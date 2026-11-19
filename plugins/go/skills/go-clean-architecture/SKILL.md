---
name: go-clean-architecture
description: Structures a Go project with clean architecture, defining the dependency rule, the folder layout, and what each part owns - the domain (entities, value objects, business rules), the application (use cases and their ports), infrastructure (adapters implementing the ports), delivery (HTTP handlers, CLI commands, workers, cron jobs), and the composition root in cmd/<app>. Use when creating, reviewing, or refactoring Go code in a clean, hexagonal, or ports and adapters architecture, when adding a feature across layers, when writing an entity, a use case, a port, a repository, a handler, or a main.go, when wiring dependencies, or when deciding where a piece of logic belongs.
---

# Go Clean Architecture

The code is split into four layers and one composition root. Each part owns one kind of decision, and every dependency points inward, so the business rules never depend on a database, a framework, or a transport.

| Part | Owns | Package |
|---|---|---|
| **Domain** | what the business is: entities, value objects, domain errors, business rules | `internal/domain/<concept>` |
| **Application** | what the application does: one use case per intent, the ports it needs, application errors | `internal/application` |
| **Infrastructure** | how the application reaches the outside: the implementations of the ports (database, external APIs, file system, hasher, clock) | `internal/infrastructure/<technology>` |
| **Delivery** | how the outside reaches the application: entry points that call one use case (HTTP, CLI, worker, cron) | `internal/delivery/<mechanism>` |
| **Main** | assembling, starting, and stopping: configuration, construction by injection, graceful shutdown | `cmd/<app>` |

## Read the file of the part you are working on

This file holds what every part shares. The rules of each part are in its own file:

| Working on | Read |
|---|---|
| an entity, a value object, a domain error, a business rule | `domain.md` |
| a use case, a port, an input or output type, an application error | `application.md` |
| a repository, an external client, a persistence model, error translation | `infrastructure.md` |
| an HTTP handler, a CLI command, a queue consumer, a cron job, a request or response model, error mapping | `delivery.md` |
| `main.go`, `app.go`, configuration, wiring, graceful shutdown | `main.md` |

For a feature that spans several parts, read each file when its step comes (see "Adding a feature"). SQL schemas, migrations, and sqlc queries are in `go-sql`. Server-rendered pages are in `go-ssr`.

Complete examples, to read when writing the code of that part:

| Part | Examples |
|---|---|
| domain | `references/domain-user-example.md`: entity, `Email` value object with `ParseEmail`, and `ChangeEmail` as a domain rule |
| | `references/domain-order-example.md`: entity, `Money` value object, status, and `Cancel` as a domain rule while `CancelOrder` stays a use case |
| application | `references/application-create-user-example.md`: `CreateUserUC`, its own repository port, input parsed into `Email` and `Password`, time and ID supplied by the use case |
| | `references/application-update-user-example.md`: `UpdateUserUC`, calling `ChangeEmail` for the rule and assigning plain fields directly, with a composite port |
| | `references/application-user-ports-example.md`: the ports shared by the user use cases (`ports.go`) and the application errors |
| | `references/application-clock-port-example.md`: `clock.Clock`, a port shared by several concepts, with a fixed clock for tests |
| infrastructure | `references/infrastructure-postgres-example.md`: a PostgreSQL `UserStore` on the code sqlc generates, a cast params struct and a mapped one, unique violations recognized by constraint name, and integration tests in a container |
| | `references/infrastructure-sqlite-example.md`: the same `UserStore` on SQLite, where a unique violation is recognized by its column and `EXISTS` returns an integer, with integration tests on a database file |
| | `references/infrastructure-jsonfile-example.md`: a JSON file `UserStore` satisfying the repository port of each user use case, a model cast to the entity, error translation, and the mapper fallback |
| | `references/infrastructure-bcrypt-hasher-example.md`: a `Hasher` building a `PasswordHash` from a `Password`, with its configuration passed through the constructor |
| | `references/infrastructure-localfs-avatar-example.md`: an `AvatarStore` copying avatar files into a directory, one type satisfying a shared port and a use case's own port |
| | `references/infrastructure-system-clock-example.md`: a `Clock` returning the current time in UTC, with a compile-time check of the exported port |
| delivery | `references/delivery-http-example.md`: a JSON API with `POST /users` and `PATCH /users/{id}`, strict and bounded decoding, a response model hiding the password hash, error to status code mapping in one place, and tests with fake use cases |
| | `references/delivery-cli-example.md`: an `admin` CLI with `create-user` and `update-user` commands, one-method use case interfaces, flag shape checks, a presenter function, error to exit code mapping in one place, and tests with fake use cases |
| main | `references/main-cli-example.md`: the `cmd/admin` binary wiring the JSON file store, the hasher, the avatar store, and the clock into the user use cases and the CLI, with `Run(ctx, args) int` instead of a server, logs on stderr, and a test of the real wiring |

## Dependency rule

```
cmd/<app> ──→ delivery ───────┐
    │                         ├──→ application ──→ domain
    └───────→ infrastructure ─┘
```

- **Domain** imports only the standard library and other domain packages.
- **Application** imports the domain. It defines the ports.
- **Infrastructure** imports the application (ports, application errors) and the domain. It implements the ports.
- **Delivery** imports the application (use cases, inputs, application errors) and the domain. It calls the use cases.
- **Delivery and infrastructure never import each other.** Only `main` imports both.
- **No package imports `main`.**

Run `scripts/check-deps.sh` from the directory holding `go.mod` to check the rule. It lists every import that points the wrong way, test files included, and exits with 1 when it finds one. Fix each import and run it again until it passes.

## Layout

```
cmd/
└── <app>/
    ├── main.go                     # process: .env, config, signals, exit code
    └── app.go                      # App and UseCases: all the wiring
internal/
├── domain/
│   └── user/                       # one package per business concept
│       ├── user.go                 # entity
│       ├── email.go                # value object with ParseEmail
│       └── errors.go               # domain errors
├── application/
│   ├── ports/
│   │   └── clock/clock.go          # a port shared by several concepts, one package per capability
│   └── usecases/
│       └── user/
│           ├── errors.go           # application errors
│           └── create_user.go      # CreateUserUC and its ports (createUserRepository)
├── infrastructure/
│   ├── postgres/user_store.go      # one package per technology (go-sql)
│   └── system/clock.go
└── delivery/
    ├── httpapi/user_handler.go     # one package per mechanism
    └── cli/admin/                  # then per app when several binaries share a mechanism
```

The domain and the application are grouped by business concept (`user`, `order`). Infrastructure is grouped by technology, delivery by mechanism.

## Which part does this code belong to?

| The code... | Goes in |
|---|---|
| is true for every use case that touches the entity | domain |
| sequences the steps of one intent | application, in a use case |
| loads or saves data, calls an outside system | infrastructure, behind a port the use case defines |
| decodes a request, parses flags, reads a message | delivery |
| turns a result or an error into a response, an exit code, or an ack | delivery |
| builds the objects, loads the configuration, starts and stops the app | `main` |

If two use cases would need the same `if`, it is a domain rule. If two entry points would need the same `if`, it belongs to the use case or the domain.

## Rules shared by every part

1. **Dependencies come through the constructor.** `NewCreateUserUC(users createUserRepository, hasher passwordHasher)`. No globals, no `init()`, no environment read outside the configuration loader of `main`. Only `main` builds objects.
2. **`context.Context` is the first parameter** of every method that does I/O, and is passed down to the driver. Domain methods take none.
3. **Validate once, at the boundary.** The use case turns raw input into value objects (`ParseEmail`), and the rest of the flow trusts them. Delivery checks only the shape of the input (malformed JSON, a missing flag). Data read from storage was validated before it was written, so infrastructure converts it without parsing again.
4. **Errors keep their meaning across the boundaries.** The domain and the application declare errors that callers match with `errors.Is` and `errors.As`. Infrastructure translates driver errors into them. Every part wraps with context (`fmt.Errorf("loading user %s: %w", id, err)`). Delivery maps them to the outside in one place per mechanism, and never sends the detail of an unknown error.
5. **Each boundary has its own models.** Domain types carry no tags. Infrastructure has its persistence models and delivery its request and response models, each converted to and from the entity at the boundary.

## Adding a feature

Work from the inside out, so each step compiles against the one before it. Copy this checklist and check off each step:

```
- [ ] 1. Domain: entity, value objects, domain errors, rule methods (domain.md)
- [ ] 2. Application: the use case, its input, its ports, application errors (application.md)
- [ ] 3. Infrastructure: the methods that satisfy the new ports, error translation (infrastructure.md)
- [ ] 4. Delivery: the entry point that calls the use case, error mapping (delivery.md)
- [ ] 5. Main: build the new types and pass them to the constructors (main.md)
- [ ] 6. Verify: scripts/check-deps.sh, go vet ./..., go test ./...
```

If step 6 fails, fix the cause and run all three commands again. The feature is done only when the three pass.

## Must never contain

- **A business rule outside the domain.** No status check, limit, or state transition in a use case, an adapter, a handler, or `main`.
- **Driver, framework, or transport types crossing a port**: `*sql.Tx`, `*sql.Rows`, driver errors, `http.Request`, `gin.Context`.
- **A package named after a kind of code**: no flat `ports`, `models`, `utils`, `common`, or `helpers`. A Go package is named after what it provides.

## Quick check

Before finishing a change, ask:

1. Does `scripts/check-deps.sh` pass?
2. Is there an `if` on a business invariant outside the domain?
3. Could the database be replaced without touching the application or the domain?
4. Could the same use case be called from HTTP, a CLI, and a cron job without changing it?
5. Is every dependency passed through a constructor, and built only in `main`?
