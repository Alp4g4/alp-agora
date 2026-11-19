# Main

`main` is not a layer. It is the composition root: the one place that knows every concrete type, builds the object graph by constructor injection, starts the application, and stops it safely. It is the outermost, lowest-level part of the system, a plugin to the application. It contains no logic of its own: it assembles, starts, and stops.

- [Structure](#structure)
- [Must contain](#must-contain)
- [Must never contain](#must-never-contain)
- [Design rules](#design-rules)
- [Quick check](#quick-check)

## Structure

Every binary has its own directory with two files, both in `package main`:

```
cmd/
└── <app>/
    ├── main.go      # process concerns: .env, config, signals, exit code
    └── app.go       # the App struct and the dependency injection
```

- **`main.go`** handles what concerns the process: `.env`, configuration, signals, exit code.
- **`app.go`** builds the `App` from the configuration. The `App` struct holds the configuration, a `UseCases` struct grouping every use case, and the delivery adapters built from them. All dependency injection happens here, including the logger the delivery adapters need.

For a server:

```go
// main.go
func main() {
	// main.go never logs: its messages go to stderr with fmt.
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

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	err = app.Run(ctx)
	stop()
	app.Close() // before os.Exit, which would skip deferred calls

	if err != nil {
		fmt.Fprintf(os.Stderr, "application stopped: %v\n", err)
		os.Exit(1)
	}
}
```

```go
// app.go
type UseCases struct {
	CreateUser *usecaseuser.CreateUserUC
	UpdateUser *usecaseuser.UpdateUserUC
}

type App struct {
	cfg        Config
	useCases   UseCases
	httpServer *http.Server
	closers    []func() error
}

func NewApp(cfg Config) (*App, error) {
	// 1. infrastructure
	users := jsonfile.NewUserStore(cfg.UsersFile)
	hasher := bcrypthasher.NewHasherWithCost(cfg.BcryptCost)
	avatars := localfs.NewAvatarStore(cfg.AvatarDir)
	clk := system.NewClock()

	// 2. use cases: one store satisfies the repository port of each use case
	useCases := UseCases{
		CreateUser: usecaseuser.NewCreateUserUC(users, hasher, avatars, clk),
		UpdateUser: usecaseuser.NewUpdateUserUC(users, hasher, avatars, clk),
	}

	// 3. delivery: each adapter receives only the use cases it calls,
	// and the logger if it logs
	logger := newLogger(cfg)
	handler := httpapi.NewUserHandler(useCases.CreateUser, useCases.UpdateUser, logger)
	server := &http.Server{Addr: cfg.HTTPAddr, Handler: httpapi.NewRouter(handler)}

	return &App{cfg: cfg, useCases: useCases, httpServer: server}, nil
}

func newLogger(cfg Config) *slog.Logger {
	return slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{Level: cfg.LogLevel}))
}
```

A CLI differs in `Run(ctx, args) int` instead of `Run(ctx) error`, and in its logger writing to stderr, since stdout is the command's output: see the CLI example.

## Must contain

- **Output with `fmt`**: `main.go` and `app.go` write their own messages (the `.env` message, startup errors, the final error, closing errors) with `fmt`, to stderr.
- **The logger of delivery**: a `*slog.Logger` built in `NewApp` from the configuration (level, format), passed only to the delivery adapters that log.
- **`.env` loading** with the dotenv library (`godotenv`): load it if it exists, say that it is skipped if it does not.
- **Configuration loading and validation**: one `Config` struct read from the environment once, then passed to `NewApp`.
- **The `App`** (`app.go`): construction of infrastructure, use cases (grouped in a `UseCases` struct), and delivery adapters, in that order, by constructor injection.
- **Start and stop**: starting the delivery adapters, signal handling, graceful shutdown, and release of resources.
- **Exit code**: non-zero when the application fails.

## Must never contain

- **Hidden dependencies.** No service locator, no reaching for a dependency from a package-level registry. Everything a type needs is in its constructor.
- **`os.Exit` or `log.Fatal` outside `main()`.** Everything else returns an error, so deferred cleanup runs and the code stays testable.
- **Panics for expected failures.** A bad configuration or a failed connection returns an error.

## Design rules

1. **One directory per binary.** `cmd/<app>/main.go` always comes with `app.go`. A second binary gets its own `cmd/<other>/` with its own two files.
2. **`main()` is the sequence, read top to bottom.** Load `.env`, load the config, build the `App`, run it, clean up. No `run()` wrapper, it only adds a layer. Each step is one call, and `main()` holds no logic of its own. Failures before the `App` exists use `log.Fatalf`, since nothing is open yet. After `Run`, call `Close` explicitly before `os.Exit`, because `os.Exit` skips deferred calls.
3. **`main` prints, delivery logs.** `main.go` and `app.go` never log: their few messages go to stderr with `fmt`. Delivery is the only part that logs, because it is the one that sees an unknown error and must keep its detail from the caller. `NewApp` builds the `*slog.Logger` from the configuration and passes it to the delivery constructors that need one. No logger interface: `slog.Handler` is already the abstraction, and a test passes `slog.New(slog.DiscardHandler)`.
4. **A missing `.env` is normal; a broken one is not.** If the file does not exist, print that it is skipped and continue. Any other error (a parse error, a permission error) stops the start. Variables already set in the real environment win over the file, as `godotenv.Load` does not override them. Never commit `.env`.
5. **Load and validate the config once, and fail fast.** `loadConfig` is the only code that reads the environment. It applies defaults, validates, and reports every missing or invalid value at once (`errors.Join`). The result is passed by value to `NewApp`.
6. **`NewApp(cfg) (*App, error)` builds in a fixed order**: infrastructure, then use cases, then delivery. If a step fails after others succeeded, close what was already opened before returning the error.
7. **The `App` holds what is needed to run and stop**: the configuration, the `UseCases`, the delivery adapters, and the closers of the resources it opened. Closers run in reverse order of creation.
8. **Group the use cases in a `UseCases` struct** declared in `app.go`, with one exported field per use case. `NewApp` fills it once. Each delivery adapter receives only the use cases it calls (`NewUserHandler(useCases.CreateUser, useCases.UpdateUser)`), never the whole struct.
9. **Wire by hand.** Consider a tool only when the wiring is too large to read: `wire` (compile-time code generation) before `fx` or `dig` (runtime, reflection).
10. **Start and stop are explicit.** `main` creates a context cancelled by `SIGINT` and `SIGTERM` (`signal.NotifyContext`). `app.Run(ctx)` starts every delivery adapter, blocks until the context is cancelled or an adapter fails, then shuts the adapters down gracefully with a timeout from the config. `app.Close()` then releases the infrastructure.
11. **This is where the ports are checked.** Ports in `usecases` packages are unexported, so the compiler verifies that each infrastructure type satisfies them when `NewApp` passes it to a use case constructor.
12. **Do not factor out wiring too early.** Duplicate the wiring between two binaries until a second binary needs the same part, then extract that part into a package named after what it builds.
13. **Test the root.** Test `NewApp` with a test configuration and the real wiring, and `App.Run` by cancelling its context. A wiring mistake should fail in a test, not in production.

## Quick check

Before adding code to `main`, ask:

1. Does `main()` read top to bottom: `.env`, config, `NewApp`, `Run`, `Close`, exit?
2. Do `main.go` and `app.go` write with `fmt` only, and does the logger go only to delivery?
3. Does `NewApp` build infrastructure, then use cases, then delivery, passing each adapter only the use cases it calls?
4. If a step fails halfway through the start, is everything already opened closed?
5. Do `os.Exit` and `log.Fatal` appear only in `main()`?
6. Is `NewApp` tested with the real wiring?
