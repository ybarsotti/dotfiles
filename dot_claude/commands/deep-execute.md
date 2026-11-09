---
description: Executes approved deep-plan lanes in parallel Orca terminals, gates and report-only reviews each round, then runs the shared after-approval chain (review, QA, PR, report, PR watch) with every fix routed through the owning lane
---

# /deep-execute

Build an already-approved plan (`Mode: parallel`, disjoint lanes, one API contract — exactly
what `/deep-plan` produces) with parallel lane workers sharing ONE git worktree. The
orchestrator commits, gates rounds, and mediates contract drift; workers never touch `git`.

**Arguments:** `$ARGUMENTS`

## Argument grammar

```
/deep-execute <absolute-plan-path> [flags]
/deep-execute --resume RUN_DIR

FLAGS
  --resume RUN_DIR       resume an existing run; the plan path comes from its manifest.json
  --max-rounds N         override the round cap (default 3)
  --agent LANE=AGENT     replace the plan's agent of one lane (a line of agents.allowlist)
  --dry-run              print the lanes, agents, contract and review count, then stop
```

A new run writes to `~/.claude/deep-execute-runs/run-YYYYmmdd-HHMMSS`.

## What you must do

You are the **orchestrator**. Invoke the `deep-execute` skill — do NOT scaffold the run
directory, launch workers, or parse events by hand. The skill lives at
`~/.claude/skills/deep-execute/SKILL.md`. Follow its protocol exactly: preflight the plan and
the worktree, commit the contract and shared files before fanout, scaffold and launch the
lanes in Orca terminals, hold the `Monitor` on the run's event stream, and gate every round
before advancing.

**You orchestrate; you never write lane code.** The run does not pause to check in: it goes
end to end and stops only on a blocker no agent can settle alone.

Once the lanes are done, the skill runs steps 2 to 9 of
`~/.claude/skills/_shared/after-approval.md`: the full `/deep-review`, the `qa-ui` and
`qa-business` agents, frozen SHA, the PR, the run report built from the run directory, and the
PR watch. Every fix goes back to the lane that owns the code.

### Quick examples

```bash
/deep-execute /Users/me/project/docs/superpowers/plans/2026-07-18-totals/plan.md
/deep-execute /Users/me/project/docs/superpowers/plans/2026-07-18-totals/plan.md --dry-run
/deep-execute /Users/me/project/docs/superpowers/plans/2026-07-18-totals/plan.md --max-rounds 5
/deep-execute --resume ~/.claude/deep-execute-runs/run-20260718-140000
```
