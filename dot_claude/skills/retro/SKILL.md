---
name: retro
description: Close the week in the Obsidian journal — read the week's day notes, compare them with the commitments, and draft the Retro section. With `/retro slack`, produce the emoji-tagged message to paste into the team channel. Use when the user types /retro, says "close the week", "weekly retro", "retro for Slack", or asks what happened this week.
---

# Retro

Closes the week. Reads what was committed and what actually happened, then drafts
`## Retro` in the weekly note for the user to edit.

This is the section nobody fills in by hand, because it means re-reading the
whole week. That is the work this skill does.

## Language and tone

**Entries are written in English.** Section names are canonical journal keys.

**Write short and plain.** Simple words, no jargon, no long sentences. A retro
line should read like something said out loud, not like a report. If a line runs
past two lines on screen, cut it.

**This does not change the language you speak in.** Keep replying in whatever
language the conversation is already using.

## Gather

Never build a file path. Use the commands:

```bash
journal week      # path of this week's note
journal days      # the week's day notes, in order
journal pending   # what is still open, and for how long
```

Read the week note for `## Compromissos`, then read each day note for what was
ticked (`- [x]`), what stayed open (`- [ ]`), and what landed under `Decisões`,
`Tickets` and `Threads`.

## Draft

Write into `## Retro` with `journal append --week --section Retro`. Four groups,
each one only if it has content:

```markdown
### Delivered
- [[PROJ-102]] — ETA ter, completed on ter

### Slipped
- Price sync — ETA qua, open since seg (4 days)

### Weekly decisions
- The script creates the daily note, not the plugin

### Carry over
- Price sync
```

Rules:

- **Delivered**: commitment done. Say the ETA and when it actually closed.
- **Slipped**: commitment not done. Say the ETA and how long it has been open.
  State the fact, do not explain it away.
- **Weekly decisions**: one line each, pulled from the day notes. Link, do not
  repeat.
- **Carry over**: what is worth carrying into next week.

Group by project, same as everywhere else — pass `--project`.

If the inbox has anything in it (`journal inbox`), mention how many items are
sitting there. Do not triage them — that is the user's call — just say they are
waiting, so the week does not close on top of them.

## Do not

- Do not judge or coach. No "could have been better", no advice. Say what
  happened.
- Do not invent a reason for a slip. If the day notes do not say why, leave it.
- Do not copy day entries whole. One line, with a link.
- Do not tick anything, and do not touch other sections.

## After writing

Say in one line where it landed and what the week looked like — how many
commitments closed, how many slipped. Do not paste the file back.

If the week has no day notes yet, say so and write nothing.

## /retro slack

With the argument `slack`, produce the message the user posts to the team at the
end of the week. **Print it in a fenced code block and write nothing to the
vault** — this one is for copying out.

If `## Retro` is already written in the week note, build from it: the user may
have edited it, and the edited version is the truth. Otherwise gather as above.

### Shape

Plain text, no Markdown bullets — Slack renders `-` as literal characters. Emoji
codes, not Unicode. Blank line between blocks.

```
[Retro]

:white_check_mark: PROJ-101 – shipment report type and site filters
:white_check_mark: Alert panel
Email cards
Invoice cards

:warning: PROJ-102 – first order priority
Tests became too complex and are being simplified

:bulb: Price sync – solution decided, implementation pending

[Extra]

Added email validation to account creation
:exclamation: Box calculation – scope changed, decision required

[Carry over]

Price sync – implement the chosen option
PROJ-102 – first order priority

[Aprendizados]

An out-of-pattern item also forces out-of-pattern packaging when its longest side exceeds the largest box side. Always test with a LARGE item.
```

### Blocks

| Block | Holds |
|---|---|
| `[Retro]` | What was delivered. One line per commitment. |
| `[Extra]` | Done but never planned. |
| `[Carry over]` | Goes to next week. No icon — the block already says it. |
| `[Aprendizados]` | Worth the team knowing. Skip the block when there is nothing real. |

Keep an empty block rather than dropping it, except `[Aprendizados]` — an empty
learnings block reads better than an invented lesson.

### Icons

| Icon | Use for |
|---|---|
| `:white_check_mark:` | Done |
| `:warning:` | Not finished, or only partly done |
| `:exclamation:` | Needs attention — not necessarily a problem |
| `:bulb:` | Something found out |

`:warning:` is about state, not blame: the task did not close, or closed halfway.
It says nothing about why. `:exclamation:` flags what the team should look at,
which is often good news — a change in scope, something that needs a decision.

A topical emoji is fine when it helps scanning — `:email:` on a week of email
work. Do not decorate every line.

### Lines

- Ticket code, then ` – `, then a short description. Ticket code alone is fine.
- Sub-items go on plain lines underneath, no icon and no indent.
- One line each. If it needs two, the second is context, not a rewording.
- No `[[wikilinks]]` — they mean nothing in Slack. Ticket codes stay bare.
- Do not group by project unless the team's channel spans several.

Write it as the user would say it in standup: short, plain, no polish. Say what
happened, including what broke. This message goes to people, so a slip stated
plainly is worth more than a slip dressed up.
