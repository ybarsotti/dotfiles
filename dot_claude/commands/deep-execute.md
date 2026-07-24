---
description: Executes approved deep-plan lanes, reviews/fixes final diff, freezes SHA, then runs approved QA plan with HTML evidence
---

# /deep-execute

Build an already-approved plan (`Mode: parallel`, disjoint lanes, one API contract — exactly
what `/deep-plan` produces) with parallel lane workers sharing ONE git worktree. The
orchestrator commits, gates rounds, and mediates contract drift; workers never touch `git`.

**Arguments:** `$ARGUMENTS`

## Argument grammar

```
/deep-execute <absolute-plan-path> [flags]

FLAGS
  --resume RUN_DIR       resume an existing run instead of starting a new one
  --max-rounds N         override the round cap (default 3)
```

## What you must do

You are the **orchestrator**. Invoke the `deep-execute` skill — do NOT scaffold the run
directory, launch workers, or parse events by hand. The skill lives at
`~/.claude/skills/deep-execute/SKILL.md`. Follow its protocol exactly: preflight the plan and
the worktree, confirm each lane's agent via `AskUserQuestion` against `agents.allowlist`,
commit the contract and shared files before fanout, scaffold and launch the lanes, hold the
`Monitor` on the run's event stream, and gate every round before advancing.
After final `/deep-review` and verification, freeze commit SHA. If plan references a QA artifact,
run `/qa-execute` against environment serving that SHA before reporting completion.

### Quick examples

```bash
/deep-execute /Users/me/project/.deep-plan-runs/2026-07-18/plan.md
/deep-execute /Users/me/project/plan.md --max-rounds 5
/deep-execute --resume ~/.claude/deep-execute-runs/run-20260718-140000
```
