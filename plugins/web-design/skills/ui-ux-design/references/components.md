# Component catalog

The components every page is built from. Each entry gives the HTML structure, the variants, the states, the accessibility requirements, and the Tailwind classes, using the tokens of `theme.md`. The project implements each one once, as a reusable component of its own stack, and pages only use those components.

The focus ring shared by every interactive component:

```
focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus
```

## Button

An action. Navigation is a `Link`, even when it looks like a button.

```html
<button type="submit" class="inline-flex min-h-11 items-center justify-center gap-2 rounded-md px-4 text-sm font-medium bg-primary text-on-primary hover:bg-primary-hover disabled:cursor-not-allowed disabled:opacity-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus">
  Save changes
</button>
```

| Variant | Classes after the base | Use |
|---|---|---|
| `primary` | `bg-primary text-on-primary hover:bg-primary-hover` | the main action of a page or a form, one per view |
| `secondary` | `border border-line-strong bg-surface text-content hover:bg-surface-muted` | other actions |
| `danger` | `bg-danger text-on-danger hover:bg-danger/90` | a destructive action, after a confirmation |
| `ghost` | `text-content hover:bg-surface-muted` | low-emphasis actions in toolbars and tables |

- **Base**: `inline-flex min-h-11 items-center justify-center gap-2 rounded-md px-4 text-sm font-medium` and the focus ring.
- **States**: `disabled:cursor-not-allowed disabled:opacity-50`. While a request runs, the button is disabled and shows "Saving…".
- **Accessibility**: the label says what the button does. An icon-only button has an `aria-label`. `type="button"` unless it submits a form.

## Link

```html
<a href="/users" class="text-primary underline underline-offset-4 hover:text-primary-hover focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus">All users</a>
```

- Underlined in text, so it is not identified by color alone.
- The text says where it goes: never "click here".

## Field

A label, a control, an optional help text, and an error message. Every input, select, and textarea is a field.

```html
<div class="space-y-1">
  <label for="email" class="block text-sm font-medium text-content">Email</label>
  <input id="email" name="email" type="email" autocomplete="email" required
         value="ada@example"
         aria-invalid="true" aria-describedby="email-help email-error"
         class="block min-h-11 w-full rounded-md border border-line-strong bg-surface px-3 text-content placeholder:text-content-muted aria-invalid:border-danger focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus">
  <p id="email-help" class="text-sm text-content-muted">We send the confirmation link there.</p>
  <p id="email-error" class="text-sm text-danger">Enter an email like name@example.com</p>
</div>
```

- **Control classes**: `block min-h-11 w-full rounded-md border border-line-strong bg-surface px-3 text-content placeholder:text-content-muted aria-invalid:border-danger` and the focus ring. The same for `select`. A `textarea` adds `py-2` and drops `min-h-11`.
- **With an error**: `aria-invalid="true"`, and the error's `id` in `aria-describedby`. The border turns `danger` through `aria-invalid:`, and the message says how to fix the value.
- **Required**: the `required` attribute, and "(required)" in the label when some fields are optional, or a sentence at the top of the form when all are required.
- **The value is kept** when the form comes back with errors. A password is never sent back.

## Checkbox and radio

```html
<div class="flex items-center gap-3">
  <input id="terms" name="terms" type="checkbox" class="size-5 accent-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus">
  <label for="terms" class="text-sm text-content">I accept the terms</label>
</div>
```

- The native control, colored with `accent-primary`. The label is clickable through `for`.
- A group of radios is a `fieldset` with a `legend`.

## Card

```html
<section class="rounded-lg border border-line bg-surface p-6 shadow-sm" aria-labelledby="profile-title">
  <h2 id="profile-title" class="text-lg font-semibold text-content">Profile</h2>
  ...
</section>
```

A container for a group of content, with its own heading.

## Alert

```html
<div role="alert" class="flex gap-3 rounded-md border border-danger bg-danger-subtle p-4 text-sm text-danger">
  <svg aria-hidden="true" class="size-5 shrink-0" ...></svg>
  <p><strong class="font-semibold">The user was not saved.</strong> Check the highlighted fields.</p>
</div>
```

| Variant | Classes | Role |
|---|---|---|
| `danger` | `border-danger bg-danger-subtle text-danger` | `role="alert"`: read at once by screen readers |
| `success` | `border-success bg-success-subtle text-success` | `role="status"`: read politely |
| `warning` | `border-warning bg-warning-subtle text-warning` | `role="status"` |
| `info` | `border-line bg-surface-muted text-content` | `role="status"` |

- **Base**: `flex gap-3 rounded-md border p-4 text-sm`.
- An icon and a sentence, never the color alone. The page has one region for alerts (`id="alerts"`), at the top of `main`.

## Badge

```html
<span class="inline-flex items-center rounded-full bg-surface-muted px-2 py-0.5 text-xs font-medium text-content">Pending</span>
```

A short status label. The text carries the meaning ("Pending", "Paid"); a color variant only reinforces it: `bg-success-subtle text-success`, `bg-warning-subtle text-warning`, `bg-danger-subtle text-danger`.

## Table

```html
<div class="overflow-x-auto">
  <table class="w-full text-left text-sm">
    <caption class="sr-only">Users</caption>
    <thead class="border-b border-line-strong text-content-muted">
      <tr><th scope="col" class="px-3 py-2 font-medium">Email</th><th scope="col" class="px-3 py-2 font-medium">Created</th></tr>
    </thead>
    <tbody>
      <tr class="border-b border-line"><td class="px-3 py-2">ada@example.com</td><td class="px-3 py-2">10 Nov 2026</td></tr>
    </tbody>
  </table>
</div>
```

- Only for tabular data. `scope="col"` on header cells, a `caption` (visible or `sr-only`).
- The wrapper scrolls horizontally on small screens.
- With no rows, the table is replaced by an `EmptyState`.

## Pagination

Lists use previous and next links, with no page numbers. A page number shifts when rows are added or removed, and needs a count of every row, while a cursor (the last item shown) does not: the server returns the cursors of the previous and next pages.

```html
<nav aria-label="Pagination" class="flex justify-between">
  <a href="?before=…" class="…secondary button classes…">Previous</a>
  <a href="?after=…" class="…secondary button classes…">Next</a>
</nav>
```

A link styled as a secondary button. A missing direction is not rendered, rather than disabled.

## Dialog

```html
<dialog id="confirm-delete" aria-labelledby="confirm-delete-title" class="m-auto max-w-md rounded-lg bg-surface p-6 text-content shadow-lg backdrop:bg-content/50">
  <h2 id="confirm-delete-title" class="text-lg font-semibold">Delete this user?</h2>
  <p class="mt-2 text-sm text-content-muted">This cannot be undone.</p>
  <form method="dialog" class="mt-6 flex justify-end gap-3">
    <button value="cancel" class="…secondary…">Cancel</button>
    <button value="confirm" class="…danger…">Delete</button>
  </form>
</dialog>
```

- The native `dialog`, opened with `showModal()`: it traps focus, closes with Escape, and returns focus to the opener.
- A heading tied with `aria-labelledby`. The safe action first, the destructive one last.

## EmptyState

```html
<div class="rounded-lg border border-dashed border-line-strong p-8 text-center">
  <p class="text-base font-medium text-content">No users yet</p>
  <p class="mt-1 text-sm text-content-muted">Invite the first one to get started.</p>
  <a href="/users/new" class="mt-4 …primary button classes…">Invite a user</a>
</div>
```

What is missing, why, and the action to fix it.

## PageHeader

```html
<header class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
  <div>
    <h1 class="text-2xl font-semibold text-content">Users</h1>
    <p class="mt-1 text-sm text-content-muted">Everyone who can sign in.</p>
  </div>
  <div class="flex gap-3"><!-- the page's main actions: Buttons or Links --></div>
</header>
```

The page's only `h1`, an optional description, and the main actions.

## Layout

The frame every page renders inside.

```html
<body>
  <a href="#main" class="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:rounded-md focus:bg-surface focus:px-4 focus:py-2">Skip to content</a>
  <header class="border-b border-line">
    <nav aria-label="Main" class="mx-auto flex max-w-5xl items-center gap-6 px-4 py-3">…</nav>
  </header>
  <main id="main" class="mx-auto max-w-5xl space-y-8 px-4 py-8">
    <div id="alerts"></div>
    …
  </main>
  <footer class="border-t border-line">…</footer>
</body>
```

- Landmarks: `header`, `nav` with an `aria-label`, `main`, `footer`.
- A skip link, first in the page, visible on focus.
- The `alerts` region, where messages are shown.
