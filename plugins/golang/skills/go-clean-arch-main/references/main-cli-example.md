# Main: admin CLI binary

`cmd/admin/`. The composition root of the `admin` binary, which runs the CLI from `go-clean-arch-delivery` (`references/delivery-cli-example.md`). It wires the JSON file store and the bcrypt hasher from `go-clean-arch-infrastructure` into the `CreateUser` and `UpdateUser` use cases from `go-clean-arch-application`.

```
cmd/admin/
├── main.go       # .env, config, logger, signals, exit code
├── app.go        # App, UseCases, NewApp
└── app_test.go
```

A CLI differs from a server in three ways, and only `main` and `App` see them:

| | HTTP server | CLI |
|---|---|---|
| `App.Run` | `Run(ctx) error`, blocks until a signal | `Run(ctx, args) int`, runs one command and returns |
| Shutdown | drain the server with a timeout | nothing to drain: cancelling `ctx` stops the use case in progress |
| Output | responses, logs on stdout or stderr | stdout is the command's output, so the logs and the startup messages go to stderr |

The rest is the same: `.env`, config, logger, `NewApp`, run, close, exit.

## main.go

```go
package main

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"log/slog"
	"os"
	"os/signal"
	"strconv"
	"syscall"

	"github.com/joho/godotenv"
)

func main() {
	// No logger yet: it is built from the config, so early messages use fmt.
	// Stderr, not stdout: stdout belongs to the command's output.
	if err := godotenv.Load(); err != nil {
		if !errors.Is(err, fs.ErrNotExist) {
			log.Fatalf("loading .env: %v", err)
		}
		fmt.Fprintln(os.Stderr, "no .env file found, skipping it")
	}

	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("loading config: %v", err)
	}

	logger := newLogger(cfg)

	app, err := NewApp(cfg, logger)
	if err != nil {
		log.Fatalf("building app: %v", err)
	}

	// Ctrl+C cancels ctx: the use case stops and the CLI exits with "interrupted".
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	code := app.Run(ctx, os.Args[1:])
	stop()
	app.Close() // before os.Exit, which would skip deferred calls

	os.Exit(code)
}

type Config struct {
	UsersFile  string
	AvatarDir  string
	BcryptCost int
	LogLevel   slog.Level
}

// loadConfig is the only code that reads the environment. It reports every
// invalid value at once, so one run shows everything to fix.
func loadConfig() (Config, error) {
	cfg := Config{
		UsersFile: envOr("ADMIN_USERS_FILE", "data/users.json"),
		AvatarDir: envOr("ADMIN_AVATAR_DIR", "data/avatars"),
	}

	var errs []error

	cost, err := strconv.Atoi(envOr("ADMIN_BCRYPT_COST", "10"))
	if err != nil || cost < 4 || cost > 31 {
		errs = append(errs, errors.New("ADMIN_BCRYPT_COST must be an integer between 4 and 31"))
	}
	cfg.BcryptCost = cost

	if err := cfg.LogLevel.UnmarshalText([]byte(envOr("ADMIN_LOG_LEVEL", "info"))); err != nil {
		errs = append(errs, fmt.Errorf("ADMIN_LOG_LEVEL: %w", err))
	}

	return cfg, errors.Join(errs...)
}

func envOr(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok {
		return v
	}
	return fallback
}

func newLogger(cfg Config) *slog.Logger {
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: cfg.LogLevel}))
}
```

## app.go

The three infrastructure types come from the `go-clean-arch-infrastructure` references: `jsonfile.UserStore`, `bcrypthasher.Hasher`, and `localfs.AvatarStore`.

```go
package main

import (
	"context"
	"log/slog"
	"os"

	usecaseuser "internal/application/usecase/user"
	"internal/delivery/cli/admin"
	"internal/infrastructure/bcrypthasher"
	"internal/infrastructure/jsonfile"
	"internal/infrastructure/localfs"
)

type UseCases struct {
	CreateUser *usecaseuser.CreateUserUC
	UpdateUser *usecaseuser.UpdateUserUC
}

type App struct {
	cfg      Config
	logger   *slog.Logger
	useCases UseCases
	cli      *admin.CLI
	closers  []func() error
}

func NewApp(cfg Config, logger *slog.Logger) (*App, error) {
	// 1. infrastructure
	users := jsonfile.NewUserStore(cfg.UsersFile)
	hasher := bcrypthasher.NewHasherWithCost(cfg.BcryptCost)
	avatars := localfs.NewAvatarStore(cfg.AvatarDir)

	// 2. use cases: one store satisfies several one-method ports, so it is
	// passed once per port. The compiler checks each port here.
	useCases := UseCases{
		CreateUser: usecaseuser.NewCreateUserUC(users, users, hasher, avatars),
		UpdateUser: usecaseuser.NewUpdateUserUC(users, users, users, hasher, avatars),
	}

	// 3. delivery: the CLI receives only the use cases it calls
	cli := admin.NewCLI(useCases.CreateUser, useCases.UpdateUser, logger, os.Stdout, os.Stderr)

	return &App{
		cfg:      cfg,
		logger:   logger,
		useCases: useCases,
		cli:      cli,
		// Nothing to close with a JSON file. A database would add db.Close here,
		// and NewApp would close it itself if a later step failed.
		closers: nil,
	}, nil
}

// Run runs one command and returns its exit code. The CLI maps errors to
// exit codes, so main only passes the code to os.Exit.
func (a *App) Run(ctx context.Context, args []string) int {
	return a.cli.Run(ctx, args)
}

// Close releases what NewApp opened, in reverse order of creation.
func (a *App) Close() {
	for i := len(a.closers) - 1; i >= 0; i-- {
		if err := a.closers[i](); err != nil {
			a.logger.Error("closing resource", "error", err)
		}
	}
}
```

## app_test.go

The root is tested with the real wiring and a test configuration: a temporary directory and the lowest bcrypt cost. A wrong wiring (a missing port, a store in the wrong place) fails here, not in front of an operator.

```go
package main

import (
	"context"
	"io"
	"log/slog"
	"path/filepath"
	"testing"
)

func TestApp(t *testing.T) {
	dir := t.TempDir()
	cfg := Config{
		// nested paths that do not exist yet, as on a fresh machine
		UsersFile:  filepath.Join(dir, "data", "users.json"),
		AvatarDir:  filepath.Join(dir, "data", "avatars"),
		BcryptCost: 4,
	}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))

	app, err := NewApp(cfg, logger)
	if err != nil {
		t.Fatalf("NewApp: %v", err)
	}
	defer app.Close()

	args := []string{"create-user", "--email", "ada@example.com", "--password", "correct horse"}

	if code := app.Run(context.Background(), args); code != 0 {
		t.Fatalf("first create-user: exit code %d, want 0", code)
	}

	// The same email again goes through the real store: the duplicate is detected.
	if code := app.Run(context.Background(), args); code != 1 {
		t.Fatalf("second create-user: exit code %d, want 1", code)
	}
}
```

## Running it

```
$ go build -o bin/admin ./cmd/admin

$ bin/admin create-user --email ada@example.com --password 'correct horse'
no .env file found, skipping it
id:       5b0f6c1e-8d2a-4c39-9a57-3f1e2d4c6b80
email:    ada@example.com
verified: false
$ echo $?
0

$ bin/admin create-user --email ada@example.com --password 'correct horse'
no .env file found, skipping it
error: user email already exists
$ echo $?
1

$ bin/admin create-user --email not-an-email --password 'correct horse'
no .env file found, skipping it
invalid input: invalid email
$ echo $?
2
```

Only the first block goes to stdout, so `bin/admin create-user ... > user.txt` captures the user and nothing else.

## What stays out of this package

- Flag parsing, the error to exit code mapping, the output format: `internal/delivery/cli/admin`.
- Email and password rules: the domain, through the use cases.
- Any `if` on a user, a command name, or an error type: `main` only assembles, runs, and exits.
