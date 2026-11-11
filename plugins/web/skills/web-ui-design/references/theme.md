# Default theme

A neutral theme to start a project with: zinc neutrals, one indigo accent, and status colors. It is readable, meets WCAG 2.2 AA in light and in dark, and is easy to brand later: change the token values here, and nothing else.

## app.css

The Tailwind CSS v4 entry point. `@source` points at the folders holding the files that use classes (templates, components, Go files with class maps): adjust it to the project.

```css
@import "tailwindcss";

@source "../../internal/delivery/web/views";

@theme {
  /* Only the theme's colors exist: bg-blue-600 or text-white generate nothing. */
  --color-*: initial;

  --color-surface: #ffffff;
  --color-surface-muted: #f4f4f5;
  --color-content: #18181b;
  --color-content-muted: #52525b;
  --color-line: #e4e4e7;
  --color-line-strong: #71717a;

  --color-primary: #4f46e5;
  --color-primary-hover: #4338ca;
  --color-on-primary: #ffffff;

  --color-danger: #b91c1c;
  --color-on-danger: #ffffff;
  --color-danger-subtle: #fef2f2;

  --color-success: #15803d;
  --color-success-subtle: #f0fdf4;

  --color-warning: #a16207;
  --color-warning-subtle: #fefce8;

  --color-focus: #4f46e5;
}

@layer base {
  /* Dark mode: the same tokens, other values. No dark: class anywhere else. */
  @media (prefers-color-scheme: dark) {
    :root {
      --color-surface: #18181b;
      --color-surface-muted: #27272a;
      --color-content: #fafafa;
      --color-content-muted: #a1a1aa;
      --color-line: #3f3f46;
      --color-line-strong: #71717a;

      --color-primary: #818cf8;
      --color-primary-hover: #a5b4fc;
      --color-on-primary: #18181b;

      --color-danger: #f87171;
      --color-on-danger: #18181b;
      --color-danger-subtle: #2a1215;

      --color-success: #4ade80;
      --color-success-subtle: #0f2417;

      --color-warning: #facc15;
      --color-warning-subtle: #2a2410;

      --color-focus: #818cf8;
    }
  }

  html {
    color-scheme: light dark;
  }

  body {
    @apply bg-surface text-content antialiased;
  }
}
```

Fonts, spacing, radius, and shadows keep Tailwind's defaults: the system font stack and the 0.25rem spacing scale. Design rule 5 of the skill restricts which steps are used.

## Contrast

Every pairing the components use, measured with the WCAG 2.2 formula. Text needs 4.5:1, control borders and focus rings 3:1. When a token changes, measure its pairings again.

| Pairing | Use | Light | Dark |
|---|---|---|---|
| `content` on `surface` | body text | 17.72 | 16.97 |
| `content` on `surface-muted` | text on a muted area | 16.12 | 14.27 |
| `content-muted` on `surface` | secondary text, help text | 7.73 | 6.91 |
| `content-muted` on `surface-muted` | secondary text on a muted area | 7.03 | 5.81 |
| `on-primary` on `primary` | primary button | 6.29 | 5.94 |
| `on-primary` on `primary-hover` | primary button, hovered | 7.90 | 8.89 |
| `primary` on `surface` | link | 6.29 | 5.94 |
| `on-danger` on `danger` | danger button | 6.47 | 6.40 |
| `danger` on `surface` | field error message | 6.47 | 6.40 |
| `danger` on `danger-subtle` | danger alert | 5.91 | 6.35 |
| `success` on `success-subtle` | success alert | 4.79 | 9.38 |
| `warning` on `warning-subtle` | warning alert | 4.76 | 10.10 |
| `line-strong` on `surface` | input border (3:1) | 4.83 | 3.67 |
| `focus` on `surface` | focus ring (3:1) | 6.29 | 5.94 |

`line` (`#e4e4e7`) is under 3:1 on purpose: it is for decorative separators (card borders, table rows), never for the border that shows where a control is.

## Branding the theme

To give the product its own look, change the values of the existing tokens, then check the contrast table again:

- **The accent**: `primary`, `primary-hover`, `focus`, and `on-primary` if the new accent is light.
- **The neutrals**: `surface*`, `content*`, `line*`, for a warmer or cooler gray.
- **The font**: add `--font-sans: "Inter", ui-sans-serif, system-ui, sans-serif;` to `@theme`, and serve the font file with the other static assets.

Never add a token for one page. A new token is a new role, used by a component.
