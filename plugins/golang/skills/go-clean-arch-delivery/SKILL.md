---
name: go-clean-arch-delivery
description: Rules for the delivery layer of a Go clean architecture project, defining what it must contain (entry points that drive the application such as HTTP handlers, GraphQL resolvers, CLI commands, queue consumers and cron jobs, request and response models, mapping of use case results and errors to the outside world) and what it must never contain (business rules, use case orchestration, infrastructure code, direct calls to ports or repositories). Use when writing or reviewing a controller, handler, resolver, command or job that calls a use case, or when deciding what belongs in delivery versus the application layer or main.
---

# Go Clean Architecture: Delivery Layer

The delivery layer is the driving side of the application: something outside triggers it (an HTTP request, a CLI command, a queue message, a timer), and delivery translates that trigger into a use case input, calls one use case, and translates the outcome back into something the outside understands. It decides nothing about the business.

In Uncle Bob's vocabulary this layer holds the **controller** (trigger to input) and the **presenter** (result to output). With use cases that return their result, the presenter is a mapping step the controller calls, not a separate object.

## Dependency rule

```
delivery → application → domain
```

- Delivery imports the **application** (use cases, their input and output types, application errors) and the **domain** (entities it maps, domain errors it matches).
- Delivery never imports infrastructure, and infrastructure never imports delivery. Only the composition root (`main`) knows both.
- The application never imports delivery. It does not know whether it is called by HTTP, a CLI, or a cron job.

## Must contain

- **Entry points (controllers)**: HTTP handlers, GraphQL resolvers, CLI commands, queue consumers, cron job functions. Each turns one trigger into one use case call.
- **Request and response models**: structs shaped for the transport, with its tags (`json:`, validation tags, CLI flags).
- **Input translation**: decoding the request, flags, or message, and building the use case input from them.
- **Presenting**: mapping a use case result to a response model, a GraphQL type, or formatted CLI output.
- **Error mapping**: application and domain errors turned into status codes, GraphQL errors, exit codes, or ack/nack/retry decisions.
- **Transport concerns**: routing, middleware (authentication, logging, recovery), serialization, pagination parameters, flag parsing.

## Must never contain

- **Business rules.** No status checks, limits, or state transitions. If an `if` expresses a business invariant, it belongs to the domain.
- **Use case orchestration.** One trigger calls one use case. Chaining several use cases to achieve one intent is a new use case in the application layer.
- **Direct use of ports or repositories.** Delivery never reads or writes data itself. It always goes through a use case.
- **Infrastructure code.** No SQL, ORM, clients for the application's outbound needs (databases, payment APIs, email). The library that delivers the trigger itself (HTTP server, queue consumer client, scheduler) is allowed.
- **Domain entities on the wire.** Never serialize an entity directly: it leaks fields (`PasswordHash`) and couples the API to the domain.
- **Wiring.** Building use cases and infrastructure, loading config, and starting servers belong to `main`.

## Design rules

1. **One trigger, one use case call.** The shape of a handler is: decode, build the input, call `Execute`, map the result or the error. Keep it linear.
2. **Depend on use cases through small interfaces defined in delivery.** One method, unexported, named after what it does:
   ```go
   type userCreator interface {
   	Execute(ctx context.Context, input usecaseuser.CreateUserInput) (user.User, error)
   }
   ```
   The use case struct satisfies it implicitly, and handler tests can pass a fake.
3. **Check the shape of the transport input, not its meaning.** Malformed JSON, a missing flag, or a wrong type is a delivery error. Whether an email is valid or a password strong enough is decided by the use case through `ParseEmail` and `ParsePassword`. Delivery passes raw strings.
4. **Response models are separate from entities.** Map explicitly (`toUserResponse(u user.User) UserResponse`) and leave out what must not leave the system. A cast is rarely possible here, because a response hides fields.
5. **Map errors in one place per mechanism.** One function turns an error into a status code, GraphQL error, or exit code, using `errors.Is` / `errors.As`:

   | Error | HTTP | CLI |
   |---|---|---|
   | invalid input (`ErrInvalidEmail`, `ErrPasswordTooShort`) | 400 or 422 | message and exit 2 |
   | `ErrUserNotFound` | 404 | message and exit 1 |
   | `ErrEmailAlreadyExists` | 409 | message and exit 1 |
   | anything else | 500, generic message | generic message and exit 1 |

   Log an unknown error with its detail and never send that detail to the caller.
6. **Pass the caller's context.** Use the request context (`r.Context()`), or a context tied to the process shutdown for workers and cron. Cancellation must reach the use case.
7. **Authenticate here, authorize in the use case.** Delivery extracts the caller's identity (token, session) and passes it as part of the input. Deciding what that caller may do is a business rule.
8. **Workers decide the delivery outcome, not the business flow.** A consumer maps the result to ack, nack, retry, or dead-letter, from the type of error (permanent or transient). The business flow stays in the use case. Cron jobs log the outcome and report it.
9. **If a use case has an output port, delivery implements it.** The implementation holds the response and is built per request. This is the exception, see the application skill.
10. **Take dependencies through the constructor.** `NewUserHandler(creator userCreator)`. No globals, no reading of environment variables.
11. **Test with fake use cases.** Test handlers with `httptest` and a fake `Execute`, and CLI commands by running them with arguments and capturing the output.

## Delivery, application, or main?

| The code... | Goes in |
|---|---|
| decodes a request, parses flags, reads a message | delivery |
| calls a use case | delivery |
| turns a result or an error into a response | delivery |
| expresses a rule true for every entry point | domain |
| sequences the steps of one intent | use case |
| builds the objects, loads config, starts the app | `main` |

## Suggested layout

```
cmd/
├── api/main.go
├── admin/main.go
└── worker/main.go
internal/
└── delivery/
    ├── http/
    │   ├── router.go
    │   ├── user_handler.go
    │   ├── user_models.go       # request and response models, mapping
    │   └── errors.go            # error to status code
    ├── cli/
    │   ├── admin/               # commands of the admin binary
    │   └── ops/                 # commands of the ops binary
    ├── web/                     # server-rendered pages (go-ssr-templ)
    ├── graphql/
    ├── worker/
    └── cron/
```

Group by mechanism (`http`, `cli`, `worker`), then by app when several binaries use the same mechanism. A helper needed by two apps goes in a small package named after what it does (`output`, `exitcode`), created only when the second copy appears. Each `main` wires only the use cases its entry points call.

## References

Complete examples calling the `user` use cases from `go-clean-arch-application`:

- `references/delivery-cli-example.md`: an `admin` CLI with `create-user` and `update-user` commands, one-method use case interfaces, flag shape checks, a presenter function, error to exit code mapping in one place, and tests with fake use cases.

## Quick check

Before adding code to delivery, ask:

1. Is there a business decision in it? If it would be true for every entry point, move it to the domain or the use case.
2. Does it call anything other than a use case (a repository, an external client)? If so, that call belongs in a use case behind a port.
3. Could the same use case be called by a CLI instead of HTTP without changing it? If not, transport details are leaking into the application.
