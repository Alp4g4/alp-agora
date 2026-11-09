---
name: go-clean-arch-infrastructure
description: Rules for the infrastructure layer of a Go clean architecture project, defining what it must contain (implementations of application ports, database and external API clients, persistence models and their mapping to domain entities, translation of driver errors into application errors) and what it must never contain (business rules, use case orchestration, transport or presentation logic). Use when implementing a repository or external service port, writing database or third-party client code, or reviewing the boundary between infrastructure and the application layer.
---

# Go Clean Architecture: Infrastructure Layer

The infrastructure layer is the driven side of the application: it does what the application asks through its ports, and nothing more. It talks to databases, external APIs, queues, the file system, and libraries, and hides all of them behind the ports the application defined.

## Dependency rule

```
infrastructure → application → domain
```

- Infrastructure imports the **application** (its ports and application errors) and the **domain** (entities and value objects used in port signatures).
- Infrastructure never imports delivery, and delivery never imports infrastructure. Only the composition root (`main`) knows both.
- The application never imports infrastructure. It only sees the ports.

## Must contain

- **Port implementations**: concrete types that satisfy the application's ports (`postgres.UserStore` implements `userGetter` and `userUpdater`, `bcrypt.PasswordHasher` implements `passwordHasher`).
- **Drivers and clients**: database access, HTTP clients, SMTP, queue and cache clients, wrapped by the types above.
- **Persistence models**: structs shaped for the storage (with `db:` / `gorm:` / `json:` tags), separate from domain entities.
- **Casting**: a Go type conversion between a persistence or API model and the domain entity (`user.User(model)`, `userModel(entity)`), used first whenever the two have an identical structure.
- **Mapping**: functions that convert persistence or API models to domain entities and back (`toDomain`, `fromDomain`), used only when casting is not possible.
- **Error translation**: driver errors turned into application errors (`sql.ErrNoRows` → `ErrNotFound`, unique violation → `ErrConflict`).
- **Transaction mechanics**: the implementation of the transaction port, including how a transaction is carried to the repositories.

## Must never contain

- **Business rules.** No status checks, limits, or state transitions. Infrastructure stores and fetches what it is given. If an `if` expresses a business invariant, it belongs to the domain.
- **Use case orchestration.** No calling several ports in sequence to achieve an intent, no calling use cases. Sequencing is the use case's job.
- **Port definitions.** The interfaces the application consumes are defined in the application layer. Infrastructure may declare small unexported interfaces for its own driver dependencies, never for the application.
- **Transport or presentation logic.** No HTTP handlers, routing, request parsing, response building, or status codes. That is the delivery layer.
- **Leaked driver types.** No `*sql.Rows`, `*sql.Tx`, driver errors, or persistence models in the return values of a port method. Only domain types, application types, and primitives cross the boundary.
- **Tags or storage details on domain types.** The domain stays free of `db:` and `json:` tags. Mapping is done here.

## Design rules

1. **Implement the ports, do not shape them.** The signature comes from the application. If the implementation is awkward, change the port in the application layer, not the contract's meaning here.
2. **One type per technology and concept, many methods.** A single `postgres.UserStore` struct can implement `GetUser`, `UpdateUser`, and `DeleteUser`, and so satisfy every single-method port and composite at once. The one-method rule applies to interfaces, not to the concrete types that implement them.
3. **Persistence models are separate from domain entities.** Keep a private model struct with the storage tags. Never put storage tags on a domain entity, and never return a persistence model.
4. **Cast first, map only when casting is impossible.** Shape the model like the entity whenever the storage allows it, so one type conversion replaces the mapper:
   ```go
   // Same field names, same order, same types as user.User. Only the tags differ.
   type userModel struct {
   	ID              uuid.UUID            `db:"id"`
   	Email           user.Email     `db:"email"`
   	EmailVerifiedAt *time.Time           `db:"email_verified_at"`
   	PasswordHash    user.PasswordHash `db:"password_hash"`
   	AvatarKey       *string              `db:"avatar_key"`
   }

   u := user.User(model) // model → entity
   m := userModel(u)           // entity → model
   ```
   Go ignores struct tags in a conversion, but requires the same field names, order, and types. So the model uses the domain's own types (`user.Email`, not `string`). The benefit is a compile-time guarantee: if a field is added, removed, renamed, or retyped in the entity, the conversion stops compiling and points straight at the model to update. A hand-written mapper would silently keep compiling.
   Write a mapper (`toDomain` / `fromDomain`) only when a cast cannot work: the storage shape differs (flattened value object such as `Money` as amount and currency columns, JSON column, joined or denormalized data), a field needs a different type (time stored as an integer), or the driver cannot scan the domain type. Keep the mapper next to the model and explain in a comment why a cast was not possible.
   Data read from storage is trusted: it was validated before it was written, so a cast or a mapper converts stored strings into value objects (`user.Email(row.Email)`) without calling `ParseEmail` again. The only exception is building a `PasswordHash` from a freshly hashed password, which only the hasher implementation does.
5. **Translate errors at the boundary.** Convert driver errors to application errors and wrap them with `%w` and context (`fmt.Errorf("selecting user %s: %w", id, err)`). A caller must be able to use `errors.Is` without knowing the driver.
6. **Take dependencies and configuration through the constructor.** `NewUserStore(db *sql.DB)`. Do not read environment variables, parse config files, or use globals inside infrastructure code. Loading config is the composition root's job.
7. **Carry transactions through `context.Context`.** The transaction port starts a transaction and stores it in the context. Repository methods look it up and use it when present, otherwise use the plain connection. This keeps `*sql.Tx` out of the application layer.
8. **Honor the context.** Every port method takes `ctx` first, and passes it to the driver so cancellation and deadlines work.
9. **Check the contract at compile time.** For ports exported from `application/ports`, add `var _ ports.Clock = (*SystemClock)(nil)`. Unexported ports in `usecase` packages cannot be named from outside, so the check happens when the composition root wires the types together.
10. **Group by technology, not by port.** One package per driver (`postgres`, `smtp`, `bcrypthasher`), mirroring the domain concepts inside it.
11. **Test against the real technology.** Verify repositories with integration tests on a real database (a container), and clients against a real or recorded service. A mock of the driver proves nothing about the SQL.

## Suggested layout

```
internal/
└── infrastructure/
    ├── postgres/
    │   ├── user_store.go        # implements the user ports
    │   ├── user_model.go        # persistence model (cast, or mapper if needed)
    │   ├── order_store.go
    │   ├── errors.go            # driver error translation
    │   └── transactor.go        # transaction port implementation
    ├── bcrypthasher/
    │   └── password_hasher.go
    ├── smtp/
    │   └── email_sender.go
    └── system/
        └── clock.go             # implements ports.Clock
```

The composition root (`cmd/<app>/main.go`) builds the concrete types and passes them to the use case constructors. It is the only place where application and infrastructure meet.

## References

Complete examples implementing the ports of the `user` use cases from `go-clean-arch-application`, on the domain `user` package from `go-clean-arch-domain`:

- `references/infrastructure-jsonfile-example.md`: a JSON file `UserStore` satisfying several one-method ports, a model cast to the entity, error translation, and the mapper fallback.
- `references/infrastructure-bcrypt-hasher-example.md`: a `Hasher` building a `PasswordHash` from a `Password`, with configuration passed through the constructor.

## Quick check

Before adding code to infrastructure, ask:

1. Is there a business decision in it? If it would be true regardless of the storage, move it to the domain.
2. Does a port method return anything that reveals the driver (a `sql` type, a driver error, a persistence model)? If so, map or translate it before returning.
3. Could the database be replaced by another one without touching the application or the domain? If not, storage details are leaking inward.
