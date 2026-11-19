# Delivery: JSON HTTP API

`internal/delivery/httpapi/`. A JSON API that calls the `CreateUserUC` and `UpdateUserUC` use cases: `POST /users` creates a user, `PATCH /users/{id}` updates one. It uses only the standard library: `net/http` routes with method and path patterns, `encoding/json` decodes and encodes.

- [router.go](#routergo): the routes
- [user_models.go](#user_modelsgo): request and response models, and the presenter
- [json.go](#jsongo): bounded, strict JSON decoding
- [errors.go](#errorsgo): every error turned into a status code
- [user_handler.go](#user_handlergo): the two handlers
- [user_handler_test.go](#user_handler_testgo): the handlers tested with fake use cases
- [What stays out of this package](#what-stays-out-of-this-package)

The package is `httpapi`, not `http`, so it does not shadow the `net/http` import in its own files.

```
internal/delivery/httpapi/
├── router.go             # routes
├── user_handler.go       # the handlers and their use case interfaces
├── user_models.go        # request and response models, the presenter
├── json.go               # decoding and encoding JSON
├── errors.go             # error to status code, in one place
└── user_handler_test.go
```

Each handler follows the same linear shape: decode, build the input, call `Execute`, present. Every error goes to `writeError`, which turns it into a status code in one place.

## router.go

`internal/delivery/httpapi/router.go`

```go
package httpapi

import "net/http"

func NewRouter(users *UserHandler) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /users", users.Create)
	mux.HandleFunc("PATCH /users/{id}", users.Update)
	return mux
}
```

## user_models.go

`internal/delivery/httpapi/user_models.go`

```go
package httpapi

import (
	"time"

	"internal/domain/user"
)

// Request models: the shape of the JSON body, raw strings only. Whether an email
// is valid is decided by the use case, through ParseEmail.
type createUserRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// Pointers: a field left out of a PATCH is not changed.
type updateUserRequest struct {
	Email    *string `json:"email"`
	Password *string `json:"password"`
}

// The response model: what a client may see of a user. PasswordHash never leaves.
type userResponse struct {
	ID            string    `json:"id"`
	Email         string    `json:"email"`
	EmailVerified bool      `json:"email_verified"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}

// toUserResponse is the presenter of this mechanism. Not a cast: the response
// hides fields and computes EmailVerified.
func toUserResponse(u user.User) userResponse {
	return userResponse{
		ID:            u.ID.String(),
		Email:         string(u.Email),
		EmailVerified: u.EmailVerifiedAt != nil,
		CreatedAt:     u.CreatedAt,
		UpdatedAt:     u.UpdatedAt,
	}
}

type errorResponse struct {
	Error string `json:"error"`
}
```

## json.go

`internal/delivery/httpapi/json.go`

```go
package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
)

// maxBodyBytes bounds a request body: a user's JSON is well under 1 KiB, and
// an unbounded body would let one request fill the server's memory.
const maxBodyBytes = 1 << 20

// errMalformed is a shape error: the body is not the JSON the endpoint expects.
var errMalformed = errors.New("malformed request")

// decodeJSON reads exactly one JSON object into dst, rejecting unknown fields
// and trailing data, so a typo in a field name is an error, not a silent no-op.
func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) error {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	dec.DisallowUnknownFields()

	if err := dec.Decode(dst); err != nil {
		return fmt.Errorf("%w: %v", errMalformed, err)
	}
	if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return fmt.Errorf("%w: a single JSON object is expected", errMalformed)
	}

	return nil
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
```

## errors.go

`internal/delivery/httpapi/errors.go`

```go
package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net/http"

	usecaseuser "internal/application/usecases/user"
	"internal/domain/user"
)

// writeError is the only place where an error becomes a status code. Known
// errors are matched with errors.Is, so the wrapping added by the use case
// ("loading user: user not found") does not matter.
func writeError(w http.ResponseWriter, r *http.Request, logger *slog.Logger, err error) {
	switch {
	case errors.Is(err, errMalformed):
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: err.Error()})

	case errors.Is(err, user.ErrInvalidEmail),
		errors.Is(err, user.ErrPasswordTooShort),
		errors.Is(err, user.ErrEmailUnchanged),
		errors.Is(err, usecaseuser.ErrNothingToUpdate):
		writeJSON(w, http.StatusUnprocessableEntity, errorResponse{Error: err.Error()})

	case errors.Is(err, usecaseuser.ErrUserNotFound):
		writeJSON(w, http.StatusNotFound, errorResponse{Error: "user not found"})

	case errors.Is(err, usecaseuser.ErrEmailAlreadyExists):
		writeJSON(w, http.StatusConflict, errorResponse{Error: "user email already exists"})

	case errors.Is(err, context.Canceled):
		// the client went away: nobody reads the response
		logger.Info("request canceled", "method", r.Method, "path", r.URL.Path)

	default:
		// unknown: the detail goes to the logs, never to the client
		logger.Error("request failed", "method", r.Method, "path", r.URL.Path, "error", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "internal error"})
	}
}
```

## user_handler.go

`internal/delivery/httpapi/user_handler.go`

```go
package httpapi

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"uuid"

	usecaseuser "internal/application/usecases/user"
	"internal/domain/user"
)

type userCreator interface {
	Execute(ctx context.Context, input usecaseuser.CreateUserInput) (user.User, error)
}

type userUpdater interface {
	Execute(ctx context.Context, input usecaseuser.UpdateUserInput) (user.User, error)
}

type UserHandler struct {
	userCreator userCreator
	userUpdater userUpdater
	logger      *slog.Logger
}

func NewUserHandler(creator userCreator, updater userUpdater, logger *slog.Logger) *UserHandler {
	return &UserHandler{userCreator: creator, userUpdater: updater, logger: logger}
}

// Create handles POST /users: decode, build the input, call Execute, present.
func (h *UserHandler) Create(w http.ResponseWriter, r *http.Request) {
	var req createUserRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeError(w, r, h.logger, err)
		return
	}

	u, err := h.userCreator.Execute(r.Context(), usecaseuser.CreateUserInput{
		Email:    req.Email,
		Password: req.Password,
	})
	if err != nil {
		writeError(w, r, h.logger, err)
		return
	}

	w.Header().Set("Location", "/users/"+u.ID.String())
	writeJSON(w, http.StatusCreated, toUserResponse(u))
}

// Update handles PATCH /users/{id}.
func (h *UserHandler) Update(w http.ResponseWriter, r *http.Request) {
	// a malformed id is a shape error, like a malformed body
	id, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeError(w, r, h.logger, fmt.Errorf("%w: id must be a uuid", errMalformed))
		return
	}

	var req updateUserRequest
	if err := decodeJSON(w, r, &req); err != nil {
		writeError(w, r, h.logger, err)
		return
	}

	// "nothing to update" is not checked here: the use case owns that rule
	u, err := h.userUpdater.Execute(r.Context(), usecaseuser.UpdateUserInput{
		ID:       id,
		Email:    req.Email,
		Password: req.Password,
	})
	if err != nil {
		writeError(w, r, h.logger, err)
		return
	}

	writeJSON(w, http.StatusOK, toUserResponse(u))
}
```

## user_handler_test.go

`internal/delivery/httpapi/user_handler_test.go`

```go
package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
	"uuid"

	usecaseuser "internal/application/usecases/user"
	"internal/domain/user"
)

// The use cases are replaced by fakes: no store, no hasher, no database.
type fakeUserCreator struct {
	got  usecaseuser.CreateUserInput
	user user.User
	err  error
}

func (f *fakeUserCreator) Execute(_ context.Context, input usecaseuser.CreateUserInput) (user.User, error) {
	f.got = input
	return f.user, f.err
}

type fakeUserUpdater struct {
	got  usecaseuser.UpdateUserInput
	user user.User
	err  error
}

func (f *fakeUserUpdater) Execute(_ context.Context, input usecaseuser.UpdateUserInput) (user.User, error) {
	f.got = input
	return f.user, f.err
}

var ada = user.User{
	ID:           uuid.MustParse("019a8f2c-6d41-7b3e-9a57-3f1e2d4c6b80"),
	Email:        "ada@example.com",
	PasswordHash: "secret-hash",
	CreatedAt:    time.Date(2026, 11, 10, 9, 0, 0, 0, time.UTC),
	UpdatedAt:    time.Date(2026, 11, 10, 9, 0, 0, 0, time.UTC),
}

func serve(creator *fakeUserCreator, updater *fakeUserUpdater, method, path, body string) *httptest.ResponseRecorder {
	logger := slog.New(slog.DiscardHandler)
	router := NewRouter(NewUserHandler(creator, updater, logger))
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, httptest.NewRequest(method, path, strings.NewReader(body)))
	return rec
}

func TestCreateUser(t *testing.T) {
	valid := `{"email":"ada@example.com","password":"correct horse"}`

	tests := []struct {
		name       string
		body       string
		ucErr      error
		wantStatus int
		wantBody   string
	}{
		{name: "created", body: valid, wantStatus: http.StatusCreated, wantBody: `"email":"ada@example.com"`},
		{name: "malformed json", body: `{"email":`, wantStatus: http.StatusBadRequest, wantBody: "malformed request"},
		{name: "unknown field", body: `{"mail":"ada@example.com"}`, wantStatus: http.StatusBadRequest, wantBody: "unknown field"},
		{name: "two objects", body: valid + valid, wantStatus: http.StatusBadRequest, wantBody: "single JSON object"},
		{name: "invalid email", body: valid, ucErr: user.ErrInvalidEmail, wantStatus: http.StatusUnprocessableEntity, wantBody: "invalid email"},
		{name: "duplicate email", body: valid, ucErr: usecaseuser.ErrEmailAlreadyExists, wantStatus: http.StatusConflict, wantBody: "already exists"},
		{name: "unknown error", body: valid, ucErr: errors.New("disk full"), wantStatus: http.StatusInternalServerError, wantBody: "internal error"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			creator := &fakeUserCreator{user: ada, err: tt.ucErr}
			rec := serve(creator, nil, "POST", "/users", tt.body)

			if rec.Code != tt.wantStatus {
				t.Errorf("status = %d, want %d (body: %s)", rec.Code, tt.wantStatus, rec.Body)
			}
			if !strings.Contains(rec.Body.String(), tt.wantBody) {
				t.Errorf("body = %s, want it to contain %q", rec.Body, tt.wantBody)
			}
			if strings.Contains(rec.Body.String(), "disk full") || strings.Contains(rec.Body.String(), "secret-hash") {
				t.Errorf("body leaks an internal detail: %s", rec.Body)
			}
		})
	}
}

func TestCreateUserResponse(t *testing.T) {
	creator := &fakeUserCreator{user: ada}
	rec := serve(creator, nil, "POST", "/users", `{"email":"ada@example.com","password":"correct horse"}`)

	// raw strings reach the use case, unparsed
	if creator.got.Email != "ada@example.com" || creator.got.Password != "correct horse" {
		t.Errorf("input = %+v", creator.got)
	}
	if loc := rec.Header().Get("Location"); loc != "/users/"+ada.ID.String() {
		t.Errorf("Location = %q", loc)
	}

	var got map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	want := map[string]any{
		"id": ada.ID.String(), "email": "ada@example.com", "email_verified": false,
		"created_at": "2026-11-10T09:00:00Z", "updated_at": "2026-11-10T09:00:00Z",
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s = %v, want %v", k, got[k], v)
		}
	}
	if len(got) != len(want) {
		t.Errorf("response has %d fields, want %d: %v", len(got), len(want), got)
	}
}

func TestUpdateUser(t *testing.T) {
	path := "/users/" + ada.ID.String()

	tests := []struct {
		name       string
		path       string
		body       string
		ucErr      error
		wantStatus int
	}{
		{name: "updated", path: path, body: `{"email":"grace@example.com"}`, wantStatus: http.StatusOK},
		{name: "id not a uuid", path: "/users/42", body: `{}`, wantStatus: http.StatusBadRequest},
		{name: "nothing to update", path: path, body: `{}`, ucErr: usecaseuser.ErrNothingToUpdate, wantStatus: http.StatusUnprocessableEntity},
		{name: "not found", path: path, body: `{"email":"grace@example.com"}`, ucErr: fmt.Errorf("loading user: %w", usecaseuser.ErrUserNotFound), wantStatus: http.StatusNotFound},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			updater := &fakeUserUpdater{user: ada, err: tt.ucErr}
			rec := serve(nil, updater, "PATCH", tt.path, tt.body)

			if rec.Code != tt.wantStatus {
				t.Errorf("status = %d, want %d (body: %s)", rec.Code, tt.wantStatus, rec.Body)
			}
		})
	}
}

func TestUpdateUserLeavesMissingFieldsOut(t *testing.T) {
	updater := &fakeUserUpdater{user: ada}
	serve(nil, updater, "PATCH", "/users/"+ada.ID.String(), `{"email":"grace@example.com"}`)

	if updater.got.ID != ada.ID || updater.got.Email == nil || *updater.got.Email != "grace@example.com" || updater.got.Password != nil {
		t.Errorf("input = %+v, want the id, the email, and no password", updater.got)
	}
}
```

## What stays out of this package

- **Email and password rules**: `user.ParseEmail` and `user.ParsePassword`, called by the use case. The handler passes raw strings.
- **"At least one field to update"**: `UpdateUserInput.Validate` in the use case. The handler only checks that the body is JSON and the id a UUID.
- **Building the use cases, the stores, the logger, and the `http.Server`, and shutting it down**: `cmd/<app>` (`main.md`).
- **Authentication**: a middleware in this package when the API needs one. It puts the caller's identity in the use case input, and the use case decides what the caller may do.
