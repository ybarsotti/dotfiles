# UX writing reference

The `ux-writer` agent reads this file. It writes and reviews the text that users read in a
product: labels, buttons, hints, empty states, toasts, errors, dialogs, emails.

Sources, rewritten for this harness: Anthropic `ux-copy` skill (Apache-2.0,
github.com/anthropics/knowledge-work-plugins), the `ux-writing` skill by content-designer (MIT,
github.com/content-designer/ux-writing-skill), Google Material writing guidance.

## 1. The rule that wins

`~/.claude/skills/_shared/ui-quality.md` section 6b wins over every pattern below. The text
says what is on the screen, what an action does for the user, or a fact they need. It never
explains how the system works, never describes the screen itself, and never repeats a label.
When a generic pattern says "explain why", show the fact or the next action instead.

## 2. Voice and tone

- **Voice** stays the same on every screen. Read the project's `docs/voice.md`. When it does
  not exist, derive the voice from the existing screens: 3 adjectives, and one "we say / we do
  not say" pair for each. Write that draft in your report, so the user can save it as
  `docs/voice.md`.
- **Tone** changes with the user's state:

| User state | Tone | Example |
|---|---|---|
| routine task | short, direct | "Saved" |
| first use | patient, one step at a time | "Add your first product" |
| error, blocked | calm, no blame, next step first | "Card declined. Try another card." |
| high stakes | serious, the consequence in plain words | "Delete account? This removes all your orders." |
| success | brief, in proportion to the action | "Order sent" |

## 3. Patterns

- **Button and link**: a verb and its object, 1 to 3 words. "Save changes", "Export CSV". Never
  "Submit", "OK", "Click here". The label matches the result.
- **Dialog**: the title is the question with the object: "Delete 3 files?". The body states
  the consequence when it is not obvious: "You can't undo this." The buttons name the actions:
  "Delete files" / "Keep files".
- **Error**: what happened, then what the user can do. "Couldn't save. Check your connection
  and try again." No error codes, no exception names, no blame, no system cause.
- **Empty state**: what the user can do here, with the action. "No orders yet." plus the
  button "Create order". Do not explain why it is empty.
- **Form field**: the label is a noun ("Email"). A hint appears only when the format is not
  obvious ("MM/YY"). A placeholder is never the label.
- **Toast and success**: the result, past tense, 1 to 4 words. "Invoice sent".
- **Tooltip**: only for an icon without a label, or a term the user does not know. Never for
  what the label already says.
- **Loading**: the action in progress: "Saving…". For a wait over a few seconds, what is
  happening for the user: "Uploading 3 of 10".
- **Numbers and dates**: the user's format. "2 hours ago", "Updated 10:42".

## 4. The four passes

Edit each text in this order. Stop at the first pass that cuts it.

1. **Purposeful**: does the user need this text to act or to decide? If not, cut it.
2. **Concise**: remove each word that does not change the meaning. Front-load the key word.
3. **Conversational**: the words of the user, not of the code. "Customer", not `account_owner`.
   Address the user as "you". Active voice. No exclamation marks.
4. **Clear**: one idea per text. A sentence holds 20 words or fewer. Same term for the same
   thing on every screen.

## 5. Checklist

- [ ] Each text passes the four passes.
- [ ] No text explains the system, describes the screen, or repeats a label.
- [ ] Each button names its action. Each dialog names its object and consequence.
- [ ] Each error gives the next step.
- [ ] The same thing has the same name on every screen.
- [ ] The text fits its element at 390 px. A label in German or Portuguese can be 30 % longer.
- [ ] No meaning depends on color, position or an icon alone. Link text makes sense out of
      context.
- [ ] The text follows the product's language and the i18n setup of the project.
