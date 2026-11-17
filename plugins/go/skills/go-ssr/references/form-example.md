# A complete form

A "new user" form, end to end: the shared components, the layout, the page and its fragment, the handler with its presenter, and the tests. It calls the `CreateUserUC` use case of `go-clean-architecture`. The rendering helpers are in `render-example.md`.

- [Components](#components): [classes.go](#classesgo), [button.templ](#buttontempl), [field.templ](#fieldtempl), [alert.templ](#alerttempl)
- [Layout](#layout): [layout.templ](#layouttempl), with the htmx configuration
- [Page and fragment](#page-and-fragment): [new_user.templ](#new_usertempl)
- [Handler and presenter](#handler-and-presenter): [user_handler.go](#user_handlergo)
- [Tests](#tests): [user_handler_test.go](#user_handler_testgo)

## Components

## classes.go

`internal/delivery/web/views/components/classes.go`

```go
package components

// Complete class strings only: Tailwind reads this file to find them.
const focusRing = "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
```

## button.templ

`internal/delivery/web/views/components/button.templ`

```templ
package components

type ButtonVariant int

const (
	ButtonPrimary ButtonVariant = iota
	ButtonSecondary
	ButtonDanger
	ButtonGhost
)

const buttonBase = "inline-flex min-h-11 items-center justify-center gap-2 rounded-md px-4 text-sm font-medium disabled:cursor-not-allowed disabled:opacity-50"

var buttonVariants = map[ButtonVariant]string{
	ButtonPrimary:   "bg-primary text-on-primary hover:bg-primary-hover",
	ButtonSecondary: "border border-line-strong bg-surface text-content hover:bg-surface-muted",
	ButtonDanger:    "bg-danger text-on-danger hover:bg-danger/90",
	ButtonGhost:     "text-content hover:bg-surface-muted",
}

type ButtonProps struct {
	Label   string
	Variant ButtonVariant
	Submit  bool
}

func (p ButtonProps) buttonType() string {
	if p.Submit {
		return "submit"
	}
	return "button"
}

templ Button(p ButtonProps) {
	<button type={ p.buttonType() } class={ buttonBase, buttonVariants[p.Variant], focusRing }>{ p.Label }</button>
}
```

The variants are a map of complete class strings: Tailwind finds `hover:bg-danger/90` in this file even if no page uses the danger variant yet.

## field.templ

`internal/delivery/web/views/components/field.templ`

```templ
package components

import "strings"

const fieldControl = "block min-h-11 w-full rounded-md border border-line-strong bg-surface px-3 text-content placeholder:text-content-muted aria-invalid:border-danger"

type FieldProps struct {
	ID           string
	Name         string
	Label        string
	Type         string
	Autocomplete string
	Value        string
	Help         string
	Error        string
	Required     bool
}

func (p FieldProps) describedBy() string {
	var ids []string
	if p.Help != "" {
		ids = append(ids, p.ID+"-help")
	}
	if p.Error != "" {
		ids = append(ids, p.ID+"-error")
	}
	return strings.Join(ids, " ")
}

templ Field(p FieldProps) {
	<div class="space-y-1">
		<label for={ p.ID } class="block text-sm font-medium text-content">{ p.Label }</label>
		<input
			id={ p.ID }
			name={ p.Name }
			type={ p.Type }
			autocomplete={ p.Autocomplete }
			value={ p.Value }
			required?={ p.Required }
			if p.Error != "" {
				aria-invalid="true"
			}
			if p.describedBy() != "" {
				aria-describedby={ p.describedBy() }
			}
			class={ fieldControl, focusRing }
		/>
		if p.Help != "" {
			<p id={ p.ID + "-help" } class="text-sm text-content-muted">{ p.Help }</p>
		}
		if p.Error != "" {
			<p id={ p.ID + "-error" } class="text-sm text-danger">{ p.Error }</p>
		}
	</div>
}
```

`aria-invalid` and `aria-describedby` are only written when they have a value: templ supports `if` blocks inside an element's attributes.

## alert.templ

`internal/delivery/web/views/components/alert.templ`

```templ
package components

type AlertVariant int

const (
	AlertDanger AlertVariant = iota
	AlertSuccess
)

var alertVariants = map[AlertVariant]string{
	AlertDanger:  "border-danger bg-danger-subtle text-danger",
	AlertSuccess: "border-success bg-success-subtle text-success",
}

func alertRole(v AlertVariant) string {
	if v == AlertDanger {
		return "alert"
	}
	return "status"
}

templ Alert(variant AlertVariant, message string) {
	<div role={ alertRole(variant) } class={ "flex gap-3 rounded-md border p-4 text-sm", alertVariants[variant] }>
		<p>{ message }</p>
	</div>
}
```

## Layout

## layout.templ

`internal/delivery/web/views/layout.templ`

```templ
package views

import "internal/delivery/web/static"

// Every status but 204 is swapped: the server decides where. A 422 replaces the
// form it answers, any other error is retargeted to #alerts by the server.
const htmxConfig = `{"responseHandling":[{"code":"204","swap":false},{"code":"[23]..","swap":true},{"code":"[45]..","swap":true,"error":true}]}`

templ Layout(title string) {
	<!DOCTYPE html>
	<html lang="en">
		<head>
			<meta charset="utf-8"/>
			<meta name="viewport" content="width=device-width, initial-scale=1"/>
			<meta name="htmx-config" content={ htmxConfig }/>
			<title>{ title }</title>
			<link rel="stylesheet" href={ static.URL("app.css") }/>
			<script src={ static.URL("htmx.min.js") } defer></script>
		</head>
		<body>
			<a href="#main" class="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:rounded-md focus:bg-surface focus:px-4 focus:py-2">Skip to content</a>
			<main id="main" class="mx-auto max-w-5xl space-y-8 px-4 py-8">
				<div id="alerts"></div>
				{ children... }
			</main>
		</body>
	</html>
}

templ ErrorPage(message string) {
	@Layout("Error") {
		<h1 class="text-2xl font-semibold text-content">Something went wrong</h1>
		<p class="text-content-muted">{ message }</p>
	}
}
```

The `htmx-config` meta tag replaces htmx's default `responseHandling`, which discards 4xx and 5xx responses. The list is complete: htmx replaces the whole setting, it does not merge it.

## Page and fragment

## new_user.templ

`internal/delivery/web/views/new_user.templ`

```templ
package views

import "internal/delivery/web/views/components"

// UserForm is the view model of the form: the values to show again and one
// message per field, built by the handler's presenter.
type UserForm struct {
	Email         string
	EmailError    string
	PasswordError string
}

templ NewUserPage(form UserForm) {
	@Layout("New user") {
		<h1 class="text-2xl font-semibold text-content">New user</h1>
		@NewUserForm(form)
	}
}

templ NewUserForm(form UserForm) {
	<form
		id="new-user-form"
		method="post"
		action="/users"
		hx-post="/users"
		hx-target="this"
		hx-swap="outerHTML"
		hx-disabled-elt="find button[type=submit]"
		class="max-w-md space-y-6"
	>
		@components.Field(components.FieldProps{ID: "email", Name: "email", Label: "Email", Type: "email", Autocomplete: "email", Value: form.Email, Error: form.EmailError, Required: true})
		@components.Field(components.FieldProps{ID: "password", Name: "password", Label: "Password", Type: "password", Autocomplete: "new-password", Help: "At least 6 characters.", Error: form.PasswordError, Required: true})
		@components.Button(components.ButtonProps{Label: "Create user", Variant: components.ButtonPrimary, Submit: true})
	</form>
}
```

`NewUserPage` embeds `NewUserForm`: htmx gets the form alone, a browser the page around it, from one component.

## Handler and presenter

## user_handler.go

`internal/delivery/web/user_handler.go`

```go
package web

import (
	"context"
	"errors"
	"log/slog"
	"net/http"

	usecaseuser "internal/application/usecase/user"
	"internal/delivery/web/views"
	"internal/domain/user"
)

type userCreator interface {
	Execute(ctx context.Context, input usecaseuser.CreateUserInput) (user.User, error)
}

type UserHandler struct {
	userCreator userCreator
	logger      *slog.Logger
}

func NewUserHandler(creator userCreator, logger *slog.Logger) *UserHandler {
	return &UserHandler{userCreator: creator, logger: logger}
}

func (h *UserHandler) New(w http.ResponseWriter, r *http.Request) {
	form := views.UserForm{}
	render(w, r, http.StatusOK, views.NewUserPage(form), views.NewUserForm(form))
}

func (h *UserHandler) Create(w http.ResponseWriter, r *http.Request) {
	// the password is never sent back: only the email is kept in the view model
	form := views.UserForm{Email: r.PostFormValue("email")}

	_, err := h.userCreator.Execute(r.Context(), usecaseuser.CreateUserInput{
		Email:    form.Email,
		Password: r.PostFormValue("password"),
	})
	if err != nil {
		if presentUserFormError(&form, err) {
			render(w, r, http.StatusUnprocessableEntity, views.NewUserPage(form), views.NewUserForm(form))
			return
		}

		h.logger.Error("creating user", "error", err)
		renderError(w, r, http.StatusInternalServerError, "The user could not be created. Try again in a moment.")
		return
	}

	redirect(w, r, "/users")
}

// presentUserFormError puts the message of a known error next to its field.
// It reports false when the form cannot show the error.
func presentUserFormError(form *views.UserForm, err error) bool {
	switch {
	case errors.Is(err, user.ErrInvalidEmail):
		form.EmailError = "Enter an email like name@example.com."
	case errors.Is(err, usecaseuser.ErrEmailAlreadyExists):
		form.EmailError = "This email is already used by another account."
	case errors.Is(err, user.ErrPasswordTooShort):
		form.PasswordError = "Use at least 6 characters."
	default:
		return false
	}
	return true
}
```

## Tests

## user_handler_test.go

`internal/delivery/web/user_handler_test.go`

```go
package web

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	usecaseuser "internal/application/usecase/user"
	"internal/domain/user"
)

type fakeUserCreator struct{ err error }

func (f fakeUserCreator) Execute(context.Context, usecaseuser.CreateUserInput) (user.User, error) {
	return user.User{}, f.err
}

func do(t *testing.T, ucErr error, method, path string, form url.Values, headers map[string]string) *httptest.ResponseRecorder {
	t.Helper()
	router := NewRouter(NewUserHandler(fakeUserCreator{err: ucErr}, slog.New(slog.NewTextHandler(io.Discard, nil))))
	var body io.Reader
	if form != nil {
		body = strings.NewReader(form.Encode())
	}
	req := httptest.NewRequest(method, path, body)
	if form != nil {
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	return rec
}

var htmx = map[string]string{"HX-Request": "true"}
var valid = url.Values{"email": {"ada@example.com"}, "password": {"correct horse"}}

func TestPageOrFragment(t *testing.T) {
	page := do(t, nil, "GET", "/users/new", nil, nil)
	frag := do(t, nil, "GET", "/users/new", nil, htmx)
	restore := do(t, nil, "GET", "/users/new", nil, map[string]string{"HX-Request": "true", "HX-History-Restore-Request": "true"})

	if !strings.Contains(page.Body.String(), "<html") || !strings.Contains(page.Body.String(), `id="new-user-form"`) {
		t.Errorf("page: want full document with the form")
	}
	if strings.Contains(frag.Body.String(), "<html") || !strings.Contains(frag.Body.String(), `id="new-user-form"`) {
		t.Errorf("fragment: want the form only, got %q", frag.Body.String()[:80])
	}
	if !strings.Contains(restore.Body.String(), "<html") {
		t.Errorf("history restore: want the full page")
	}
	if page.Header().Get("Vary") != "HX-Request" {
		t.Errorf("Vary = %q", page.Header().Get("Vary"))
	}
}

func TestValidationError(t *testing.T) {
	rec := do(t, user.ErrInvalidEmail, "POST", "/users", url.Values{"email": {"ada@"}, "password": {"secret"}}, htmx)
	body := rec.Body.String()
	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d", rec.Code)
	}
	for _, want := range []string{`aria-invalid="true"`, `aria-describedby="email-error"`, "Enter an email like", `value="ada@"`} {
		if !strings.Contains(body, want) {
			t.Errorf("missing %q", want)
		}
	}
	if strings.Contains(body, "secret") {
		t.Errorf("the password was sent back")
	}
	if strings.Contains(body, "<html") {
		t.Errorf("htmx validation error: want the form fragment only")
	}
}

func TestSuccessRedirect(t *testing.T) {
	h := do(t, nil, "POST", "/users", valid, htmx)
	if h.Code != http.StatusNoContent || h.Header().Get("HX-Redirect") != "/users" {
		t.Errorf("htmx: %d %q", h.Code, h.Header().Get("HX-Redirect"))
	}
	b := do(t, nil, "POST", "/users", valid, nil)
	if b.Code != http.StatusSeeOther || b.Header().Get("Location") != "/users" {
		t.Errorf("browser: %d %q", b.Code, b.Header().Get("Location"))
	}
}

func TestUnknownErrorIsRetargeted(t *testing.T) {
	rec := do(t, errors.New("disk full"), "POST", "/users", valid, htmx)
	if rec.Code != 500 || rec.Header().Get("HX-Retarget") != "#alerts" || rec.Header().Get("HX-Reswap") != "innerHTML" {
		t.Errorf("%d %q %q", rec.Code, rec.Header().Get("HX-Retarget"), rec.Header().Get("HX-Reswap"))
	}
	if !strings.Contains(rec.Body.String(), `role="alert"`) || strings.Contains(rec.Body.String(), "disk full") {
		t.Errorf("want a generic alert, never the detail: %q", rec.Body.String())
	}
}

func TestCrossOriginPostIsRejected(t *testing.T) {
	rec := do(t, nil, "POST", "/users", valid, map[string]string{"Sec-Fetch-Site": "cross-site"})
	same := do(t, nil, "POST", "/users", valid, map[string]string{"Sec-Fetch-Site": "same-origin"})
	if rec.Code != http.StatusForbidden || same.Code != http.StatusSeeOther {
		t.Errorf("cross-site %d, same-origin %d", rec.Code, same.Code)
	}
}

func TestStaticAssetsAreVersioned(t *testing.T) {
	page := do(t, nil, "GET", "/users/new", nil, nil).Body.String()
	i := strings.Index(page, "/static/htmx.min.js?v=")
	if i < 0 {
		t.Fatalf("no versioned htmx URL in the page")
	}
	u := page[i : i+strings.Index(page[i:], `"`)]
	rec := do(t, nil, "GET", u, nil, nil)
	if rec.Code != 200 || !strings.Contains(rec.Header().Get("Cache-Control"), "immutable") || rec.Body.Len() < 1000 {
		t.Errorf("%s: %d %q %d bytes", u, rec.Code, rec.Header().Get("Cache-Control"), rec.Body.Len())
	}
}
```
