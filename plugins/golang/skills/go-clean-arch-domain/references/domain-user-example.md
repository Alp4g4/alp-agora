# Domain User

Package `user`: an entity with exported fields, a validated value object, domain errors, and one business operation (`ChangeEmail`) because it carries a rule that must hold for every use case.

## user.go

```go
package user

import (
	"time"
	"uuid"
)

// User is a plain entity: exported fields, no getters, no setters.
type User struct {
	ID              uuid.UUID
	Email           Email
	EmailVerifiedAt *time.Time
	PasswordHash    PasswordHash
	AvatarKey       *string
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

// ChangeEmail carries a business rule (a new email must be verified again),
// so it lives in the domain and is shared by every use case that changes an email.
func (u *User) ChangeEmail(newEmail Email) error {
	if newEmail == u.Email {
		return ErrEmailUnchanged
	}
	u.Email = newEmail
	u.EmailVerifiedAt = nil
	return nil
}
```

`ChangeEmail` does not re-validate `newEmail`: the caller obtained it from `ParseEmail`, which is the single validation point. Never write `Email(rawString)` directly.

Not in the domain: `u.AvatarKey = &key`. Plain data without a rule is assigned directly by the use case.

`CreatedAt` and `UpdatedAt` are plain fields too. The use case sets them from its clock: the domain never reads the current time, so `ChangeEmail` does not touch `UpdatedAt`.

## email.go

```go
package user

import (
	"net/mail"
	"strings"
)

type Email string

// ParseEmail validates and normalizes a raw email.
// Any Email produced by ParseEmail is known to be valid.
func ParseEmail(rawEmail string) (Email, error) {
	trimmed := strings.TrimSpace(rawEmail)
	addr, err := mail.ParseAddress(trimmed)
	if err != nil || addr.Address != trimmed {
		return "", ErrInvalidEmail
	}
	return Email(strings.ToLower(addr.Address)), nil
}

// ValidEmail reports whether a raw email is valid, without building the value.
func ValidEmail(rawEmail string) bool {
	_, err := ParseEmail(rawEmail)
	return err == nil
}
```

## password.go

```go
package user

import "unicode/utf8"

const minPasswordLength = 6

// Password is a plain password that satisfies the password policy.
// It is transient: never stored on User, never logged. It only exists between
// ParsePassword and the PasswordHasher port, which turns it into a PasswordHash.
// Shared by every use case that sets a password (RegisterUser, ChangePassword).
type Password string

func ParsePassword(rawPassword string) (Password, error) {
	if utf8.RuneCountInString(rawPassword) < minPasswordLength {
		return "", ErrPasswordTooShort
	}
	return Password(rawPassword), nil
}
```

## password_hash.go

```go
package user

// PasswordHash is an opaque, already-hashed password.
// The domain does not know the algorithm: it only knows the field never holds a plain password.
// A PasswordHash is only ever produced by the PasswordHasher port (application layer),
// never by converting a raw string: PasswordHash("plaintext") must not appear in the code.
type PasswordHash string
```

## errors.go

```go
package user

import "errors"

var (
	ErrInvalidEmail     = errors.New("invalid email")
	ErrEmailUnchanged   = errors.New("new email is the same as the current one")
	ErrPasswordTooShort = errors.New("password is too short")
)
```

## What stays out of this package

- Persistence ports (`userGetter`, `userUpdater`, ...): application layer, next to the use cases, one method each.
- Password hashing and verification: two one-method ports defined in the application layer, `passwordHasher` (`Hash(ctx, Password) (PasswordHash, error)`) and `passwordVerifier` (`Verify(ctx, PasswordHash, string) (bool, error)`). One bcrypt or argon2 type in infrastructure implements both. The domain only defines the `PasswordHash` type.
- `json:` / `db:` tags and the mapping to API or storage models: outer layers.
- Loading the user, calling `ChangeEmail`, saving it, sending the verification email: the `ChangeUserEmail` use case.
