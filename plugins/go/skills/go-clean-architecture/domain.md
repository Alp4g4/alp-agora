# Domain

The domain is the innermost layer. It holds the business concepts and rules, and knows nothing about how they are stored, exposed, or orchestrated.

## Must contain

- **Entities**: objects with an identity and a lifecycle (`User`, `Order`). Plain structs with exported fields.
- **Value objects**: immutable, compared by value (`Email`, `Money`). Validated by domain functions (`ParseEmail`, `ValidEmail`).
- **Domain errors**: sentinel errors or typed errors expressing business failures (`ErrInsufficientFunds`, `ErrInvalidEmail`).
- **Business rules**: logic that is true regardless of the use case, as methods on entities and value objects.

## Must never contain

- **Interfaces for persistence or external services.** Repository and gateway ports live in the application layer, in the use case that consumes them.
- **Use cases or orchestration.** Coordinating entities and calling repositories belong to the application layer.
- **Infrastructure concerns.** No SQL, ORM tags or models, HTTP, gRPC, queues, file system, environment variables, or config loading.
- **Serialization tags.** No `json:`, `db:`, `gorm:`, or `yaml:` tags. Mapping to and from transport and storage models happens in outer layers.
- **Framework or third-party types.** No `gin.Context`, `*sql.DB` from a library, and so on.
- **Hidden side effects.** No logging, no `time.Now()` calls inside business rules (pass the time in as an argument), no global state.

## Design rules

1. **Entities have exported fields.** No getters, no setters, no `SetX` that only assigns. Plain data is read and written directly.
2. **Business operations are methods named by intent** (`order.Cancel()`, `user.ChangeEmail(e)`), only when a business rule or state transition is involved. Do not invent a method for a plain field update.
3. **No entity constructor until creation carries a rule.** Building an entity with a struct literal in the use case is fine while creation is plain field assignment. Add `NewX(...) X` to the domain only when creation has a rule (an initial status, a default value, a field that must start empty) or when a second use case creates the same entity. The constructor then becomes the single place for that rule. Ids and timestamps are passed in as arguments, since the domain cannot generate them. Do not add a constructor that only copies its arguments into fields.
4. **Value objects are validated by domain functions.** Provide `ParseX` / `ValidX` (`ParseEmail`, `ValidEmail`) so that any value built through them is known to be valid. Domain methods that take a value object trust it and do not re-validate. Go cannot enforce this (`Email("garbage")` compiles), so the convention is: never convert a raw string to a value object directly, always go through `ParseX`.
5. **Value objects are immutable.** Methods return a new value instead of mutating.
6. **Errors are part of the domain.** Return domain errors that callers can match with `errors.Is` / `errors.As`. Do not return infrastructure errors.
7. **Keep it testable without mocks.** Domain code must be fully unit-testable with plain Go and no test doubles.

## Quick check

Before adding code to the domain, ask:

1. Would this still be true if the app had no database, no HTTP, and no UI? If not, it does not belong here.
2. Does it import anything outside the standard library or the domain? If so, move it out.
3. Does it describe *what the business is* (domain) or *what the app does* (application)? Only the former belongs here.
