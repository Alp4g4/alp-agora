# Delivery: admin CLI

`internal/delivery/cli/admin/`. The commands of the `admin` binary, an operator tool that calls the `CreateUserUC` and `UpdateUserUC` use cases. It uses only the standard library `flag` package: one `FlagSet` per command.

Each command follows the same linear shape: parse the flags, check their shape, build the use case input, call `Execute`, present the result. Every error goes back to `Run`, which turns it into a message and an exit code in one place.

```
internal/delivery/cli/admin/
├── cli.go            # CLI struct, constructor, command dispatch
├── create_user.go    # create-user command and its use case interface
├── update_user.go    # update-user command and its use case interface
├── flags.go          # flag set helpers
├── present.go        # user → terminal output
├── errors.go         # error → message and exit code
└── cli_test.go
```

The domain package is imported without an alias (`user.User`). The application package gets one, `usecaseuser`, because both are named `user`.

- [cli.go](#cligo): the `CLI` struct and the command dispatch
- [create_user.go](#create_usergo): the `create-user` command and its use case interface
- [update_user.go](#update_usergo): the `update-user` command and its use case interface
- [flags.go](#flagsgo): flag set helpers and optional flags
- [present.go](#presentgo): the use case result turned into terminal output
- [errors.go](#errorsgo): every error turned into a message and an exit code, in one place
- [cli_test.go](#cli_testgo): the commands tested with a fake use case
- [What stays out of this package](#what-stays-out-of-this-package)

## cli.go

```go
package admin

import (
	"context"
	"fmt"
	"io"
	"log/slog"
)

type CLI struct {
	userCreator userCreator
	userUpdater userUpdater
	logger      *slog.Logger
	stdout      io.Writer
	stderr      io.Writer
}

// The writers come from the constructor, so tests capture the output
// instead of reading os.Stdout.
func NewCLI(creator userCreator, updater userUpdater, logger *slog.Logger, stdout, stderr io.Writer) *CLI {
	return &CLI{
		userCreator: creator,
		userUpdater: updater,
		logger:      logger,
		stdout:      stdout,
		stderr:      stderr,
	}
}

// Run runs the command named by args[0] and returns the process exit code.
// It never calls os.Exit: the process belongs to main.
func (c *CLI) Run(ctx context.Context, args []string) int {
	if len(args) == 0 {
		c.usage()
		return exitUsage
	}

	var err error

	switch args[0] {
	case "create-user":
		err = c.createUser(ctx, args[1:])
	case "update-user":
		err = c.updateUser(ctx, args[1:])
	case "help", "-h", "--help":
		c.usage()
		return exitOK
	default:
		fmt.Fprintf(c.stderr, "unknown command %q\n\n", args[0])
		c.usage()
		return exitUsage
	}

	return c.exitCode(err)
}

func (c *CLI) usage() {
	fmt.Fprint(c.stderr, `usage: admin <command> [flags]

commands:
  create-user  --email <email> --password <password> [--avatar <file>]
  update-user  --id <uuid> [--email <email>] [--password <password>] [--avatar <file>]

run "admin <command> -h" for the flags of a command
`)
}
```

## create_user.go

The interface is defined here, next to the command that uses it: one method, unexported, satisfied implicitly by `*usecaseuser.CreateUserUC`.

```go
package admin

import (
	"context"

	usecaseuser "internal/application/usecases/user"
	"internal/domain/user"
)

type userCreator interface {
	Execute(ctx context.Context, input usecaseuser.CreateUserInput) (user.User, error)
}

func (c *CLI) createUser(ctx context.Context, args []string) error {
	fs := c.newFlagSet("create-user")
	email := fs.String("email", "", "email of the new user (required)")
	// A flag keeps the example short. A real tool reads the password from a
	// prompt or stdin, so it does not end up in the shell history.
	password := fs.String("password", "", "password of the new user (required)")
	var avatar optionalString
	fs.Var(&avatar, "avatar", "path to an avatar image")

	if err := parseFlags(fs, args); err != nil {
		return err
	}

	// Shape only: the flags are present. Whether the email is valid or the
	// password strong enough is decided by the use case.
	if *email == "" || *password == "" {
		return c.usageErr(fs, "--email and --password are required")
	}

	u, err := c.userCreator.Execute(ctx, usecaseuser.CreateUserInput{
		Email:          *email,
		Password:       *password,
		AvatarFilePath: avatar.value,
	})
	if err != nil {
		return err
	}

	presentUser(c.stdout, u)

	return nil
}
```

## update_user.go

```go
package admin

import (
	"context"
	"uuid"

	usecaseuser "internal/application/usecases/user"
	"internal/domain/user"
)

type userUpdater interface {
	Execute(ctx context.Context, input usecaseuser.UpdateUserInput) (user.User, error)
}

func (c *CLI) updateUser(ctx context.Context, args []string) error {
	fs := c.newFlagSet("update-user")
	id := fs.String("id", "", "id of the user to update (required)")
	var email, password, avatar optionalString
	fs.Var(&email, "email", "new email")
	fs.Var(&password, "password", "new password")
	fs.Var(&avatar, "avatar", "path to a new avatar image")

	if err := parseFlags(fs, args); err != nil {
		return err
	}

	// A malformed UUID is a shape error, like a flag of the wrong type.
	userID, err := uuid.Parse(*id)
	if err != nil {
		return c.usageErr(fs, "--id must be a valid uuid")
	}

	// "Nothing to update" is not checked here: the use case already owns that rule.
	u, err := c.userUpdater.Execute(ctx, usecaseuser.UpdateUserInput{
		ID:             userID,
		Email:          email.value,
		Password:       password.value,
		AvatarFilePath: avatar.value,
	})
	if err != nil {
		return err
	}

	presentUser(c.stdout, u)

	return nil
}
```

## flags.go

```go
package admin

import (
	"errors"
	"flag"
	"fmt"
)

// errUsage means the command line was malformed and the problem was already printed.
var errUsage = errors.New("invalid usage")

func (c *CLI) newFlagSet(name string) *flag.FlagSet {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	fs.SetOutput(c.stderr)
	return fs
}

// parseFlags returns flag.ErrHelp for -h, and errUsage for any other parse
// error, which the flag package has already printed with the usage.
func parseFlags(fs *flag.FlagSet, args []string) error {
	err := fs.Parse(args)
	if err == nil || errors.Is(err, flag.ErrHelp) {
		return err
	}

	return errUsage
}

func (c *CLI) usageErr(fs *flag.FlagSet, msg string) error {
	fmt.Fprintf(c.stderr, "%s\n", msg)
	fs.Usage()
	return errUsage
}

// optionalString records whether a flag was given, so "not set" (nil) and
// "set to an empty string" stay different, as the use case input expects.
type optionalString struct {
	value *string
}

func (o *optionalString) String() string {
	if o.value == nil {
		return ""
	}
	return *o.value
}

func (o *optionalString) Set(s string) error {
	o.value = &s
	return nil
}
```

## present.go

The presenter of this mechanism: a function that turns the use case result into terminal output. The entity is never printed as is, because `PasswordHash` must not leave the system.

```go
package admin

import (
	"fmt"
	"io"

	"internal/domain/user"
)

func presentUser(w io.Writer, u user.User) {
	fmt.Fprintf(w, "id:       %s\n", u.ID)
	fmt.Fprintf(w, "email:    %s\n", u.Email)
	fmt.Fprintf(w, "verified: %t\n", u.EmailVerifiedAt != nil)

	if u.AvatarKey != nil {
		fmt.Fprintf(w, "avatar:   %s\n", *u.AvatarKey)
	}
}
```

## errors.go

The only place where an error becomes a message and an exit code. Known errors are matched with `errors.Is`, so the wrapping added by the use case (`loading user: user not found`) does not matter.

```go
package admin

import (
	"context"
	"errors"
	"flag"
	"fmt"

	usecaseuser "internal/application/usecases/user"
	"internal/domain/user"
)

const (
	exitOK      = 0
	exitFailure = 1
	exitUsage   = 2
)

func (c *CLI) exitCode(err error) int {
	switch {
	case err == nil, errors.Is(err, flag.ErrHelp):
		return exitOK

	case errors.Is(err, errUsage):
		return exitUsage // already printed

	case errors.Is(err, user.ErrInvalidEmail),
		errors.Is(err, user.ErrPasswordTooShort),
		errors.Is(err, user.ErrEmailUnchanged),
		errors.Is(err, usecaseuser.ErrUserIDEmpty),
		errors.Is(err, usecaseuser.ErrAvatarFilePathEmpty),
		errors.Is(err, usecaseuser.ErrNothingToUpdate):
		fmt.Fprintf(c.stderr, "invalid input: %v\n", err)
		return exitUsage

	case errors.Is(err, usecaseuser.ErrUserNotFound),
		errors.Is(err, usecaseuser.ErrEmailAlreadyExists):
		fmt.Fprintf(c.stderr, "error: %v\n", err)
		return exitFailure

	case errors.Is(err, context.Canceled):
		fmt.Fprintln(c.stderr, "interrupted")
		return exitFailure

	default:
		// unknown: the detail goes to the logs, never to the operator's terminal
		c.logger.Error("command failed", "error", err)
		fmt.Fprintln(c.stderr, "error: something went wrong, see the logs")
		return exitFailure
	}
}
```

## cli_test.go

The use case is replaced by a fake `Execute`: no store, no hasher, no file. The test runs the command with arguments and checks the exit code and the output.

```go
package admin

import (
	"bytes"
	"context"
	"io"
	"log/slog"
	"strings"
	"testing"

	usecaseuser "internal/application/usecases/user"
	"internal/domain/user"
)

type fakeUserCreator struct {
	got  usecaseuser.CreateUserInput
	user user.User
	err  error
}

func (f *fakeUserCreator) Execute(_ context.Context, input usecaseuser.CreateUserInput) (user.User, error) {
	f.got = input
	return f.user, f.err
}

func TestCreateUser(t *testing.T) {
	valid := []string{"create-user", "--email", "ada@example.com", "--password", "correct horse"}

	tests := []struct {
		name       string
		args       []string
		ucErr      error
		wantCode   int
		wantStdout string
		wantStderr string
	}{
		{name: "created", args: valid, wantCode: exitOK, wantStdout: "email:    ada@example.com"},
		{name: "missing password", args: valid[:3], wantCode: exitUsage, wantStderr: "are required"},
		{name: "invalid email", args: valid, ucErr: user.ErrInvalidEmail, wantCode: exitUsage, wantStderr: "invalid input"},
		{name: "duplicate email", args: valid, ucErr: usecaseuser.ErrEmailAlreadyExists, wantCode: exitFailure, wantStderr: "already exists"},
		{name: "unknown error", args: valid, ucErr: io.ErrUnexpectedEOF, wantCode: exitFailure, wantStderr: "see the logs"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			creator := &fakeUserCreator{user: user.User{Email: "ada@example.com"}, err: tt.ucErr}
			var stdout, stderr bytes.Buffer
			logger := slog.New(slog.NewTextHandler(io.Discard, nil))

			// update-user is not called here: its use case can be nil
			cli := NewCLI(creator, nil, logger, &stdout, &stderr)

			code := cli.Run(context.Background(), tt.args)

			if code != tt.wantCode {
				t.Errorf("exit code = %d, want %d (stderr: %s)", code, tt.wantCode, stderr.String())
			}
			if !strings.Contains(stdout.String(), tt.wantStdout) {
				t.Errorf("stdout = %q, want it to contain %q", stdout.String(), tt.wantStdout)
			}
			if !strings.Contains(stderr.String(), tt.wantStderr) {
				t.Errorf("stderr = %q, want it to contain %q", stderr.String(), tt.wantStderr)
			}
		})
	}
}
```

## What stays out of this package

- Email and password rules: `user.ParseEmail` and `user.ParsePassword`, called by the use case. The CLI passes raw strings.
- "At least one field to update": `UpdateUserInput.Validate` in the use case.
- Building the use cases, the store, and the hasher, loading `.env` and the config, calling `os.Exit`: `cmd/admin`.
- Reading or writing the users file directly: always through a use case.
