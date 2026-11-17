---
name: ui-ux-design
description: Rules for the visual design of a web interface built with Tailwind CSS, defining what it must contain (one theme file of semantic design tokens for colors, typography, spacing, radius and shadows, with light and dark values, a small catalog of shared UI components that pages assemble, semantic HTML, accessible forms, contrast, focus and keyboard navigation, responsive layouts) and what it must never contain (raw colors or arbitrary values outside the theme, pages styling their own buttons or inputs, one-off components duplicating the catalog, information conveyed by color alone, inaccessible custom controls). Use when choosing or changing the theme, designing or reviewing a page, a form or a UI component, or checking that an interface is consistent and accessible.
---

# UI and UX Design

An interface stays consistent when design decisions are made once, in one place, and everything else reuses them. Three levels, each with one job:

| Level | Holds | Decides |
|---|---|---|
| **Theme** | one CSS file of design tokens | how things look: colors, fonts, radius, shadows, light and dark |
| **Components** | a small catalog (`Button`, `Field`, `Card`, `Alert`, ...) | how each UI element is built from the tokens, its variants, states, and accessibility |
| **Pages** | assemblies of components | what is on the screen and where: layout, order, content |

A page never decides a color, a border, or a button style. A component never decides what a page contains. Changing the look of the product is a change to the theme, and nothing else.

This skill is not tied to a language or a framework. The tokens use Tailwind CSS v4 (`@theme`). The catalog gives each component's HTML, classes, states, and accessibility: the project implements each one once, in whatever it renders pages with (a template partial, a server-side component, a React component).

## References

- `references/theme.md`: the default theme, ready to copy, with its light and dark values and their contrast ratios.
- `references/components.md`: the component catalog, with the variants, states, accessibility requirements, and Tailwind classes of each component.

## Must contain

- **One theme file** declaring every color as a semantic token (`surface`, `content`, `primary`, `danger`, ...), with a light and a dark value.
- **The default palette removed** (`--color-*: initial`), so only the theme's colors exist.
- **A component catalog** that every page uses, with each component's variants and states defined once.
- **Semantic HTML**: landmarks, one `h1` per page, headings in order, buttons for actions and links for navigation.
- **Accessible forms**: a visible label for every field, help and error text tied to the field, errors that say how to fix them.
- **Contrast** of at least 4.5:1 for text and 3:1 for control borders and focus indicators, in light and in dark.
- **A visible focus indicator** on every interactive element, and everything usable with the keyboard alone.
- **Responsive layouts**, built mobile first.

## Must never contain

- **Raw colors**: no `bg-blue-600`, no `#4f46e5` in a class, no `text-white`. With the default palette removed, they generate nothing.
- **Arbitrary values**: no `p-[13px]`, `text-[15px]`, `w-[327px]`. Use the scale.
- **`dark:` variants in components or pages.** Dark mode is a second set of token values in the theme.
- **Pages styling controls.** A page never writes the classes of a button, an input, or an alert: it uses the component.
- **One-off components.** If the catalog lacks something, add it to the catalog first, then use it.
- **Information conveyed by color alone.** An error has a message and an icon, a status has a label, a link in text is underlined.
- **Custom controls where a native element exists.** No `div` with a click handler as a button, no fake select. Use `button`, `a`, `select`, `input`, `dialog`.
- **A removed focus outline** without a visible replacement.

## Design rules

1. **Colors are semantic tokens, named after their role.** `surface` and `surface-muted` (backgrounds), `content` and `content-muted` (text), `line` (decorative borders) and `line-strong` (control borders), `primary` with `primary-hover` and `on-primary` (text on primary), `danger`, `success`, `warning` with their `on-` and `-subtle` variants, `focus`. A component asks for a role (`bg-primary text-on-primary`), never for a hue.
2. **Remove the default palette.** `--color-*: initial` in `@theme` deletes Tailwind's colors, so `bg-blue-600` generates no CSS and a raw color is visibly broken in review. `bg-transparent` and `text-current` still work.
3. **Dark mode lives in the theme only.** The theme redefines the same tokens under `@media (prefers-color-scheme: dark)`. Components and pages contain no `dark:` class and work in both modes unchanged.
4. **Every pairing meets the contrast minimum, in both modes.** Text on its background at least 4.5:1, control borders and focus rings at least 3:1 (WCAG 2.2 AA). When a token changes, check every pairing it is part of again: the theme reference lists them.
5. **Use a subset of the scale.** Spacing: `1, 2, 3, 4, 6, 8, 12, 16` (4 px steps up to 16 px, then 24, 32, 48, 64). Text: `text-sm`, `text-base`, `text-lg`, `text-xl`, `text-2xl`, `text-3xl`. Radius: `rounded-md` for controls, `rounded-lg` for containers, `rounded-full` for pills. Shadows: `shadow-sm` for cards, `shadow-lg` for dialogs. A smaller set makes pages look related.
6. **Pages lay out, components style.** A page uses layout classes only: `flex`, `grid`, `gap-*`, `max-w-*`, `mx-auto`, `px-*`, `py-*`, `space-y-*`, and responsive prefixes. Colors, borders, radius, shadows, and font weights belong to components.
7. **Every interactive component has all its states**: default, hover, `focus-visible`, active, disabled, and loading when it triggers a request. Lists and tables also have an empty state and a loading state.
8. **Focus is always visible.** Every interactive component has `focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus`. The keyboard order follows the reading order, and a skip link leads to the main content.
9. **Native elements first.** A `button` for an action, an `a` for navigation, a `dialog` opened with `showModal()` for a modal (it traps focus and closes with Escape), a `details` for a disclosure. A custom widget follows its WAI-ARIA pattern, and only when no native element fits.
10. **Forms are explicit.** Every field has a visible `label`, its help text and its error linked with `aria-describedby`, and `aria-invalid="true"` when it has an error. Required fields say "required" in text. Inputs use the right `type` and `autocomplete`. Errors are shown next to the field, with a summary at the top of a long form.
11. **Touch targets are at least 44 px high** (`min-h-11`) for buttons, inputs, and links that stand alone.
12. **Mobile first, three breakpoints.** Write the mobile layout without prefix, then adapt with `sm:`, `md:`, `lg:` only. Content is centered in a container (`mx-auto max-w-5xl px-4`). Text lines stay under 75 characters (`max-w-prose`). Tables scroll horizontally on small screens.
13. **Respect reduced motion.** Animations and transitions use `motion-safe:`. Nothing essential depends on an animation.
14. **Words are part of the design.** Labels and headings in sentence case. Buttons say what they do ("Save changes", not "OK"). An error message says what went wrong and how to fix it ("Enter an email like name@example.com"). An empty state says what is missing and offers the action to add it.
15. **Grow the catalog, not the pages.** A new need becomes a new component or a new variant of an existing one, reviewed once and reused everywhere.

## Quick check

Before adding a page or a component, ask:

1. Does any class name a raw color, an arbitrary value, or a `dark:` variant?
2. Does the page style a control itself instead of using a catalog component?
3. Does every text and control pairing meet the contrast minimum in light and in dark?
4. Can every action be reached and done with the keyboard, with the focus always visible?
5. Does every field have a label, and every error a message tied to its field?
6. Is anything conveyed by color alone?
7. Does the page work on a phone-sized screen?
