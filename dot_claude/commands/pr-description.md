---
description: Generate + review a conventional-commit PR title and body (objective, Mermaid flow, rationale, ticket — no file list), then open or update the PR assigned to you
---

# /pr-description

Write a crisp, reviewer-friendly pull-request title and description, have a second
model review it, then open (or update) the PR assigned to you.

- **Title** is a Conventional Commit (`feat`/`fix`/`refactor`/`perf`/`docs`/`test`/`chore` + optional scope), ≤ 70 chars.
- **Body** states what the change solves, a **Mermaid** flow diagram, the rationale, the key decisions, and the linked ticket.
- **Body never** lists changed files or file/line counts — it is about *what we solve*, not *what moved*.
- A **claude Sonnet** agent writes it; a **codex** agent reviews it. The PR is assigned to you (`@me`).

**Arguments:** `$ARGUMENTS`

## Argument grammar

```
/pr-description [flags]

FLAGS
  --plan <path>       deep-plan plan.md to source Context / Flow diagram / Rationale / ticket from
  --ticket KEY-123    explicit ticket key (else auto-detected from branch/commit)
  --update <pr-number> update an existing PR instead of creating one
  --draft             open the PR as a draft
  --no-codex          skip the codex reviewer (Sonnet self-review only)
  --dry-run           print the drafted title + body, do not open/update the PR
```

## What you must do

You are the **orchestrator**. Invoke the `pr-description` skill — do NOT write the PR
title/body inline yourself. The writer (Sonnet) drafts it, the reviewer (codex) checks
it, you apply fixes and open the PR.

The skill lives at `~/.claude/skills/pr-description/SKILL.md`. Follow its phases exactly.

### Quick examples

```bash
/pr-description
/pr-description --plan ~/.claude/deep-plan-runs/20260713-101500-a3f9c2/plan.md --ticket FBIT-2982
/pr-description --update 1421 --draft
```
