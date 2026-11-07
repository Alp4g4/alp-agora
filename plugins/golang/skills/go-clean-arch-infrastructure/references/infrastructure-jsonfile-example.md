# Infrastructure: JSON file user store

`internal/infrastructure/jsonfile/user_store.go`. One concrete type, `UserStore`, keeps users in a JSON file and implements several one-method ports of the application layer at once:

| Method | Application port | Declared in |
|---|---|---|
| `Save` | `userSaver` | `create_user.go` (level 1) |
| `ExistsByEmail` | `userEmailChecker` | `ports.go` (level 2) |
| `FindByID` | `userFinder` | `update_user.go` (level 1) |
| `Update` | `userUpdater` | `update_user.go` (level 1) |

The ports are unexported, so this package cannot name them. The compiler checks them when `main` passes `*UserStore` to the use case constructors.

The domain package is imported without an alias (`user.User`, `user.Email`). Only the application package gets one, `usecaseuser`, because it is used for a single error and this file already uses `user` for the domain.

## user_model.go

The persistence model has the same field names, order and types as `user.User`. Only the tags differ, so a cast replaces a mapper and the compiler fails if the entity changes.

```go
package jsonfile

import (
	"time"
	"uuid"

	"internal/domain/user"
)

// Same shape as user.User: the cast works. Only the json tags are specific to the file.
type userModel struct {
	ID              uuid.UUID               `json:"id"`
	Email           user.Email        `json:"email"`
	EmailVerifiedAt *time.Time              `json:"email_verified_at"`
	PasswordHash    user.PasswordHash `json:"password_hash"`
	AvatarKey       *string                 `json:"avatar_key"`
}
```

## user_store.go

```go
package jsonfile

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sync"
	"uuid"

	usecaseuser "internal/application/usecase/user"
	"internal/domain/user"
)

type UserStore struct {
	mu   sync.Mutex
	path string
}

// The path comes from the constructor: config is loaded by main, never read here.
func NewUserStore(path string) *UserStore {
	return &UserStore{path: path}
}

func (s *UserStore) Save(ctx context.Context, u user.User) error {
	// file access has no context support: honor cancellation before starting
	if err := ctx.Err(); err != nil {
		return err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	models, err := s.load()
	if err != nil {
		return fmt.Errorf("loading users: %w", err)
	}

	models = append(models, userModel(u)) // entity → model, a cast

	if err := s.write(models); err != nil {
		return fmt.Errorf("writing users: %w", err)
	}

	return nil
}

func (s *UserStore) ExistsByEmail(ctx context.Context, email user.Email) (bool, error) {
	if err := ctx.Err(); err != nil {
		return false, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	models, err := s.load()
	if err != nil {
		return false, fmt.Errorf("loading users: %w", err)
	}

	for _, m := range models {
		if m.Email == email {
			return true, nil
		}
	}

	return false, nil
}

func (s *UserStore) FindByID(ctx context.Context, id uuid.UUID) (user.User, error) {
	if err := ctx.Err(); err != nil {
		return user.User{}, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	models, err := s.load()
	if err != nil {
		return user.User{}, fmt.Errorf("loading users: %w", err)
	}

	for _, m := range models {
		if m.ID == id {
			// Stored data is trusted: the cast does not call ParseEmail again.
			return user.User(m), nil // model → entity, a cast
		}
	}

	// nothing found: reported as an application error, not a file detail
	return user.User{}, usecaseuser.ErrUserNotFound
}

func (s *UserStore) Update(ctx context.Context, u user.User) error {
	if err := ctx.Err(); err != nil {
		return err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	models, err := s.load()
	if err != nil {
		return fmt.Errorf("loading users: %w", err)
	}

	for i, m := range models {
		if m.ID == u.ID {
			models[i] = userModel(u)

			if err := s.write(models); err != nil {
				return fmt.Errorf("writing users: %w", err)
			}

			return nil
		}
	}

	return usecaseuser.ErrUserNotFound
}

// load returns an empty list when the file does not exist yet.
func (s *UserStore) load() ([]userModel, error) {
	data, err := os.ReadFile(s.path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	var models []userModel
	if err := json.Unmarshal(data, &models); err != nil {
		return nil, err
	}

	return models, nil
}

// write replaces the file atomically: a crash never leaves a half-written file.
func (s *UserStore) write(models []userModel) error {
	data, err := json.MarshalIndent(models, "", "  ")
	if err != nil {
		return err
	}

	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}

	return os.Rename(tmp, s.path)
}
```

## When a cast is not possible

Cast first, map only when casting is impossible. If the file had to keep `id` as a plain string and the time as a Unix timestamp, the model would no longer match the entity, and a mapper takes over:

```go
type userModel struct {
	ID              string  `json:"id"`
	Email           string  `json:"email"`
	EmailVerifiedAt *int64  `json:"email_verified_at"` // Unix seconds
	PasswordHash    string  `json:"password_hash"`
	AvatarKey       *string `json:"avatar_key"`
}

func toEntity(m userModel) (user.User, error) {
	id, err := uuid.Parse(m.ID)
	if err != nil {
		return user.User{}, fmt.Errorf("parsing user id %q: %w", m.ID, err)
	}

	var verifiedAt *time.Time
	if m.EmailVerifiedAt != nil {
		t := time.Unix(*m.EmailVerifiedAt, 0).UTC()
		verifiedAt = &t
	}

	return user.User{
		ID:              id,
		Email:           user.Email(m.Email),
		EmailVerifiedAt: verifiedAt,
		PasswordHash:    user.PasswordHash(m.PasswordHash),
		AvatarKey:       m.AvatarKey,
	}, nil
}
```

Keep the mapper next to the model, with a comment saying why a cast was not possible.

## What stays out of this package

- The port interfaces: the application layer.
- Checking that a new email is not already taken, and choosing what to do when it is: `CreateUserUC` and `UpdateUserUC`. The store only answers `ExistsByEmail`.
- `ChangeEmail` and the rule that resets `EmailVerifiedAt`: the domain. The store saves whatever it is given.
- The file path and its location: `main`.
