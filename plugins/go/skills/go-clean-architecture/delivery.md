# Delivery

The delivery layer is the driving side of the application: something outside triggers it (an HTTP request, a CLI command, a queue message, a timer), and delivery translates that trigger into a use case input, calls one use case, and translates the outcome back into something the outside understands. It decides nothing about the business.

In Uncle Bob's vocabulary this layer holds the **controller** (trigger to input) and the **presenter** (result to output). With use cases that return their result, the presenter is a mapping step the controller calls, not a separate object.

## Must contain

- **Entry points (controllers)**: HTTP handlers, GraphQL resolvers, CLI commands, queue consumers, cron job functions. Each turns one trigger into one use case call.
- **Request and response models**: structs shaped for the transport, with its tags (`json:`, validation tags, CLI flags).
- **Input translation**: decoding the request, flags, or message, and building the use case input from them.
- **Presenting**: mapping a use case result to a response model, a GraphQL type, or formatted CLI output.
- **Error mapping**: application and domain errors turned into status codes, GraphQL errors, exit codes, or ack/nack/retry decisions.
- **Transport concerns**: routing, middleware (authentication, logging, recovery), serialization, pagination parameters, flag parsing.

## Must never contain

- **Use case orchestration.** One trigger calls one use case. Chaining several use cases to achieve one intent is a new use case in the application layer.
- **Direct use of ports or repositories.** Delivery never reads or writes data itself. It always goes through a use case.
- **Infrastructure code.** No SQL, ORM, or clients for the application's outbound needs (databases, payment APIs, email). The library that delivers the trigger itself (HTTP server, queue consumer client, scheduler) is allowed.
- **Domain entities on the wire.** Never serialize an entity directly: it leaks fields (`PasswordHash`) and couples the API to the domain.
- **Wiring.** Building use cases and infrastructure, loading config, and starting servers belong to `main`.

## Design rules

1. **One trigger, one use case call.** The shape of a handler is: decode, build the input, call `Execute`, map the result or the error. Keep it linear.
2. **Depend on each use case through a one-method interface declared in delivery**, unexported, named after what it does:
   ```go
   type userCreator interface {
   	Execute(ctx context.Context, input usecaseuser.CreateUserInput) (user.User, error)
   }
   ```
   The use case struct satisfies it implicitly, and handler tests pass a fake.
3. **Response models are separate from entities.** Map explicitly (`toUserResponse(u user.User) UserResponse`) and leave out what must not leave the system. A cast is rarely possible here, because a response hides fields.
4. **Map errors in one place per mechanism.** One function turns an error into a status code, GraphQL error, or exit code, using `errors.Is` / `errors.As`:

   | Error | HTTP | CLI |
   |---|---|---|
   | invalid input (`ErrInvalidEmail`, `ErrPasswordTooShort`) | 400 or 422 | message and exit 2 |
   | `ErrUserNotFound` | 404 | message and exit 1 |
   | `ErrEmailAlreadyExists` | 409 | message and exit 1 |
   | anything else | 500, generic message | generic message and exit 1 |

   Log an unknown error with its detail and never send that detail to the caller.
5. **Pass the caller's context.** Use the request context (`r.Context()`), or a context tied to the process shutdown for workers and cron. Cancellation must reach the use case.
6. **Authenticate here, authorize in the use case.** Delivery extracts the caller's identity (token, session) and passes it as part of the input. Deciding what that caller may do is a business rule.
7. **Workers decide the delivery outcome, not the business flow.** A consumer maps the result to ack, nack, retry, or dead-letter, from the type of error (permanent or transient). The business flow stays in the use case. Cron jobs log the outcome and report it.
8. **If a use case has an output port, delivery implements it.** The implementation holds the response and is built per request. This is the exception, see "Returning a result or presenting it?" in `application.md`.
9. **Test with fake use cases.** Test handlers with `httptest` and a fake `Execute`, and CLI commands by running them with arguments and capturing the output.

## Layout

```
internal/delivery/
├── httpapi/                 # not http: it would shadow net/http
│   ├── router.go
│   ├── user_handler.go
│   ├── user_models.go       # request and response models, mapping
│   ├── json.go              # decoding and encoding
│   └── errors.go            # error to status code
├── cli/
│   ├── admin/               # commands of the admin binary
│   └── ops/                 # commands of the ops binary
├── web/                     # server-rendered pages (go-ssr)
├── graphql/
├── worker/
└── cron/
```

Group by mechanism (`http`, `cli`, `worker`), then by app when several binaries use the same mechanism. A helper needed by two apps goes in a small package named after what it does (`output`, `exitcode`), created only when the second copy appears.

## Quick check

Before adding code to delivery, ask:

1. Does each entry point call exactly one use case, through a one-method interface declared here?
2. Does it call anything other than a use case (a repository, an external client)? If so, that call belongs in a use case behind a port.
3. Is every entity mapped to a response model or an output before it leaves?
4. Are errors mapped in one place per mechanism, with the detail of an unknown error logged and never sent?
5. Is it tested with a fake use case?
