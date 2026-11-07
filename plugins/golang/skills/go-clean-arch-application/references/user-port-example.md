# Application User: shared ports

Package `user` (`internal/application/usecase/user`). These files are shared by the user use cases, so their ports are level 2: unexported, in the package, one method each.

`userEmailChecker` started in `create_user.go` (level 1). `update_user.go` needed it too, so it was promoted here.

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

type userEmailChecker interface {
	ExistsByEmail(ctx context.Context, email user.Email) (bool, error)
}
```

`passwordHasher` takes a `Password` (a value that already passed the policy) and returns a `PasswordHash`, the only way to obtain one. `userEmailChecker` takes an `Email`, not a `string`: the caller has already parsed it.
