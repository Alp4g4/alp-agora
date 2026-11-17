# Infrastructure

The infrastructure layer is the driven side of the application: it does what the application asks through its ports, and nothing more. It talks to databases, external APIs, queues, the file system, and libraries, and hides all of them behind the ports the application declared.

## Must contain

- **Port implementations**: concrete types that satisfy the application's ports (`postgres.UserStore` satisfies `createUserRepository` and `updateUserRepository`, `bcrypthasher.Hasher` satisfies `passwordHasher`).
- **Drivers and clients for the application's outbound calls**: database access, HTTP clients of external APIs, SMTP, queue publishers, and cache clients, wrapped by the types above.
- **Persistence models**: structs shaped for the storage (with `db:` / `json:` tags), separate from domain entities.
- **Casting**: a Go type conversion between a persistence or API model and the domain entity (`user.User(model)`, `userModel(entity)`), used first whenever the two have an identical structure.
- **Mapping**: functions that convert persistence or API models to domain entities and back (`toEntity`, `fromEntity`), used only when casting is not possible.
- **Error translation**: driver errors turned into application errors (`sql.ErrNoRows` → `ErrUserNotFound`, unique violation → `ErrEmailAlreadyExists`).

## Must never contain

- **Use case orchestration.** No calling several ports in sequence to achieve an intent, no calling use cases. Sequencing is the use case's job.
- **Port definitions.** The interfaces the application consumes are declared in the application layer. Infrastructure may declare small unexported interfaces for its own driver dependencies, never for the application.
- **Transport or presentation logic.** No HTTP handlers, routing, request parsing, response building, or status codes. That is the delivery layer.

## Design rules

1. **Implement the ports, do not shape them.** The signatures come from the application. If the implementation is awkward, change the port in the application layer, not the contract's meaning here.
2. **One type per technology and concept, many methods.** A single `postgres.UserStore` has `CreateUser`, `GetUser`, `UpdateUser`, and `ExistsUserByEmail`, and so satisfies the repository port of every user use case at once. The method names come from the ports, named with their entity, so a store never has a bare `Get` or `Save`.
3. **Cast first, map only when casting is impossible.** Shape the model like the entity whenever the storage allows it, so one type conversion replaces the mapper:
   ```go
   // Same field names, same order, same types as user.User. Only the tags differ.
   type userModel struct {
   	ID              uuid.UUID         `db:"id"`
   	Email           user.Email        `db:"email"`
   	EmailVerifiedAt *time.Time        `db:"email_verified_at"`
   	PasswordHash    user.PasswordHash `db:"password_hash"`
   	AvatarKey       *string           `db:"avatar_key"`
   	CreatedAt       time.Time         `db:"created_at"`
   	UpdatedAt       time.Time         `db:"updated_at"`
   }

   u := user.User(model) // model → entity
   m := userModel(u)     // entity → model
   ```
   Go ignores struct tags in a conversion, but requires the same field names, order, and types. So the model uses the domain's own types (`user.Email`, not `string`). The benefit is a compile-time guarantee: if a field is added, removed, renamed, or retyped in the entity, the conversion stops compiling and points straight at the model to update. A hand-written mapper would silently keep compiling.

   Write a mapper (`toEntity` / `fromEntity`) only when a cast cannot work: the storage shape differs (a flattened value object such as `Money` as amount and currency columns, a JSON column, joined or denormalized data), a field needs a different type (time stored as an integer), or the driver cannot scan the domain type. Keep the mapper next to the model, with a comment saying why a cast was not possible.
4. **Only the hasher builds a `PasswordHash` from a string.** Stored data is converted to value objects without `ParseX`, since it was validated before it was written. The one value never built from a raw string is a `PasswordHash`: only the hasher implementation creates one, from a freshly hashed `Password`.
5. **Translate the errors a caller must act on.** A lookup that finds nothing returns the application's not-found error (`ErrUserNotFound`), and so does an update that matches no row. A unique violation returns the matching application error, recognized by the constraint name. Any other driver error is wrapped as it is.
6. **Honor the context, even without driver support.** Pass `ctx` to every driver call that takes one. When the driver has none (file access, bcrypt), check `ctx.Err()` before starting the work.
7. **Check exported ports at compile time.** For a port exported from `application/ports/<capability>`, add `var _ clock.Clock = (*Clock)(nil)` next to the type. Unexported ports in `usecase` packages cannot be named from outside, so the compiler checks them when `main` passes the type to a use case constructor.
8. **Name the package after the technology, without clashing with its library.** `postgres`, `smtp`, `localfs`, and `bcrypthasher` rather than `bcrypt`, so the package does not shadow the `golang.org/x/crypto/bcrypt` import.
9. **Test against the real technology.** Verify stores with integration tests on a real database (a container), and clients against a real or recorded service. A mock of the driver proves nothing about the SQL.

## Layout

```
internal/infrastructure/
├── postgres/                # or sqlite/: the engine of the project
│   ├── migrations/          # goose (go-sql)
│   ├── queries/             # sqlc queries (go-sql)
│   ├── sqlcgen/             # generated by sqlc, the persistence models
│   ├── db.go                # Open: the connection, configured once
│   ├── user_store.go        # satisfies the user repository ports
│   └── errors.go            # driver error translation
├── bcrypthasher/
│   └── password_hasher.go
├── localfs/
│   └── avatar_store.go
└── system/
    └── clock.go             # satisfies clock.Clock (application/ports/clock)
```

## Quick check

Before adding code to infrastructure, ask:

1. Do the method names and signatures come from the ports, named with their entity, without changing their meaning?
2. Is the model cast to the entity, and if a mapper is used, does a comment say why?
3. Does a missing row, or a unique violation, come back as the application error the use case expects?
4. Is it tested against the real technology rather than a mock of the driver?
