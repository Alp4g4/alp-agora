# Update User use case

`internal/application/usecase/user/update_user.go`. It shows the rule from the skill about calling domain methods:

- **Email**: a business rule exists (a new email must be verified again), so the use case calls `u.ChangeEmail(email)` and never sets `u.Email` itself.
- **Password hash and avatar key**: plain data with no rule, assigned directly.

Ports used only here are defined in this file (level 1): `userFinder`, `userUpdater`, `avatarDeleter`, and the composite `avatarStorerDeleter`, which embeds `avatarStorer` (from `ports.go`) and `avatarDeleter`. The composite name joins the roles of the embedded ports. The clock is a level 3 port, `clock.Clock`, see `clock-port-example.md`.

## update_user.go

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

type userFinder interface {
	FindByID(ctx context.Context, id uuid.UUID) (user.User, error)
}

type userUpdater interface {
	Update(ctx context.Context, u user.User) error
}

type avatarDeleter interface {
	Delete(ctx context.Context, avatarKey string) error
}

type avatarStorerDeleter interface {
	avatarStorer
	avatarDeleter
}

type UpdateUserUC struct {
	userFinder       userFinder
	userUpdater      userUpdater
	userEmailChecker userEmailChecker
	passwordHasher   passwordHasher
	avatarStore      avatarStorerDeleter
	clock            clock.Clock
}

func NewUpdateUserUC(finder userFinder, updater userUpdater, emailChecker userEmailChecker, hasher passwordHasher, avatars avatarStorerDeleter, clk clock.Clock) *UpdateUserUC {
	return &UpdateUserUC{
		userFinder:       finder,
		userUpdater:      updater,
		userEmailChecker: emailChecker,
		passwordHasher:   hasher,
		avatarStore:      avatars,
		clock:            clk,
	}
}

type UpdateUserInput struct {
	ID             uuid.UUID
	Email          *string
	Password       *string
	AvatarFilePath *string
}

func (i UpdateUserInput) Validate() error {
	if i.ID == (uuid.UUID{}) {
		return ErrUserIDEmpty
	}

	if i.Email == nil && i.Password == nil && i.AvatarFilePath == nil {
		return ErrNothingToUpdate
	}

	if i.AvatarFilePath != nil && strings.TrimSpace(*i.AvatarFilePath) == "" {
		return ErrAvatarFilePathEmpty
	}

	return nil
}

func (uc *UpdateUserUC) Execute(ctx context.Context, input UpdateUserInput) (user.User, error) {
	zero := user.User{}

	if err := input.Validate(); err != nil {
		return zero, err
	}

	u, err := uc.userFinder.FindByID(ctx, input.ID)
	if err != nil {
		return zero, fmt.Errorf("finding user: %w", err)
	}

	if input.Email != nil {
		email, err := user.ParseEmail(*input.Email)
		if err != nil {
			return zero, err
		}

		// business rule (verification reset, unchanged email): the domain decides.
		// Called before the duplicate check, so the user's own email is not reported as taken.
		if err := u.ChangeEmail(email); err != nil {
			return zero, err
		}

		exists, err := uc.userEmailChecker.ExistsByEmail(ctx, email)
		if err != nil {
			return zero, fmt.Errorf("checking duplicate user email: %w", err)
		}

		if exists {
			return zero, ErrEmailAlreadyExists
		}
	}

	if input.Password != nil {
		password, err := user.ParsePassword(*input.Password)
		if err != nil {
			return zero, err
		}

		passwordHash, err := uc.passwordHasher.Hash(ctx, password)
		if err != nil {
			return zero, fmt.Errorf("hashing password: %w", err)
		}

		// plain data with no rule: assigned directly, no domain method
		u.PasswordHash = passwordHash
	}

	previousAvatarKey := u.AvatarKey
	var newAvatarKey *string

	if input.AvatarFilePath != nil {
		key, err := uc.avatarStore.Store(ctx, u.ID, *input.AvatarFilePath)
		if err != nil {
			return zero, fmt.Errorf("storing avatar: %w", err)
		}

		newAvatarKey = &key
		u.AvatarKey = newAvatarKey
	}

	u.UpdatedAt = uc.clock.Now()

	if err := uc.userUpdater.Update(ctx, u); err != nil {
		if newAvatarKey != nil {
			_ = uc.avatarStore.Delete(ctx, *newAvatarKey)
		}

		return zero, fmt.Errorf("updating user: %w", err)
	}

	// the user is already updated: a leftover old file must not fail the call
	if newAvatarKey != nil && previousAvatarKey != nil {
		_ = uc.avatarStore.Delete(ctx, *previousAvatarKey)
	}

	return u, nil
}
```
