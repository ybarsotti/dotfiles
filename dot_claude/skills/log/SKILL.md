---
name: log
description: Record decisions, Slack threads, tickets and learnings in the Obsidian journal. Use when the user types /log, asks to "registrar", "anotar no diário", "log this", "save this decision", when the journal-nudge hook fires, or after work whose motivation would not be obvious from the code alone.
---

# Journal

A work journal in the user's Obsidian vault. It holds **what the code does not**:
why a decision was made, which thread prompted a change, what a ticket actually
covered, what was learned.

Works identically in Claude Code and Codex — every write goes through one script.

## Language and tone

**Entries are written in Portuguese.** Section names are fixed Portuguese strings
and are never translated.

**Write short and plain.** Simple words, no jargon, no long sentences. An entry
should read like something said out loud, not like a report. If a line runs past
two lines on screen, cut it.

**This does not change the language you speak in.** Keep replying in whatever
language the conversation is already using.

## Core rule

**Never build a file path.** Use `journal` and nothing else:

```bash
journal append --section Decisões --text "..."              # project auto-detected
journal append --section Notas --project foo --text "..."   # override project
journal entity --type ticket --name PROJ-201               # atomic note, prints path
journal today                                               # path of today's note
```

If `journal` is not on PATH, say so. Do not write Markdown somewhere else.

## Project is mandatory

Every section is split into `### projeto` subsections. The user works across
several projects at once — an entry that does not say which one is useless.

The project is auto-detected from the working directory (git repo root, else the
folder name). Override with `--project` **when the entry is not about the repo
you are standing in**: a Slack thread about another team's service, a ticket you
only reviewed, something raised in a meeting.

## Keep entries short

**Two lines.** A summary line, then the reason. Links inline. If it needs more
than that, it wants its own note, not a longer bullet.

```bash
journal append --section Decisões --text "- **Sincronização de preço → opção 5** — usa o mesmo payload do catálogo
  As outras divergiam o preço entre catálogo e pedido. [[PROJ-101]] · [thread](https://...)"
```

No paragraph of background. In three months the user needs the decision and the
reason, not the retelling.

## What goes in each section

| Section | Put here | Do NOT put here |
|---|---|---|
| `Plano` | A task left open that carries into tomorrow. Checkbox `- [ ]`, because rollover looks for it. | Finished tasks. |
| `Decisões` | A choice between real alternatives, plus the reason. | Something you did that had no alternative. |
| `Threads` | A Slack conversation that started or changed work. **Always with the link.** | A conversation with no consequence. |
| `Tickets` | What actually happened to a ticket — landed, blocked, reopened, scope changed. | "Worked on PROJ-123." |
| `Estudos` | Something learned that applies beyond today's task, with the practical conclusion. | A bug hit while implementing. That is not a study. |
| `Notas` | A fact about the system that will be needed again — a landmine found, an external constraint. | Implementation detail of the work in progress. That is what the commit is for. |

`Estudos` and `Notas` are the ones most often got wrong. Test: **would this
matter if the current task had never existed?** If not, it belongs in the commit
message, not the journal.

## Do not record

- What git already tells: changed files, diffs, branch names.
- A recap of the conversation.
- A finished task with no consequence.
- Anything already recorded this session.
- **Never a secret** — API key, token, password. Name the service, never the value.

## Entities

Create atomic notes only for things that **exist outside the journal and come
back**:

```bash
journal entity --type ticket  --name PROJ-201   # → Journal/entities/
journal entity --type project --name dotfiles    # → Journal/projects/
```

For anything else — a decision, a topic — write `[[Nome]]` in the entry and
create nothing. Obsidian renders an unresolved link, which is a fine way to say
"this exists but has no note yet". A stub with an empty body is worse than no
file: it clutters the vault and the graph.

Run `entity --type decision` or `--type study` only when the user explicitly asks
for a note on that subject.

## When the hook fires

`journal-nudge` reminds after 90 minutes without a record. It does not know what
happened — you do.

Ask: **would this be expensive to reconstruct later?** If yes, record it. If no,
carry on without mentioning the reminder. Ignoring it is usually correct;
recording something trivial to satisfy it degrades the journal.

## /log

In Claude Code the trigger is `/log`. Codex has no slash commands — invoke the
skill directly, same behaviour.

1. Re-read the conversation since the last record.
2. Keep only what passes the criteria above. Usually two or three items.
3. Append, one call per entry.
4. Reply with one line per record — do not paste the file back.

With an argument (`/log decidi a opção 5 na sincronização de preço porque X`), record **that**
and do not comb the conversation.

If nothing passes, say so. That is a valid outcome.
