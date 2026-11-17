# Infrastructure: system clock

`internal/infrastructure/system/clock.go`. `Clock` implements the exported level 3 port `clock.Clock` from `application/ports/clock`, using the machine's time.

The port is exported, so this package can name it and check the contract at compile time. Unexported ports in `usecase` packages cannot be checked this way.

## clock.go

```go
package system

import (
	"time"

	"internal/application/ports/clock"
)

// Compile-time check: the build fails here if Clock stops satisfying the port.
var _ clock.Clock = (*Clock)(nil)

type Clock struct{}

func NewClock() *Clock {
	return &Clock{}
}

// Now returns UTC: the application stores and compares instants in UTC,
// whatever the time zone of the machine.
func (c *Clock) Now() time.Time {
	return time.Now().UTC()
}
```

## What stays out of this package

- Deciding which moment to record (`CreatedAt`, `UpdatedAt`, `EmailVerifiedAt`): the use case.
- Formatting a time for display: delivery.
- A fixed clock for tests: the test files of the use cases, see `application-clock-port-example.md`.
