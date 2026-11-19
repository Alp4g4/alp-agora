# Application: clock port

`internal/application/ports/clock/clock.go`. A level 3 port: every use case that records a moment needs it, across concepts (users, orders), so it lives in its own capability package and is exported. `CreateUserUC` and `UpdateUserUC` take it through their constructor.

The use case reads the time from this port and passes it to the domain, which never calls `time.Now()` itself. A test passes a fixed clock and can assert on `CreatedAt` and `UpdatedAt`.

## clock.go

```go
package clock

import "time"

// Clock gives the current time, always in UTC.
type Clock interface {
	Now() time.Time
}
```

## A fixed clock for tests

Tests of the use cases pin the time with a fake, declared in the test file that needs it:

```go
type fixedClock struct{ now time.Time }

func (c fixedClock) Now() time.Time { return c.now }

// NewCreateUserUC(users, hasher, avatars, fixedClock{now: time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC)})
```

## Why a package of its own

- **Level 3**: the user and order use cases both need it, so it cannot live in `usecases/user/ports.go`.
- **One capability, one package**: `clock.Clock` says what it provides. A flat `ports` package would make every use case import every shared interface.
- **Exported**: the use case packages must name it, and infrastructure checks its implementation at compile time (`var _ clock.Clock = (*Clock)(nil)`).
