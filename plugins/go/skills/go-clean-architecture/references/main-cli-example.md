# Main: admin CLI binary

`cmd/admin/`. The composition root of the `admin` binary, which runs the CLI of `delivery-cli-example.md`. It wires the JSON file store, the bcrypt hasher, the avatar store, and the clock into the `CreateUserUC` and `UpdateUserUC` use cases.

```
cmd/admin/
├── main.go       # .env, config, signals, exit code
├── app.go        # App, UseCases, NewApp, the logger of the CLI
└── app_test.go
```

A CLI differs from a server in three ways, and only `main` and `App` see them:

| | HTTP server | CLI |
|---|---|---|
| `App.Run` | `Run(ctx) error`, blocks until a signal | `Run(ctx, args) int`, runs one command and returns |
| Shutdown | drain the server with a timeout | nothing to drain: cancelling `ctx` stops the use case in progress |
| Output | responses, logs on stdout or stderr | stdout is the command's output, so the logs and the startup messages go to stderr |

The rest is the same: `.env`, config, `NewApp`, run, close, exit.

- [main.go](#maingo): `.env`, config, signals, exit code
- [app.go](#appgo): `App`, `UseCases`, `NewApp`, and the logger of the CLI
- [app_test.go](#app_testgo): the real wiring tested with a test configuration
- [Running it](#running-it)
- [What stays out of this package](#what-stays-out-of-this-package)

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
	// main.go never logs: its messages go to stderr with fmt.
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

	app, err := NewApp(cfg)
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
```

## app.go

The four infrastructure types come from the infrastructure examples: `jsonfile.UserStore`, `bcrypthasher.Hasher`, `localfs.AvatarStore`, and `system.Clock`.

```go
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"

	usecaseuser "internal/application/usecase/user"
	"internal/delivery/cli/admin"
	"internal/infrastructure/bcrypthasher"
	"internal/infrastructure/jsonfile"
	"internal/infrastructure/localfs"
	"internal/infrastructure/system"
)

type UseCases struct {
	CreateUser *usecaseuser.CreateUserUC
	UpdateUser *usecaseuser.UpdateUserUC
}

type App struct {
	cfg      Config
	useCases UseCases
	cli      *admin.CLI
	closers  []func() error
}

func NewApp(cfg Config) (*App, error) {
	// 1. infrastructure
	users := jsonfile.NewUserStore(cfg.UsersFile)
	hasher := bcrypthasher.NewHasherWithCost(cfg.BcryptCost)
	avatars := localfs.NewAvatarStore(cfg.AvatarDir)
	clk := system.NewClock()

	// 2. use cases: one store satisfies the repository port of each use case.
	// The compiler checks each port here.
	useCases := UseCases{
		CreateUser: usecaseuser.NewCreateUserUC(users, hasher, avatars, clk),
		UpdateUser: usecaseuser.NewUpdateUserUC(users, hasher, avatars, clk),
	}

	// 3. delivery: the CLI receives only the use cases it calls, and the logger,
	// since it is the only part that logs
	cli := admin.NewCLI(useCases.CreateUser, useCases.UpdateUser, newLogger(cfg), os.Stdout, os.Stderr)

	return &App{
		cfg:      cfg,
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
			fmt.Fprintf(os.Stderr, "closing resource: %v\n", err)
		}
	}
}

// newLogger builds the logger of the CLI from the config. Stderr, not stdout:
// stdout belongs to the command's output.
func newLogger(cfg Config) *slog.Logger {
	return slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: cfg.LogLevel}))
}
```

## app_test.go

The root is tested with the real wiring and a test configuration: a temporary directory and the lowest bcrypt cost. A wrong wiring (a missing port, a store in the wrong place) fails here, not in front of an operator.

```go
package main

import (
	"context"
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
	app, err := NewApp(cfg)
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
id:       019a8f2c-6d41-7b3e-9a57-3f1e2d4c6b80
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
