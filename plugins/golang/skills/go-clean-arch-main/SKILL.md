---
name: go-clean-arch-main
description: Rules for the main component (composition root) of a Go clean architecture project, defining what it must contain (loading configuration, building infrastructure, use cases and delivery adapters by constructor injection, starting the application, signal handling and graceful shutdown) and what it must never contain (business logic, globals, init functions, hidden dependencies, construction of objects outside the root). Use when writing or reviewing a main.go or cmd package, wiring dependencies, adding a new binary, or deciding whether to introduce a dependency injection tool.
---

# Go Clean Architecture: Main Component

`main` is not a layer. It is the composition root: the one place that knows every concrete type, builds the object graph by constructor injection, starts the application, and stops it safely. It is the outermost, lowest-level part of the system, a plugin to the application. Everything else depends inward, and `main` is the only code that depends on all of it.

## Dependency rule

```
main → delivery, infrastructure, application, domain
```

- `main` may import every layer. No layer imports `main`.
- It is the only place where infrastructure and delivery meet.
- It contains no logic of its own: it assembles, starts, and stops.

## Structure

Every binary has its own directory with two files, both in `package main`:

```
cmd/
└── <app>/
    ├── main.go      # process concerns: logging, .env, config, signals, exit code
    └── app.go       # the App struct and the dependency injection
```

- **`main.go`** handles what concerns the process: `.env`, configuration, logger, signals, exit code.
- **`app.go`** builds the `App` from the configuration. The `App` struct holds the configuration, a `UseCases` struct grouping every use case, and the delivery adapters built from them. All dependency injection happens here.

```go
// main.go
func main() {
	// No logger yet: it is built from the config, so early messages use fmt.
	if err := godotenv.Load(); err != nil {
		if !errors.Is(err, fs.ErrNotExist) {
			log.Fatalf("loading .env: %v", err)
		}
		fmt.Printf("no .env file found, skipping it\n")
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

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	err = app.Run(ctx)
	stop()
	app.Close() // before os.Exit, which would skip deferred calls

	if err != nil {
		logger.Error("application stopped", "error", err)
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
	logger     *slog.Logger
	useCases   UseCases
	httpServer *http.Server
	closers    []func() error
}

func NewApp(cfg Config, logger *slog.Logger) (*App, error) {
	// 1. infrastructure
	users := jsonfile.NewUserStore(cfg.UsersFile)
	hasher := bcrypthasher.NewHasher()
	clk := system.NewClock()

	// 2. use cases
	useCases := UseCases{
		CreateUser: usecaseuser.NewCreateUserUC(users, users, hasher, avatars, clk),
		UpdateUser: usecaseuser.NewUpdateUserUC(users, users, users, hasher, avatars, clk),
	}

	// 3. delivery: each adapter receives only the use cases it calls
	handler := httpdelivery.NewUserHandler(useCases.CreateUser, useCases.UpdateUser)
	server := &http.Server{Addr: cfg.HTTPAddr, Handler: httpdelivery.NewRouter(handler)}

	return &App{cfg: cfg, logger: logger, useCases: useCases, httpServer: server}, nil
}
```

## Must contain

- **Early output with `fmt`**: before the configuration is loaded there is no logger, so the `.env` message and startup errors go through `fmt`.
- **Logger setup**: built from the configuration (level, format) right after it is loaded.
- **`.env` loading** with the dotenv library (`godotenv`): load it if it exists, log that it is skipped if it does not.
- **Configuration loading and validation**: one `Config` struct read from the environment once, then passed to `NewApp`.
- **The `App`** (`app.go`): construction of infrastructure, use cases (grouped in a `UseCases` struct), and delivery adapters, in that order, by constructor injection.
- **Start and stop**: starting the delivery adapters, signal handling, graceful shutdown, and release of resources.
- **Exit code**: non-zero when the application fails.

## Must never contain

- **Business logic.** No rules, no defaults that are business decisions, no branching on domain state.
- **Globals and `init()`.** No package-level variables holding dependencies, no `init()` that connects or configures anything.
- **Hidden dependencies.** No service locator, no reaching for a dependency from a package-level registry. Everything a type needs is in its constructor.
- **Environment reads outside the config loader.** Infrastructure and delivery receive values through their constructors. Only `loadConfig` reads the environment.
- **Construction anywhere else.** A use case or an adapter never builds its own dependencies. Only `NewApp` does.
- **`os.Exit` or `log.Fatal` outside `main()`.** Everything else returns an error, so deferred cleanup runs and the code stays testable.
- **Panics for expected failures.** A bad configuration or a failed connection returns an error.

## Design rules

1. **One directory per binary.** `cmd/<app>/main.go` always comes with `app.go`. A second binary gets its own `cmd/<other>/` with its own two files.
2. **`main()` is the sequence, read top to bottom.** Load `.env`, load the config, build the logger, build the `App`, run it, clean up. No `run()` wrapper, it only adds a layer. Each step is one call, and `main()` holds no logic of its own. Failures before the `App` exists use `log.Fatalf`, since nothing is open yet. After `Run`, call `Close` explicitly before `os.Exit`, because `os.Exit` skips deferred calls.
3. **Print first, log after the config.** The logger (`log/slog`) is built from the configuration (level, format), so it only exists once the config is loaded. Until then, use `fmt` for the `.env` message and for startup errors, which `main()` writes to stderr.
4. **A missing `.env` is normal; a broken one is not.** If the file does not exist, print that it is skipped and continue. Any other error (a parse error, a permission error) stops the start. Variables already set in the real environment win over the file, as `godotenv.Load` does not override them. Never commit `.env`.
5. **Load and validate the config once, and fail fast.** `loadConfig` reads the environment, applies defaults, validates, and reports every missing or invalid value at once. The result is passed by value to `NewApp`.
6. **`NewApp(cfg, logger) (*App, error)` builds in a fixed order**: infrastructure, then use cases, then delivery. If a step fails after others succeeded, close what was already opened before returning the error.
7. **The `App` holds what is needed to run and stop**: the configuration, the `UseCases`, the delivery adapters, and the closers of the resources it opened. Closers run in reverse order of creation.
8. **Group the use cases in a `UseCases` struct** declared in `app.go`, with one exported field per use case. `NewApp` fills it once. Each delivery adapter receives only the use cases it calls (`NewUserHandler(useCases.CreateUser, useCases.UpdateUser)`), never the whole struct, so an adapter does not depend on use cases it does not use.
9. **Inject through constructors only.** Manual wiring is the default. Consider a tool only when the wiring is too large to read: `wire` (compile-time code generation) before `fx` or `dig` (runtime, reflection).
10. **Start and stop are explicit.** `main` creates a context cancelled by `SIGINT` and `SIGTERM` (`signal.NotifyContext`). `app.Run(ctx)` starts every delivery adapter, blocks until the context is cancelled or an adapter fails, then shuts the adapters down gracefully with a timeout from the config. `app.Close()` then releases the infrastructure.
11. **This is where the ports are checked.** Ports in `usecase` packages are unexported, so the compiler verifies that each infrastructure type satisfies them when `NewApp` passes it to a use case constructor.
12. **Do not factor out wiring too early.** Duplicate the wiring between two binaries until the second copy appears, then extract the shared part into a package named after what it builds.
13. **Test the root.** Test `NewApp` with a test configuration, and `App.Run` by cancelling its context. A wiring mistake should fail in a test, not in production.

## References

- `references/main-cli-example.md`: the `cmd/admin` binary wiring the JSON file store and the bcrypt hasher into the user use cases and the CLI from `go-clean-arch-delivery`, with `Run(ctx, args) int` instead of a server, logs on stderr, and a test of the real wiring.

## Quick check

Before adding code to `main`, ask:

1. Is there a decision in it that is not about assembling, starting, or stopping? If so, it belongs to a use case or the domain.
2. Does any other package read the environment or build its own dependencies? If so, move that to `loadConfig` and `NewApp`.
3. If a step fails halfway through the start, is everything already opened closed? If not, resources leak.
