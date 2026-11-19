# Application

The application layer sits between the domain and the outside world. It describes what the application does: one use case per user intent, orchestrating domain objects and ports. It holds no business rule of its own and knows nothing about how data is stored or delivered.

- [Must contain](#must-contain)
- [Must never contain](#must-never-contain)
- [Design rules](#design-rules)
- [Where a port is declared](#where-a-port-is-declared)
- [Returning a result or presenting it?](#returning-a-result-or-presenting-it)
- [Quick check](#quick-check)

## Must contain

- **Use cases**: one per user intent (`CreateUserUC`, `UpdateUserUC`, `CancelOrderUC`). Each one loads, calls the domain, saves, and triggers side effects.
- **Ports**: interfaces declared here and implemented in infrastructure. Three kinds:
  - **Repository ports**: the persistence a use case needs, one interface per use case (`createUserRepository`, `updateUserRepository`). Signatures use domain entities.
  - **Other ports (gateways)**: a capability owned by someone else, one method each (`passwordHasher`, `avatarStorer`, `paymentRefunder`). Signatures may use small use-case-specific types.
  - **Output ports (optional)**: a presenter interface the use case calls to hand out its result (`userCreatedPresenter`). Only for streaming or multiple outputs, see "Returning a result or presenting it?".
- **Input and output types**: plain structs for what a use case receives and returns, when the domain entity is not the right shape.
- **Application errors**: failures that are not business rules (`ErrUserNotFound`, `ErrEmailAlreadyExists`).

## Must never contain

- **Infrastructure code.** No SQL, ORM, HTTP clients, queue clients, file system access, or environment variables, and no `*sql.DB` or third-party client in a use case's fields.
- **Concrete implementations of ports.** `postgres.UserStore` and `bcrypthasher.Hasher` live in infrastructure.
- **Transport or presentation concerns.** No status codes, no `json:` or `db:` tags, no formatting for display, no HTML or response building. Delivery maps to and from transport models.
- **An interface shared by several use cases** (`UserRepository`, `UserService`). It grows with every use case, hides what each one really needs, and forces every fake to implement methods its use case never calls.
- **A port "just in case".** A port exists because a use case calls it today.

## Design rules

1. **One use case, one intent.** A struct named after the intent with the `UC` suffix (`CreateUserUC`), its ports as fields, and one public method, `Execute`. Fields hold interfaces, never concrete types. Keep unrelated intents in separate use cases.
2. **A use case declares its own repository port**, unexported, named after the use case, with only the methods it calls:
   ```go
   // create_user.go
   type createUserRepository interface {
   	ExistsUserByEmail(ctx context.Context, email user.Email) (bool, error)
   	CreateUser(ctx context.Context, u user.User) error
   }

   // update_user.go
   type updateUserRepository interface {
   	GetUser(ctx context.Context, id uuid.UUID) (user.User, error)
   	ExistsUserByEmail(ctx context.Context, email user.Email) (bool, error)
   	UpdateUser(ctx context.Context, u user.User) error
   }
   ```
   Methods are named with their entity (`GetUser`, not `Get`), so one store type in infrastructure satisfies the repository ports of every use case at once, and two entities never clash on the same method name. The fake of a use case implements exactly what it touches.
3. **Any other port has one method**, named after what it does, as `io.Reader`: `passwordHasher` with `Hash`, `avatarStorer` with `Store`. When a use case needs two methods of the same dependency, it declares a composite that embeds both, named by joining their roles:
   ```go
   type avatarStorerDeleter interface {
   	avatarStorer
   	avatarDeleter
   }
   ```
4. **Check the shape of the input, parse its values.** `Input.Validate()` checks only what no value object covers (an empty file path, nothing to update). Values with a business meaning go through the domain's `ParseX` at the start of `Execute`.
5. **The use case supplies time and IDs; the domain never generates them.** Time comes from the `clock.Clock` port, in UTC, so tests can pin it. IDs are UUID v7, generated in the use case with `uuid.NewV7()` from the standard library `uuid` package (no port, no error to handle). Both are passed to the domain as arguments or set on the entity.
6. **Call domain methods for rules, assign plain fields directly.** If a domain method exists for the change (`order.Cancel()`, `u.ChangeEmail(email)`), the use case calls it and never sets those fields itself. If no rule exists (`u.AvatarKey = &key`), assign directly and do not invent a method.
7. **Keep the happy path linear.** Validate, load, call the domain, save, then side effects. Return errors early, wrapped with what the step was doing (`fmt.Errorf("loading user: %w", err)`). Domain errors from `ParseX` and domain methods are returned as they are.
8. **Test with fakes of the ports.** A use case is unit-tested with in-memory fakes declared in its test file, with no database and no network. A fixed clock pins `CreatedAt` and `UpdatedAt`.

## Where a port is declared

```
internal/application/
├── ports/                       # 3. needed by several concepts: exported, one package per capability
│   └── clock/clock.go           #    clock.Clock
└── usecases/
    └── user/
        ├── ports.go             # 2. non-repository ports shared by the user use cases (passwordHasher, avatarStorer)
        ├── errors.go            #    application errors
        ├── create_user.go       # 1. createUserRepository, and the ports only this use case calls
        └── update_user.go       # 1. updateUserRepository, avatarDeleter, avatarStorerDeleter
```

1. **In the use case file**: its repository port, always, and any other port only this use case calls. Unexported.
2. **In `usecases/<concept>/ports.go`**: a non-repository port that several use cases of the same concept call. Go forbids two declarations of the same name in one package, so it is declared once here. Unexported. A repository port never moves here.
3. **In `application/ports/<capability>/`**: a port that several concepts need, in a package named after what it provides (`clock`). Exported, since other packages must name it.

Start at level 1. Move a port to level 2 when a second use case of the concept calls it, and to level 3 when a second concept does.

When a port signature needs a struct parameter (too many arguments for a plain list), the struct is declared next to the port and exported, so infrastructure can build it. Name it after what it is (`UserSearch`, `Page`), not after the method. If its fields form a business concept (an address, a period), it is a value object in the domain instead.

## Returning a result or presenting it?

**Default: return the result.** `Execute` returns the entity or an output struct, plus an `error`, and the caller decides how to show it:

```go
func (uc *CreateUserUC) Execute(ctx context.Context, input CreateUserInput) (user.User, error)
```

**Optional: an output port.** Use one only when returning cannot express the flow:

- the use case produces several outputs over time (streaming, progress)
- the same use case feeds several output channels at once
- the use case must decide when, and how many times, to emit a result

When unsure, return: switching later is a contained change. When used, the output port follows the rules of any port, with differences:

```go
// create_user.go: unexported, one method, named after what it presents
type userCreatedPresenter interface {
	PresentUserCreated(ctx context.Context, u user.User)
}
```

- **No return value.** Data goes outward and nothing comes back.
- **The parameter** is the entity, or an output struct when the result is more than one entity.
- **Errors still go through `Execute`'s `error` return.**
- **The implementation holds the result**, so delivery builds one per request. A shared instance is unsafe under concurrency.

| | Return the result | Output port |
|---|---|---|
| Who controls the output | the caller, after the call | the use case, during the call |
| Number of outputs | exactly one | zero, one, or many |
| Tests | assert on the return value | needs a fake presenter |
| Extra code | none | one port and one implementation per use case |

## Quick check

Before adding code to a use case, ask:

1. Does the use case declare its own repository port, with only the methods it calls, named with their entity?
2. Is every other port one method, or a composite of one-method ports, declared at the narrowest level?
3. Wherever the domain has a method for a change, is it called instead of setting the fields?
4. Do time and IDs come from the use case (`clock.Clock`, `uuid.NewV7()`), never from the domain?
5. Can the use case be tested with fakes of its ports only?
