---
name: plan
description: Turn a spoken intention into weekly commitments and today's plan in the Obsidian journal, with the ETA normalised. Use when the user types /plan, or says what they intend to do ("essa semana vou fazer X até terça", "hoje vou mexer no Y", "planeja minha semana").
---

# Plan

Takes what the user says they intend to do and writes it into the journal in the
right place, with a consistent shape. The companion of `log`: **plan is what will
happen, log is what did.**

## Language and tone

**Entries are written in Portuguese.** Section names are fixed Portuguese strings.

**Write short and plain.** Simple words, no jargon, no long sentences. An entry
should read like something said out loud, not like a report. If a line runs past
two lines on screen, cut it.

**This does not change the language you speak in.** Keep replying in whatever
language the conversation is already using.

## Where things go

Two files, two different things. Getting this wrong recreates the duplication
this journal exists to remove.

| | Holds | Shape |
|---|---|---|
| **Week** `--week --section Compromissos` | The commitment. One line per thing promised this week. | `- [[TICKET]] descrição — ETA qua` — **no checkbox**, it is a reference. |
| **Day** `--section Plano` | What will actually be touched today. | `- [ ] descrição` — checkbox, because rollover looks for it. |

A commitment goes in the week **once**. It reappears in a day only on the days it
is actually worked on, and then as the concrete step — not as a copy of the
commitment line.

If the user's intention names only one thing and it starts today, writing it in
both is correct and not duplication: the week records the promise, the day
records the work. But never copy the ETA suffix into the day item; the ETA lives
on the commitment.

## ETA

Normalise to the three-letter lowercase weekday used everywhere else in the
vault: `seg ter qua qui sex`. Format is always ` — ETA xxx` at the end of the
commitment line.

- "até terça", "terça", "Ter", "tuesday" → `— ETA ter`
- "hoje" → today's weekday
- "fim da semana", "sexta" → `— ETA sex`
- No date given → no ETA suffix. Do not invent one.

## Project

Auto-detected from the working directory, with aliases applied. Pass
`--project` when the user names a project that is not the repo you are in —
which is common here, since planning often happens outside the target repo.

If the user's intention spans projects, split it: one call per project, so each
lands under its own `### projeto`.

## Commands

```bash
# commitment for the week
journal append --week --section Compromissos --project meu-projeto \
  --text "- [[PROJ-102]] prioridade do primeiro pedido — ETA ter"

# what will be touched today
journal append --section Plano --project meu-projeto \
  --text "- [ ] PROJ-102 abrir PR"

# not this week, but do not lose it
journal append --week --section Radar --project meu-projeto --text "- Refatorar pedido/orçamento"
```

`--week` targets the current week's note; without it the target is today's note.
Week sections are `Compromissos`, `Radar`, `Retro` — the day's sections are
rejected there, and vice versa.

## /plan

Read the user's intention and decide, per item, whether it is a commitment for
the week, work for today, or both.

Explicit markers win when present:

- "essa semana…", "até terça" → week
- "hoje…", "agora…" → day
- "não é pra agora", "no radar" → week, `Radar`

Without a marker: an item with an ETA on a future day is a commitment; an item
the user says they are starting is also a day item.

Then:

1. Write each item with one `journal append` call.
2. Reply with one line per item, saying where it landed.
3. Do not paste the files back.

Ask before writing only when the intention is genuinely ambiguous about *which
project* something belongs to. For an unclear ETA, write it without one rather
than guessing — an invented deadline is worse than none.

## When it is not work

Something with no project and no date — a link, a reminder, a question for
someone — is not a commitment and not a task. It goes to the inbox:

```bash
journal note "ver se dá pra automatizar o relatório"
```

`Radar` is for work that is real but not this week. The inbox is for everything
else. Do not turn a loose thought into a commitment to give it a home.

## Do not

- Do not tick anything. `/plan` writes open items only.
- Do not copy a commitment verbatim into the day with its ETA suffix.
- Do not create entity notes. That is `log`'s job, and only for tickets and
  projects.
- Do not touch `Retro`. That is written by the user on Friday.
