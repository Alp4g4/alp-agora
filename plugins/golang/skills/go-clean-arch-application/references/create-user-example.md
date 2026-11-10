# Create User use case

`internal/application/usecase/user/create_user.go`. Raw input (strings from the delivery layer) is turned into domain value objects at the start of `Execute`. After that, the flow trusts them: it never re-validates an `Email` or a `Password`.

Ports used only here are defined in this file (level 1): `userSaver`. The shared ones (`passwordHasher`, `avatarStorer`, `userEmailChecker`) are in `ports.go`, see `user-port-example.md`. The clock is a level 3 port, `clock.Clock`, see `clock-port-example.md`.

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

type userSaver interface {
	Save(ctx context.Context, u user.User) error
}

type CreateUserUC struct {
	userSaver        userSaver
	userEmailChecker userEmailChecker
	passwordHasher   passwordHasher
	avatarStorer     avatarStorer
	clock            clock.Clock
}

func NewCreateUserUC(saver userSaver, emailChecker userEmailChecker, hasher passwordHasher, avatars avatarStorer, clk clock.Clock) *CreateUserUC {
	return &CreateUserUC{
		userSaver:        saver,
		userEmailChecker: emailChecker,
		passwordHasher:   hasher,
		avatarStorer:     avatars,
		clock:            clk,
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

	exists, err := uc.userEmailChecker.ExistsByEmail(ctx, email)
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

	// UUID v7: time-ordered, so the primary key index stays compact
	id, err := uuid.NewV7()
	if err != nil {
		return zero, fmt.Errorf("generating user id: %w", err)
	}

	// time comes from the clock port, in UTC, so tests can pin it
	now := uc.clock.Now()

	u := user.User{
		ID:           id,
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

	if err := uc.userSaver.Save(ctx, u); err != nil {
		return zero, fmt.Errorf("saving user: %w", err)
	}

	return u, nil
}
```
