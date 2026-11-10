---
name: go-clean-arch-application
description: Rules for the application (use case) layer of a Go clean architecture project, defining what it must contain (use cases, repository and external service interfaces, input and output types, orchestration of domain objects) and what it must never contain (business rules that belong to the domain, SQL, HTTP, or other infrastructure code). Use when creating, reviewing, or refactoring use cases or their ports, or when deciding whether logic belongs in the use case or in the domain.
---

# Go Clean Architecture: Application Layer

The application layer sits between the domain and the outside world. It describes what the application does: one use case per user intent, orchestrating domain objects and ports. It holds no business rule of its own and knows nothing about how data is stored or delivered.

## Dependency rule

```
infrastructure/delivery → application → domain
```

- The application imports the **domain** and the Go standard library. It never imports infrastructure or delivery.
- Infrastructure imports the application to implement its ports, and delivery imports it to call its use cases.
- The application defines the interfaces it needs (ports). Infrastructure implements them.

## Must contain

- **Use cases**: one per user intent (`RegisterUser`, `CancelOrder`, `ChangeUserEmail`). Each one loads, calls the domain, saves, and triggers side effects.
- **Ports**: interfaces defined here and implemented in infrastructure. Every port has exactly one method. They come in two flavors:
  - **Repositories**: persistence of an aggregate, collection-like (`userGetter`, `userUpdater`, `userDeleter`), signatures use domain entities.
  - **External services (gateways)**: a capability owned by someone else, action-like (`paymentCharger`, `emailSender`, `passwordHasher`). Signatures may use small use-case-specific types.
  - **Output ports (optional)**: a presenter interface the use case calls to hand out its result (`userCreatedPresenter`). Only for streaming or multiple outputs, see "Returning a result or presenting it?".
- **Input and output types**: plain structs for what a use case receives and returns, when the domain entity is not the right shape.
- **Application errors**: failures that are not business rules (`ErrNotFound`, `ErrConflict`, `ErrUnauthorized`), wrapped with `%w` so callers can use `errors.Is` / `errors.As`.
- **Orchestration and transaction boundaries**: the order of steps, and which steps must succeed or fail together. A transaction is exposed through a port (a transaction manager or unit of work), never through `*sql.Tx`.

## Must never contain

- **Business rules.** A rule that must hold for every use case belongs to the domain. If a use case contains an `if` on a business invariant (a status check, a limit, a state transition), move it to the domain.
- **Infrastructure code.** No SQL, ORM, HTTP clients, queue clients, file system access, or environment variables.
- **Concrete implementations of ports.** `PostgresUserRepository` and `BcryptPasswordHasher` live in infrastructure.
- **Transport concerns.** No `http.Request`, `gin.Context`, gRPC types, status codes, or `json:` / `db:` tags. Delivery maps to and from transport models.
- **Presentation logic.** No formatting for display, no HTML or response building.
- **Framework or driver types.** No `*sql.DB`, `*sql.Tx`, or third-party clients in use case signatures or fields.

## Design rules

1. **One use case, one intent.** A struct with its dependencies and one public method (conventionally `Execute`). Keep unrelated intents in separate use cases.
2. **Depend on ports through the constructor.** `NewRegisterUser(creator userCreator, hasher passwordHasher) *RegisterUser`. Fields hold interfaces, never concrete types.
3. **A port has exactly one method.** Keep interfaces simple and explicit, and name them after what they do, as in the standard library's `io.Reader` and `io.Writer`. A use case that needs several capabilities takes several ports, or a composite interface built by embedding, as `io.ReadWriter` does. The composite name joins the roles of the embedded ports:
   ```go
   type userGetter interface {
   	GetUser(ctx context.Context, id user.UserID) (*user.User, error)
   }

   type userUpdater interface {
   	UpdateUser(ctx context.Context, u *user.User) error
   }

   // Composite: embeds the single-method ports, adds nothing.
   type userGetUpdater interface {
   	userGetter
   	userUpdater
   }
   ```
   Do not create a catch-all `UserRepository`: it hides what a use case really needs. A use case depends on the narrowest port that covers its needs (`userUpdater` if it only updates, `userGetUpdater` if it loads then updates). Infrastructure implements the methods on one struct, which satisfies every port and composite at once.
4. **Ports in `usecase` packages are unexported.** Interfaces in `usecase/<concept>/` (levels 1 and 2) start with a lowercase letter, so they are private to the package and cannot be depended on from outside. Only the interfaces in `application/ports/<capability>/` packages (level 3) are exported, because other packages must name them.
5. **Define each port at the narrowest level where it is used**, and promote it only when a second consumer appears (see Suggested layout). Never add a port "just in case".
   When a port signature needs a struct parameter (too many arguments for a plain list), the struct lives next to the port, exported: in the use case package for levels 1 and 2, in the capability package for level 3. Infrastructure imports that package for the struct. Name it after what it is (`UserSearch`, `Page`), not after the method. If the fields form a business concept (an address, a period), it is a value object in the domain instead.
6. **`context.Context` is the first parameter** of every use case method and every port method that does I/O.
7. **Validate at the boundary.** At the start of the use case, turn raw input into domain value objects (`ParseEmail`, `ParsePassword`). From then on, the rest of the flow trusts them.
8. **The use case supplies time and IDs; the domain never generates them.** Time comes from a `Clock` port, so tests can pin it, and is passed to the domain as an argument (in UTC). IDs may be generated directly in the use case (`uuid.New()`) without a port, then passed to the domain.
9. **Call domain methods for rules, assign plain fields directly.** If a domain method exists for the change (`order.Cancel()`, `user.ChangeEmail(e)`), the use case must call it rather than setting the fields. If no rule exists (`user.AvatarKey = &key`), assign directly and do not invent a method.
10. **Keep the happy path linear.** Load, call the domain, save, then side effects. Return errors early, wrapped with context (`fmt.Errorf("loading order: %w", err)`).
11. **Return the result by default; present through an output port only when returning is not enough.** `Execute` returns the entity or an output struct, plus an `error`. Add an output port only for streaming, progressive results, or several outputs from one use case. When unsure, return: switching later is a contained change.
12. **Test with fakes of the ports.** Use cases are unit-tested with in-memory implementations or generated mocks, with no database and no network.

## Use case or domain?

| The logic... | Goes in |
|---|---|
| is true for every use case that touches the entity | domain |
| is the sequence of steps of this one intent | use case |
| loads or saves data, calls an outside system | use case, through a port |
| assigns a plain field with no rule | use case |

If two use cases would need the same `if`, it is a domain rule.

## Returning a result or presenting it?

**Default: return the result.** The use case hands back its result and the caller decides how to show it:

```go
func (uc *CreateUserUC) Execute(ctx context.Context, input CreateUserInput) (user.User, error)
```

This is idiomatic Go, reads linearly, and is tested by asserting on the return value. The use case knows nothing about how its result is displayed.

**Optional: an output port (presenter interface).** Use one only when returning cannot express the flow:

- the use case produces several outputs over time (streaming, progress)
- the same use case feeds several output channels at once
- the use case must decide when, and how many times, to emit a result

If none of these apply, do not add the port.

When used, it follows the same rules as any port:

```go
// create_user.go, level 1: unexported, one method, named after what it presents
type userCreatedPresenter interface {
	PresentUserCreated(ctx context.Context, u user.User)
}
```

- **No return value.** A repository returns data because the use case needs it. A presenter is fire-and-forget: data goes outward and nothing comes back.
- **The parameter** is the entity, or a use-case-specific output struct when the result is more than one entity (computed fields, several entities).
- **Errors still go through `Execute`'s `error` return.** A separate `PresentError` port is possible, as its own one-method interface, but the return value is the usual choice.
- **The implementation is stateful** (it holds the result), so build one per request. A shared instance is unsafe under concurrency.

| | Return the result | Output port |
|---|---|---|
| Who controls the output | the caller, after the call | the use case, during the call |
| Number of outputs | exactly one | zero, one, or many |
| State | none | the presenter holds the result |
| Tests | assert on the return value | needs a fake presenter |
| Extra code | none | one port and one implementation per use case |

## Suggested layout

```
internal/
└── application/
    ├── ports/                      # level 3: one package per capability, never flat
    │   ├── clock/
    │   │   └── clock.go            # clock.Clock (exported)
    │   └── tx/
    │       └── runner.go           # tx.Runner (exported)
    └── usecase/
        ├── user/
        │   ├── ports.go            # level 2: shared by user use cases (userGetter, userUpdater, userGetUpdater)
        │   ├── errors.go           # application errors
        │   ├── register_user.go    # level 1: ports used only here (welcomeEmailSender)
        │   └── change_user_email.go
        └── order/
            ├── ports.go            # orderGetter, orderUpdater, orderGetUpdater
            ├── errors.go
            └── cancel_order.go
```

Use cases are grouped by business concept, mirroring the domain packages. Ports live at one of three levels:

1. **Use case**: defined in the use case file, used only by that use case (`register_user.go`). Unexported.
2. **Entity**: in `usecase/<concept>/ports.go`, shared by several use cases of the same concept. Unexported.
3. **Cross use case**: in `application/ports/<capability>/`, one package per capability, named after what it provides (`ports/clock` with `clock.Clock`, `ports/tx` with `tx.Runner`). Exported. Never put every shared interface in one flat `ports` package: a Go package name says what it provides, a flat `ports` package becomes a dumping ground, and every consumer imports everything in it.

Start at level 1. Promote a port to level 2 when a second use case of the same concept needs it, and to level 3 when a second concept needs it.

## References

Complete examples built on the domain `user` package from `go-clean-arch-domain`:

- `references/user-port-example.md`: level 2 shared ports (`passwordHasher`, `avatarStorer`, `userEmailChecker`) and application errors.
- `references/create-user-example.md`: `CreateUser`, with input parsed into `Email` and `Password` at the boundary and level 1 ports.
- `references/update-user-example.md`: `UpdateUser`, calling `ChangeEmail` for the rule and assigning plain fields directly, with a composite port.

## Quick check

Before adding code to a use case, ask:

1. Is this a business rule? If it would be true in any use case, move it to the domain.
2. Does it import anything outside the standard library or the domain? If so, it belongs in infrastructure behind a port.
3. Could this use case be called from an HTTP handler, a CLI, and a cron job without changes? If not, transport details are leaking in.
