# Create User use case

`internal/application/usecase/user/create_user.go`. Raw input (strings from the delivery layer) is turned into domain value objects at the start of `Execute`. After that, the flow trusts them: it never re-validates an `Email` or a `Password`.

- [The ports](#the-ports)
- [create_user.go](#create_usergo)

## The ports

- `createUserRepository`, declared in this file: the two repository methods this use case calls, `ExistsUserByEmail` and `CreateUser`.
- `passwordHasher` and `avatarStorer`, level 2, in `ports.go`: `UpdateUserUC` calls them too (see `application-user-ports-example.md`).
- `clock.Clock`, level 3 (see `application-clock-port-example.md`).

## create_user.go

```go
package user

import (
	"context"
	"fmt"
	"strings"
	"uuid"

	"internal/application/ports/clock"
	"internal/domain/user"
)

type createUserRepository interface {
	ExistsUserByEmail(ctx context.Context, email user.Email) (bool, error)
	CreateUser(ctx context.Context, u user.User) error
}

type CreateUserUC struct {
	users          createUserRepository
	passwordHasher passwordHasher
	avatarStorer   avatarStorer
	clock          clock.Clock
}

func NewCreateUserUC(users createUserRepository, hasher passwordHasher, avatars avatarStorer, clk clock.Clock) *CreateUserUC {
	return &CreateUserUC{
		users:          users,
		passwordHasher: hasher,
		avatarStorer:   avatars,
		clock:          clk,
	}
}

type CreateUserInput struct {
	Email          string
	Password       string
	AvatarFilePath *string
}

// Validate only checks what the domain cannot know about: the shape of this
// use case's input. Email and password rules live in ParseEmail and ParsePassword.
func (i CreateUserInput) Validate() error {
	if i.AvatarFilePath != nil && strings.TrimSpace(*i.AvatarFilePath) == "" {
		return ErrAvatarFilePathEmpty
	}

	return nil
}

func (uc *CreateUserUC) Execute(ctx context.Context, input CreateUserInput) (user.User, error) {
	zero := user.User{}

	if err := input.Validate(); err != nil {
		return zero, err
	}

	// Validate at the boundary: from here on, email and password are trusted.
	email, err := user.ParseEmail(input.Email)
	if err != nil {
		return zero, err
	}

	password, err := user.ParsePassword(input.Password)
	if err != nil {
		return zero, err
	}

	exists, err := uc.users.ExistsUserByEmail(ctx, email)
	if err != nil {
		return zero, fmt.Errorf("checking duplicate user email: %w", err)
	}

	if exists {
		return zero, ErrEmailAlreadyExists
	}

	passwordHash, err := uc.passwordHasher.Hash(ctx, password)
	if err != nil {
		return zero, fmt.Errorf("hashing password: %w", err)
	}

	// time comes from the clock port, in UTC, so tests can pin it
	now := uc.clock.Now()

	u := user.User{
		// UUID v7: time-ordered, so the primary key index stays compact
		ID:           uuid.NewV7(),
		Email:        email,
		PasswordHash: passwordHash,
		CreatedAt:    now,
		UpdatedAt:    now,
	}

	if input.AvatarFilePath != nil {
		avatarKey, err := uc.avatarStorer.Store(ctx, u.ID, *input.AvatarFilePath)
		if err != nil {
			return zero, fmt.Errorf("storing avatar: %w", err)
		}

		// plain data with no rule: assigned directly, no domain method
		u.AvatarKey = &avatarKey
	}

	if err := uc.users.CreateUser(ctx, u); err != nil {
		return zero, fmt.Errorf("creating user: %w", err)
	}

	return u, nil
}
```
