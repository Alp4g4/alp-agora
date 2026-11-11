---
name: go-ssr-templ
description: Rules for server-side rendered web pages in a Go clean architecture project with templ, htmx and Tailwind CSS, defining what the view layer must contain (templ layouts, pages and components rendering view models built by the presenter, handlers returning a full page or an htmx fragment from the same component, forms that work without JavaScript, validation errors re-rendered in the form, Tailwind classes written as complete strings using the theme tokens, embedded static assets) and what it must never contain (domain entities in templates, business logic or formatting in templates, JSON responses to htmx requests, unescaped user data, class names built at run time, raw colors outside the theme). Use when writing or reviewing a templ component, a page, an htmx interaction, or the handler that renders them.
---

# Go SSR with templ, htmx and Tailwind

Server-rendered pages are a delivery mechanism (`go-clean-arch-delivery`). A request goes through the same steps as any other entry point, and the HTML is the presentation:

```
request → handler → use case → presenter → view model → templ component → HTML
```

- **The handler** decodes the form or the query, calls one use case, and picks what to render.
- **The presenter** turns the result or the error into a view model: strings ready to display, messages per field.
- **The templ component** renders the view model. It is a typed Go function: a missing field or a wrong type fails at compile time.
- **htmx** sends the same requests from the page and swaps the HTML fragment it gets back. Without JavaScript, the same forms and links still work.
- **Tailwind** styles the components with the theme tokens of `web-ui-design`, whose catalog the components implement.

## References

- `references/render-example.md`: the shared plumbing, tested: rendering a page or a fragment, redirects, errors retargeted to the alerts region, CSRF protection, embedded and versioned assets.
- `references/form-example.md`: a complete form, tested: catalog components (`Button`, `Field`, `Alert`), the layout with the htmx configuration, a page and its fragment, the handler and its presenter, and the handler tests.

## Layout

```
internal/delivery/web/
├── router.go                 # routes, CSRF protection
├── render.go                 # render, redirect, renderError
├── user_handler.go           # calls the use case, presents the result, renders
├── user_handler_test.go
├── static/
│   ├── static.go             # embed, versioned URLs, cache headers
│   ├── app.css               # built by Tailwind from the theme: never edited
│   └── htmx.min.js           # vendored, pinned version
└── views/
    ├── layout.templ          # Layout, ErrorPage, htmx configuration
    ├── new_user.templ        # NewUserPage, NewUserForm, UserForm view model
    └── components/           # the web-ui-design catalog
        ├── classes.go        # shared class strings (focus ring)
        ├── button.templ
        ├── field.templ
        └── alert.templ
assets/css/app.css            # Tailwind entry point and theme (web-ui-design)
```

The generated `*_templ.go` files sit next to each `.templ` file.

## Must contain

- **View models** declared in `views`, next to the page that renders them, holding display-ready strings.
- **A presenter in the handler** that maps the use case result and its errors to the view model.
- **One `render` function** that sends the full page or the htmx fragment, from the same component.
- **Forms with `method` and `action`**, enhanced with `hx-post` on the same URL.
- **Validation errors re-rendered in the form** with status 422, the entered values, and a message per field.
- **A redirect after every successful POST**: `HX-Redirect` for htmx, `303 See Other` otherwise.
- **The htmx configuration** in the layout, so 4xx and 5xx responses are swapped where the server decides.
- **CSRF protection** with `http.CrossOriginProtection` around the router.
- **Embedded static assets** with versioned URLs: the Tailwind output and a pinned copy of htmx.
- **The generated `*_templ.go` files**, committed.

## Must never contain

- **Domain entities or application types in `views`.** The views package imports neither `internal/domain` nor `internal/application`.
- **Logic or formatting in templates.** No business condition, no date or money formatting, no call to another layer. A template shows fields, loops over lists, and branches on display flags.
- **JSON responses to htmx.** htmx swaps HTML.
- **A separate template for the fragment.** The fragment is a component the page embeds.
- **Unescaped data.** No `templ.Raw` on anything that comes from a user or the database. No `templ.SafeURL` on a URL the server did not build.
- **Class names built at run time.** No `"bg-" + color`. Tailwind only generates classes it finds written out in the source.
- **Raw colors, arbitrary values, `dark:` variants, or control styles in pages.** The rules of `web-ui-design` apply.
- **htmx from a CDN.** The page loads its own pinned copy.
- **Changes on `GET`.** A link or a page load never modifies data.

## Design rules

1. **`views` knows only view models.** A page takes a view model declared next to it (`UserForm`, `UserList`). Its fields are what the page shows, already formatted: `CreatedAt string` ("10 Nov 2026"), not `time.Time`. The handler's presenter builds it from the use case's result.
2. **The presenter maps errors to fields.** One function per form (`presentUserFormError`) turns the known use case errors into a message next to the field concerned, and reports when it cannot place an error. The messages follow `web-ui-design`: they say how to fix the value.
3. **Three kinds of templ components.** The `Layout` (the document, with `{ children... }`), pages (`<Name>Page`, one per URL), and fragments (`<Name>Form`, `<Name>List`, the parts htmx replaces). Pages assemble fragments and catalog components, and the catalog lives in `views/components`.
4. **One component, two outputs.** `render(w, r, status, page, fragment)` sends the fragment when `HX-Request` is `true` and the full page otherwise. A history restore (`HX-History-Restore-Request`) gets the full page. Every response sets `Vary: HX-Request`, so a cache never serves one for the other. Render into a buffer first, so a failure mid-render can still become a 500.
5. **Forms work without JavaScript.** `method="post" action="/users"` and `hx-post="/users"` on the same form, the same handler, the same response shape. `hx-target="this"` and `hx-swap="outerHTML"` replace the form with the response, and `hx-disabled-elt="find button[type=submit]"` prevents a double submit.
6. **Validation errors return the form with 422.** The handler renders the same fragment with the entered values and the messages: htmx swaps it in place, a browser without JavaScript gets the full page with the form. A password is never sent back.
7. **Configure htmx to swap errors.** By default htmx 2 discards 4xx and 5xx responses, so a 422 form would never appear. The layout's `<meta name="htmx-config">` swaps every status but 204, and keeps 4xx and 5xx flagged as errors. The server then decides where each response goes.
8. **Other errors go to the alerts region.** For an error the page cannot show in place (a failure, a missing resource), `renderError` logs the detail, sets `HX-Retarget: #alerts` and `HX-Reswap: innerHTML` for htmx, and renders a generic `Alert`. A browser without JavaScript gets the error page. The detail never reaches the page.
9. **Redirect after a successful POST.** `HX-Redirect` with 204 for htmx, `303 See Other` otherwise. Reloading the next page never submits the form again.
10. **Update other regions out of band.** When one response must also change another part of the page (a flash message, a counter), render that part too, with its `id` and `hx-swap-oob="true"`. Never make a second request for it.
11. **CSRF protection without tokens.** `http.NewCrossOriginProtection().Handler(mux)` (Go 1.25 and later) rejects cross-origin `POST`, `PUT`, `PATCH`, and `DELETE` from the browser's `Sec-Fetch-Site` and `Origin` headers. It relies on `GET` never changing anything.
12. **templ escapes, so let it.** Text and attribute values are escaped, and a `string` in `href` or `src` is sanitized. `templ.Raw` and `templ.SafeURL` turn that off: use them only on content the server wrote itself.
13. **Classes are complete strings in the source.** A component's variants are a `map[Variant]string` of full class strings in the component's file, and a boolean class uses `templ.KV("class", condition)`. Tailwind scans `.templ` and `.go` files through `@source`, so every class it needs is written out somewhere. Shared strings, such as the focus ring, live in `components/classes.go`.
14. **Components follow the catalog.** Each component of `web-ui-design` is implemented once in `views/components`, with its variants as a typed parameter (`ButtonPrimary`, `AlertDanger`). Components take no class parameter: a page cannot restyle a control.
15. **Assets are embedded and versioned.** `static` embeds `app.css` and `htmx.min.js`, and `static.URL("app.css")` adds a hash of the content (`/static/app.css?v=1a2b3c4d`). A versioned request is served with `Cache-Control: immutable`, and a new build gets a new URL. htmx is a copy of a pinned release in `static/`, updated on purpose. `app.css` is generated by Tailwind from the theme and committed, so `go build` works with no other tool.
16. **Pin templ and commit the generated code.** templ is a Go tool in `go.mod` (`go get -tool github.com/a-h/templ/cmd/templ@<version>`), at the same version as the `github.com/a-h/templ` module, so the generator and the runtime match. The `*_templ.go` files are committed. In CI, `go tool templ generate` then `git diff --exit-code`, and `go tool templ fmt -fail .`.
17. **Test through the router.** Handler tests use `httptest` with a fake use case: the full page and the fragment, a 422 with its messages and values, both redirects, a retargeted error, and a cross-origin `POST` rejected. A component can be tested alone by rendering it into a buffer.

## Quick check

Before adding a page or an interaction, ask:

1. Does anything in `views` import the domain or the application, or format a value?
2. Does the handler send the page and the fragment from the same component, with `Vary: HX-Request`?
3. Does the form work with JavaScript disabled?
4. Does a validation error come back as 422 with the values and a message per field, and an unexpected error as a generic alert?
5. Does every successful POST redirect?
6. Is every class written out in full, with tokens only?
7. Is anything rendered with `templ.Raw` or `templ.SafeURL`, and did the server write it?
