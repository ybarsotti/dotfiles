# UI code checklist

A static check of UI code. Read each changed UI file, and report each hit as `file:line - <problem>`.
The `implementer-frontend` agent runs it before it hands off. The `qa-ui` agent runs it on the
diff. `ui-quality.md` covers what the screen looks like; this file covers what the code does.

Sources, rewritten and shortened: Vercel Web Interface Guidelines (MIT,
github.com/vercel-labs/web-interface-guidelines), Emil Kowalski design engineering skills (MIT,
github.com/emilkowalski/skills), impeccable `craft-floor` (Apache-2.0, github.com/pbakaus/impeccable).

## Flag on sight

- `transition: all`. List the properties.
- `ease-in` on an enter or a hover. Use the ease-out token of section 8 of `ui-quality.md`.
- An entrance from `scale(0)`. Start from `scale(0.95)` with opacity 0.
- `outline: none` or `outline-none` without a `:focus-visible` style.
- A `div` or `span` with a click handler. Use `button`, or `a` for navigation.
- An icon-only button without `aria-label`. An input without a label.
- `user-scalable=no` or `maximum-scale=1`.
- `onPaste` with `preventDefault`.
- A hard-coded date, number or currency format. Use `Intl.DateTimeFormat`, `Intl.NumberFormat`,
  and `Intl.PluralRules` for counts ("1 member", "2 members").
- An `img` without `width` and `height`.
- A `.map()` over a list that can hold more than about 50 items, without virtualization or
  `content-visibility: auto`.
- An animation on a keyboard shortcut or a command palette toggle.

## Motion

- Animate only `transform` and `opacity`.
- A popover or a menu sets `transform-origin` at its trigger. A modal stays centered.
- An animation can be interrupted: a new input reverses or retargets it.
- Each loop or decorative animation stops under `prefers-reduced-motion`.

## Forms

- Inputs use the right `type` and `inputmode`. Emails and codes have `spellCheck={false}`.
- The submit button stays enabled until the request starts, then shows a spinner.
- On submit, focus the first field with an error. The error sits next to its field.
- A form with unsaved changes warns before navigation.

## Content and layout

- A flex child that holds text has `min-width: 0`, and the text truncates, clamps or wraps.
- Numbers that change or sit in a column use `font-variant-numeric: tabular-nums`.
- Headings use `text-wrap: balance`. Use `…`, not `...`.
- Filters, tabs, pagination and open panels live in the URL.

## Browser surfaces

- Style text selection (`::selection`), the caret (`caret-color`), the scrollbar and the focus
  ring with the project's tokens.
- A dark theme sets `color-scheme: dark`, and a native `select` sets its colors.
- Modals, drawers and sheets set `overscroll-behavior: contain`.
- Touch targets set `touch-action: manipulation`. A full-bleed layout uses
  `env(safe-area-inset-*)`.
- A destructive action offers an undo window when it can be reversed. Else it asks for
  confirmation. It never runs at once without one of the two.
