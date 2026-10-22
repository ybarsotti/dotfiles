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
  them.
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

## 7. Visual finish

- Icons come from the project's icon set. Use one size per context and one stroke style. Put
  an icon before its label and align it to the text's centre line. An icon-only control has an
  accessible name and a tooltip.
- Every interactive element has hover, active, focus-visible and disabled styles.
- Colour carries meaning through the project's semantic tokens: success, warning, danger,
  info. Colour never carries meaning alone. Add text, an icon or a shape.

## 8. Motion

- Use the project's animation utility or library. Do not add a new animation library for one
  effect.
- Transition between states with a short fade or slide, 150 ms to 250 ms.
- Give hover and press a small, fast response on interactive components.
- Count up a headline number when it first appears.
- Do not animate a frequent action, every list item, or content that the user is reading.
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

1. Run the app. Use the `agent-browser` skill, or `obscura` for a local URL.
2. Take a screenshot of each state from the plan, at desktop width and at 390 px.
3. Critique each screenshot as a designer, against sections 3 to 10 of this file. Write each
   weak point down.
4. Fix each weak point.
5. Take the screenshots again, and repeat until no weak point is left.
6. Keep the final screenshots. The review and the PR use them as evidence.

When no local environment can run, render the component with fixture data, and say so in the
evidence.
