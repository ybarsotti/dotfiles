---
description: Executes approved deep-plan lanes, runs /deep-review 3:3 plus fixes, QA-tests with the qa-ui and qa-business agents, fixes the gaps with a different agent, freezes SHA, opens the PR with evidence, then builds the run's HTML decision report
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

**You orchestrate; you never write lane code.** And the run does not pause to check in — Phase 0
opens `/goal` on the finished state, so it goes end to end and stops only on a blocker no agent
can settle alone.

Every task uses one Wave tab. Lane blocks have names and form one vertical column. The task's llmessage chat opens
beside them. The orchestrator header shows current
phase, task completion, percentage, and elapsed time; tab badge shows running, blocked, or complete.

Once the lanes are done, the skill's Phase 4 and Phase 5 run the tail back to back: the full
`/deep-review`, then steps 3 to 8 of `~/.claude/skills/_shared/after-approval.md` (the `qa-ui`
and `qa-business` agents, gap fixes by a different agent, frozen SHA, `/pr`), then the run
report, which a script builds from the run directory.

Documentation the change makes stale is part of done, and lanes use Serena / GitNexus / Graphify
rather than raw `grep`.

### Quick examples

```bash
/deep-execute /Users/me/project/.deep-plan-runs/2026-07-18/plan.md
/deep-execute /Users/me/project/plan.md --max-rounds 5
/deep-execute --resume ~/.claude/deep-execute-runs/run-20260718-140000
```
