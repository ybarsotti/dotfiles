---
description: Executes approved deep-plan lanes, runs /deep-review 3:3 plus fixes, QA-tests with a browser agent, fixes the gaps with a different agent, freezes SHA, opens the PR with evidence, then builds the run's HTML decision report
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

Phase 1 opens a Hunk diff pane in Wave beside the run, pointed at the shared worktree and diffed
against the baseline commit. Every round gate refreshes it and writes that round's decisions onto
the lines that produced them, so the user reads the change as it lands. Use `/hunk-watch` to open
the same pane on any other worktree.

Once the lanes are done, the tail runs back to back:

1. `/deep-review default --reviewers 6 --ratio 3:3`, fixes routed back to the owning lane.
2. Record what was built and what the review changed, through `decision.sh`.
3. A **QA agent** drives `agent-browser` against the live env, capturing screenshots and
   recordings — `/qa-testing` (EXECUTE) when that skill is on the machine, `/qa-execute` when
   the plan carries a `qa-plan.yaml`, a plain browser agent otherwise.
4. A **different** agent fixes every gap QA found; QA re-verifies. The tester never fixes.
5. Freeze the commit SHA.
6. `/pr-description` opens the PR with the evidence attached.
7. Build the run report — a self-contained HTML page covering what was built, every decision and
   assumption the lanes recorded (alternatives rejected, tradeoffs accepted), drift from the
   approved plan, tests, the review and QA evidence, and the PR. Assembled from the run directory
   by script; never written or extended from your own memory of the run.

Documentation the change makes stale is part of done, and lanes use Serena / GitNexus / Graphify
rather than raw `grep`.

### Quick examples

```bash
/deep-execute /Users/me/project/.deep-plan-runs/2026-07-18/plan.md
/deep-execute /Users/me/project/plan.md --max-rounds 5
/deep-execute --resume ~/.claude/deep-execute-runs/run-20260718-140000
```
