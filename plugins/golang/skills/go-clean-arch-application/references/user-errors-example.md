# Application User: errors

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
