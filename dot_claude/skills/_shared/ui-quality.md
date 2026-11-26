# UI quality bar

This file is the single UI quality bar for every skill and every session. A plan reads it to
fill the `UI design pass`. An implementer reads it before the first line of UI code and
again for the visual pass. A reviewer reads it to judge the result. Do not copy these rules
into another file. Point at this file instead.

The user has no designer. The agent is the designer. A screen that works but looks raw is not
done, and the user must never need to ask for the polish.

## 1. Design for the task

- Name who uses the screen and the task they do on it. Example: "Finance opens it, checks the
  totals, and emails them to the client." Design for that task, not for the list of fields.
- Find the shortcut the real task needs. Example: "copy everything, formatted for an email".
- Pick one screen of this project as the visual reference, and follow it.

## 2. Reuse before you build

Use the first rung that exists:

1. A component, a token, or a pattern that this project already has. Look in the component
   directory and the theme file first.
2. A component of the UI library that this project already installs.
3. Only then, a new component. Put it in the shared component directory when another screen
   can use it.

This applies to loading indicators, toasts, dialogs, empty states, icons and animation
utilities too.

## 3. Hierarchy and structure

- Every screen has one clear title and one clear primary purpose.
- Group the data that belongs together. Show shared data once, not on every row.
- Use the project's type scale, spacing scale and colour tokens. Never hardcode them.
- Align to one grid. Keep the same spacing between siblings.
- A label, a value and a unit read as one unit. A wall of `key: value` lines is a defect.
- Cut components along clear lines. One component per file. Data fetching and business rules
  stay out of presentational components.

## 4. Every state, designed

The plan lists every state of the screen. The implementation builds each one.

| State | Rule |
|---|---|
| Loading | Use the project's loading component. Otherwise choose by purpose: a skeleton in the shape of the final content for a list or a page, a spinner inside the control for a short action, a progress bar or steps for a long operation. Never show only the text "Loading". |
| Empty | Say why it is empty and give the next step as an action. |
| Error | Show a readable message, never raw JSON or only a status code. Put a field error next to its field. Put a page error in the content area with a retry action. Keep everything the user typed. |
| Blocked | List what the user must fix, each item with a link or an action that fixes it. |
| Pending action | Disable the control and show progress in it. A long action shows that it is still moving. |
| Success | Show a visible outcome: an updated view, an optimistic update, or a toast when the result is off screen. |
| Permission | Hide or disable what the user cannot do, and say why when they expect it. |

## 5. Feedback on every interaction

- Every click, submit and toggle produces a visible response within 100 ms.
- Everything clickable shows that it is clickable: `cursor: pointer` and a hover style on
  buttons, links, clickable rows and clickable cards. A non-clickable element never gets
  them. Tailwind v4 resets `button` to `cursor: default`, so a project on it needs one base
  rule: `button:not(:disabled), [role="button"]:not(:disabled) { cursor: pointer; }`.
  `scripts/interaction-audit.js` checks this on the running page (section 11).
- An icon-only action shows a tooltip on hover and on keyboard focus that says what it does.
- A toast reports the result of an action whose effect is not visible on the screen. Do not
  use a toast for an error that belongs to a field.
- A destructive action asks for confirmation that names the object, and offers undo when it
  can.
- A form never clears on an error. Navigation away from unsaved input warns the user.

## 6. Content that does not break the layout

- Format numbers, currency, percentages and dates with the user's locale, through `Intl` or
  the project's formatter.
- Truncate a long single-line value with an ellipsis and show the full value in a tooltip.
  Clamp a long text block and give a "show more" control.
- Test each screen with one item, many items, a very long name, and a number wider than its
  column.

## 6b. Copy says what the user sees and gets

This applies to every text a user reads: labels, buttons, hints, empty states, toasts, errors,
emails, notifications, exports and any page made for users.

- Say what is on the screen, what an action does for the user, or the information they need.
  Nothing else.
- Never explain how the system works underneath. No jobs, schedules, crons, queues,
  webhooks, syncs, retries, caches, tables, APIs, models, flags, internal ids or status codes.
  - Wrong: "A background job runs every hour to sync your invoices from Stripe."
  - Right: "Invoices update automatically." Or show the fact: "Updated 10:42".
- Use the words of the user, not the words of the code. "Customer", not `account_owner`.
- An error says what happened and what the user can do next. Never a code, an exception name
  or a stack trace.
- Do not explain a rule the user cannot act on. Show its result instead.
- The `ux-writer` agent writes and reviews this text, with the patterns of
  `~/.claude/skills/_shared/ux-writing.md`.
- Keep it short and plain. One idea per sentence.

## 7. Visual finish

- Icons come from the project's icon set. Use one size per context and one stroke style. Put
  an icon before its label and align it to the text's centre line. An icon-only control has an
  accessible name and a tooltip.
- Every interactive element has hover, active, focus-visible and disabled styles.
- Colour carries meaning through the project's semantic tokens: success, warning, danger,
  info. Colour never carries meaning alone. Add text, an icon or a shape.
- Style the browser surfaces with the project's tokens: text selection, caret, scrollbar and
  focus ring. A dark theme sets `color-scheme: dark`.
- A destructive action that can be reversed offers an undo window instead of a confirm dialog.

## 8. Motion

- When a design exists, its motion spec is the contract: build every hover, focus, active
  and open state, transition, entrance and loop it lists, with its exact easing and duration.
  The defaults below apply only where the design says nothing.
- Use the project's animation utility or library. Do not add a new animation library for one
  effect.
- Transition between states with a short fade or slide. Durations: press 100 to 160 ms,
  tooltip and small popover 125 to 200 ms, dropdown 150 to 250 ms, modal and drawer 200 to
  500 ms. Other UI motion stays under 300 ms.
- Easing: enter and exit use a strong ease-out, `cubic-bezier(0.23, 1, 0.32, 1)`. Movement on
  the screen uses `cubic-bezier(0.77, 0, 0.175, 1)`. Never use `ease-in` on UI.
- Animate only `transform` and `opacity`. Never write `transition: all`. A new input
  interrupts a running animation.
- A pressable element scales to 0.97 on `:active`. A new element enters from `scale(0.95)`
  with opacity 0, never from `scale(0)`. A popover grows from its trigger
  (`transform-origin`). A modal stays centered.
- Stagger a group entrance by 30 to 80 ms per item, under about 300 ms in total. The main item
  moves most, support items move less, decoration only fades. One entrance per container.
- Give hover and press a small, fast response on interactive components.
- Give components personality. Use the accent color, a micro-interaction on the main action,
  and the motion style of the closest existing screen. Plain gray boxes with no feedback are
  not done.
- Count up a headline number when it first appears.
- Do not animate a frequent action, every list item, or content that the user is reading.
  Never animate a keyboard shortcut or a command palette toggle.
- Respect `prefers-reduced-motion`: replace movement with an instant change or a fade.

## 9. Layout, mobile and actions

- Use wide screens: put comparable items side by side.
- Stack the layout on mobile. Check 390 px wide at minimum. The page body never scrolls
  horizontally. A wide table scrolls inside its own container or turns into cards.
- Touch targets are 44 by 44 px at minimum. Nothing is reachable only by hover.
- Put the primary action on the right of the footer, secondary actions beside it, and utility
  actions (copy, export) on the left. Show one primary action per state.
- On mobile, keep the primary action reachable without a long scroll, for example in a sticky
  footer.

## 10. Accessibility

- Use native elements: `button` for an action, `a` for navigation, a `label` tied to each
  input. A `div` with a click handler is a defect.
- Every interactive element is reachable by Tab in visual order and works with Enter and
  Space.
- A dialog or drawer moves focus inside when it opens, traps it, and returns it to the trigger
  when it closes.
- Announce errors and toasts through a live region. Tie a field error to its input with
  `aria-describedby` and `aria-invalid`.
- Text contrast is 4.5:1 at minimum, 3:1 for large text and for control borders. Check the
  disabled and placeholder text too.
- Meaningful images have alt text. Decorative images have empty alt text.

## 11. The visual pass, before you hand off

Do this after the UI builds and before review. A screen nobody looked at is not done.

1. Run the app. Use the `agent-browser:agent-browser` skill, or `obscura` for a local URL.
2. Take a screenshot of each state from the plan, at desktop width and at 390 px.
3. Critique each screenshot as a designer, against sections 3 to 10 of this file. Write each
   weak point down.
4. Fix each weak point.
5. Take the screenshots again, and repeat until no weak point is left.
6. On each screen, run the interaction audit in the page and fix each failure it lists:
   `agent-browser eval "$(cat ~/.claude/skills/_shared/scripts/interaction-audit.js)"`.
   It lists each visible clickable element without `cursor: pointer` or without a `:hover`
   rule. Done when `failures` is empty. Save the output next to the screenshots.
7. Fill each screen with worst-case data and screenshot it again: a long name, an email
   without a break point, counts of 0, 1 and 1,284, empty optional fields, a long translated
   label. The layout holds, the text truncates or wraps, and plurals read right.
8. Run an accessibility scan on each screen with axe-core, for example
   `agent-browser eval` with `axe.run()`, or `@axe-core/playwright` when the project has it.
   Fix each `serious` and `critical` violation.
9. Run the code checklist of `~/.claude/skills/_shared/ui-code-checklist.md` on each changed UI
   file. Fix each hit.
10. Keep the final screenshots. The review and the PR use them as evidence.

This pass is the check of the builder. It does not prove that the screen matches a design
canvas. When a canvas exists, the `qa-ui` agent makes that comparison, and `/ship-it` requires it.

When no local environment can run, render the component with fixture data, and say so in the
evidence.
