# Infrastructure: bcrypt password hasher

`internal/infrastructure/bcrypthasher/password_hasher.go`. It implements two one-method ports from the application layer:

- `passwordHasher` (`Hash`), declared in `usecases/user/ports.go`.
- A second port for checking a password at login (`passwordVerifier`), declared by the login use case. It is separate from `passwordHasher`, because a port other than a repository has one method.

The ports are unexported, so this package cannot name them and no `var _ ... = ` check is possible. The compiler checks the contract when `main` passes `*Hasher` to the use case constructors.

The package is `bcrypthasher`, not `bcrypt`, so it does not clash with the `golang.org/x/crypto/bcrypt` import.

## password_hasher.go

```go
package bcrypthasher

import (
	"context"
	"errors"
	"fmt"

	"golang.org/x/crypto/bcrypt"

	"internal/domain/user"
)

type Hasher struct {
	cost int
}

func NewHasher() *Hasher {
	return &Hasher{cost: bcrypt.DefaultCost}
}

// The cost comes from the constructor: config is loaded by main, never read here.
func NewHasherWithCost(cost int) *Hasher {
	return &Hasher{cost: cost}
}

// Hash takes a Password (already checked against the policy by the domain) and returns
// a PasswordHash. This is the only place allowed to build a PasswordHash from a string.
// bcrypt is CPU-bound and has no context support: ctx is accepted to satisfy the port.
func (h *Hasher) Hash(_ context.Context, password user.Password) (user.PasswordHash, error) {
	hashed, err := bcrypt.GenerateFromPassword([]byte(password), h.cost)
	if err != nil {
		return "", fmt.Errorf("generating bcrypt hash: %w", err)
	}

	return user.PasswordHash(hashed), nil
}

// Verify takes the raw string, not a Password: a password created under an older
// policy must still be accepted at login. A wrong password is not an error,
// it returns false; only a technical failure returns an error.
func (h *Hasher) Verify(_ context.Context, hash user.PasswordHash, password string) (bool, error) {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	if errors.Is(err, bcrypt.ErrMismatchedHashAndPassword) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("comparing bcrypt hash: %w", err)
	}

	return true, nil
}
```

## What stays out of this package

- The password policy (minimum length): `user.ParsePassword`. The hasher never checks it.
- Deciding when to hash, and what to do on a wrong password: the use cases.
- The port interfaces: the application layer.
