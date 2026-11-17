# Application User: shared ports and errors

Package `user` (`internal/application/usecase/user`). Two files shared by the user use cases: the non-repository ports that several of them call (level 2), and the application errors.

The domain package `internal/domain/user` is imported without an alias: a package's own name is not an identifier in its files, so `user.User` and `user.ParseEmail` refer to the domain even inside `package user`.

## ports.go

```go
package user

import (
	"context"
	"uuid"

	"internal/domain/user"
)

type passwordHasher interface {
	Hash(ctx context.Context, password user.Password) (user.PasswordHash, error)
}

type avatarStorer interface {
	Store(ctx context.Context, userID uuid.UUID, filePath string) (avatarKey string, err error)
}
```

Both are called by `CreateUserUC` and `UpdateUserUC`. Go forbids declaring `passwordHasher` twice in the same package, so it is declared once here. `avatarDeleter` is called only by `UpdateUserUC`, so it stays in `update_user.go`.

`passwordHasher` takes a `Password` (a value that already passed the policy) and returns a `PasswordHash`, the only way to obtain one.

No repository port is here: each use case declares its own (`createUserRepository`, `updateUserRepository`), with only the methods it calls.

## errors.go

```go
package user

import "errors"

// Application errors: failures of the flow, not business rules.
// ErrUserNotFound is returned by the infrastructure when a lookup finds nothing.
// Invalid emails and passwords are domain errors (user.ErrInvalidEmail,
// user.ErrPasswordTooShort) returned as they are by ParseEmail and ParsePassword.
var (
	ErrUserNotFound        = errors.New("user not found")
	ErrEmailAlreadyExists  = errors.New("user email already exists")
	ErrAvatarFilePathEmpty = errors.New("user avatar file path can not be empty")
	ErrUserIDEmpty         = errors.New("user id can not be empty")
	ErrNothingToUpdate     = errors.New("nothing to update: provide an email, a password or an avatar")
)
```
