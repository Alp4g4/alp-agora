# Infrastructure: local file system avatar store

`internal/infrastructure/localfs/avatar_store.go`. One concrete type, `AvatarStore`, copies avatar images into a directory and implements two one-method ports of the application layer:

| Method | Application port | Declared in |
|---|---|---|
| `Store` | `avatarStorer` | `ports.go` (level 2) |
| `Delete` | `avatarDeleter` | `update_user.go` (level 1) |

`UpdateUser` takes both through the composite `avatarStorerDeleter`. One `*AvatarStore` satisfies it, because it has both methods.

The ports are unexported, so this package cannot name them. The compiler checks them when `main` passes `*AvatarStore` to the use case constructors.

## avatar_store.go

```go
package localfs

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"uuid"
)

type AvatarStore struct {
	dir string
}

// The directory comes from the constructor: config is loaded by main, never read here.
func NewAvatarStore(dir string) *AvatarStore {
	return &AvatarStore{dir: dir}
}

// Store copies the file at filePath into the directory and returns its key.
// The key is the file name inside the directory: the application keeps it on
// User.AvatarKey without knowing it is a file name.
func (s *AvatarStore) Store(ctx context.Context, userID uuid.UUID, filePath string) (string, error) {
	// file access has no context support: honor cancellation before starting
	if err := ctx.Err(); err != nil {
		return "", err
	}

	src, err := os.Open(filePath)
	if err != nil {
		return "", fmt.Errorf("opening avatar %s: %w", filePath, err)
	}
	defer src.Close()

	// the store owns its directory, so it creates it on the first write
	if err := os.MkdirAll(s.dir, 0o700); err != nil {
		return "", fmt.Errorf("creating avatar directory: %w", err)
	}

	// A new key per upload: a replaced avatar never overwrites the old file,
	// so the use case can still delete the new one if saving the user fails.
	key := fmt.Sprintf("%s-%s%s", userID, uuid.New(), filepath.Ext(filePath))

	dst, err := os.OpenFile(filepath.Join(s.dir, key), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return "", fmt.Errorf("creating avatar file: %w", err)
	}

	if _, err := io.Copy(dst, src); err != nil {
		dst.Close()
		return "", fmt.Errorf("copying avatar: %w", err)
	}

	// a failed Close on a written file can mean lost data: it is an error
	if err := dst.Close(); err != nil {
		return "", fmt.Errorf("closing avatar file: %w", err)
	}

	return key, nil
}

// Delete removes the file of an avatar key. Deleting a missing file is not an
// error: the goal, no file for this key, is already reached.
func (s *AvatarStore) Delete(ctx context.Context, avatarKey string) error {
	if err := ctx.Err(); err != nil {
		return err
	}

	// Keys come from Store and are trusted, like any stored data.
	err := os.Remove(filepath.Join(s.dir, avatarKey))
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return fmt.Errorf("deleting avatar %s: %w", avatarKey, err)
	}

	return nil
}
```

## What stays out of this package

- Whether a user may have an avatar, and when the old one is deleted: the `UpdateUser` use case. The store only copies and removes files.
- Rolling back a stored avatar when saving the user fails: also the use case, which calls `Delete` on the new key.
- The directory path: `cmd/<app>` reads it from the config and passes it to `NewAvatarStore`.
- Checking the image type or size: if it is a business rule, the domain. If it only protects the storage, a check here before copying.
