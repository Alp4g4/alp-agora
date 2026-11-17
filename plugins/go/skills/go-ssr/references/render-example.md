# Rendering, redirects, errors, and assets

The shared plumbing of `internal/delivery/web`, used by every handler. It is the tested code of a working project (templ v0.3.1020, htmx 2.0.11, Go 1.25 or later).

- [render.go](#rendergo): `render`, `redirect`, and `renderError`
- [router.go](#routergo): the routes and CSRF protection
- [static.go](#staticgo): embedded assets with versioned URLs and cache headers

## render.go

`internal/delivery/web/render.go`

```go
package web

import (
	"bytes"
	"log/slog"
	"net/http"

	"github.com/a-h/templ"

	"internal/delivery/web/views"
	"internal/delivery/web/views/components"
)

// isHTMX reports whether htmx sent the request and expects a fragment.
// A history restore asks for the full page, so it is not one.
func isHTMX(r *http.Request) bool {
	return r.Header.Get("HX-Request") == "true" && r.Header.Get("HX-History-Restore-Request") != "true"
}

// render writes the fragment to htmx and the full page otherwise. The page embeds
// the same fragment, so the two never drift apart.
func render(w http.ResponseWriter, r *http.Request, status int, page, fragment templ.Component) {
	c := page
	if isHTMX(r) {
		c = fragment
	}

	// Render into a buffer first: a failure mid-render can still become a 500.
	var buf bytes.Buffer
	if err := c.Render(r.Context(), &buf); err != nil {
		slog.Error("rendering", "path", r.URL.Path, "error", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	w.Header().Add("Vary", "HX-Request")
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(status)
	_, _ = buf.WriteTo(w)
}

// redirect ends a successful POST: htmx follows HX-Redirect, a browser without
// JavaScript follows the 303.
func redirect(w http.ResponseWriter, r *http.Request, url string) {
	if isHTMX(r) {
		w.Header().Set("HX-Redirect", url)
		w.WriteHeader(http.StatusNoContent)
		return
	}
	http.Redirect(w, r, url, http.StatusSeeOther)
}

// renderError shows an error the page cannot handle in place: in the alerts
// region for htmx, as a full error page otherwise.
func renderError(w http.ResponseWriter, r *http.Request, status int, message string) {
	if isHTMX(r) {
		w.Header().Set("HX-Retarget", "#alerts")
		w.Header().Set("HX-Reswap", "innerHTML")
	}
	render(w, r, status, views.ErrorPage(message), components.Alert(components.AlertDanger, message))
}
```

- `render` picks the fragment for htmx, but not for a history restore: htmx asks for the full page when its history cache misses.
- `redirect` answers htmx with `HX-Redirect` and 204: htmx reads the header before any swap, and the empty body is not swapped.
- `renderError` keeps the detail out of the page. The handler logs it before calling.

## router.go

`internal/delivery/web/router.go`

```go
package web

import (
	"net/http"

	"internal/delivery/web/static"
)

func NewRouter(users *UserHandler) http.Handler {
	mux := http.NewServeMux()
	mux.Handle("GET /static/", static.Handler())
	mux.HandleFunc("GET /users/new", users.New)
	mux.HandleFunc("POST /users", users.Create)

	// CSRF protection from the browser's Sec-Fetch-Site and Origin headers: no token.
	return http.NewCrossOriginProtection().Handler(mux)
}
```

`http.CrossOriginProtection` rejects a cross-site `POST` with 403, from the `Sec-Fetch-Site` header (or `Origin` for older browsers). Same-origin requests, and requests without either header (`curl`, tests), pass.

## static.go

`internal/delivery/web/static/static.go`

```go
package static

import (
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"io/fs"
	"net/http"
)

//go:embed app.css htmx.min.js
var files embed.FS

// versions holds a short hash of each file, computed once from the embedded content.
var versions = hashFiles()

func hashFiles() map[string]string {
	v := map[string]string{}
	entries, _ := fs.ReadDir(files, ".")
	for _, e := range entries {
		data, _ := fs.ReadFile(files, e.Name())
		sum := sha256.Sum256(data)
		v[e.Name()] = hex.EncodeToString(sum[:4])
	}
	return v
}

// URL returns the path of an asset with its content hash: a new build gets a new
// URL, so browsers can cache every version forever.
func URL(name string) string {
	return "/static/" + name + "?v=" + versions[name]
}

// Handler serves the embedded assets under /static/.
func Handler() http.Handler {
	files := http.FileServerFS(files)
	return http.StripPrefix("/static/", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("v") != "" {
			w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		}
		files.ServeHTTP(w, r)
	}))
}
```

- `URL` is called from the layout: `<link rel="stylesheet" href={ static.URL("app.css") }/>`.
- The hash is computed once, from the embedded content, when the package loads.
- An unversioned request (`/static/app.css`) is served without the long cache header.
