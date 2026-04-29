---
description: Multi-agent peer review — runs N reviewer personas in parallel (Claude + Codex headless) and produces a consolidated report
---

# /review-panel

Run a configurable panel of reviewer agents in parallel against the current branch (or a target file/PR), then aggregate their findings into a single consolidated report.

**Arguments:** `$ARGUMENTS`

## Argument grammar

```
/review-panel [variant] [flags]

VARIANT (positional, optional, default: "default")
  default             multi-perspective (10 distinct personas)
  security-focused    every persona reviews through an OWASP/security lens
  adversarial-debate  approver-vs-rejecter pairs across 5 dimensions

FLAGS
  --reviewers N       total reviewers (default: 20 — cycles each persona through Claude AND Codex for cross-model coverage)
  --ratio C:X         Claude:Codex split (default: 10:10)
  --scope <ref>       git range (default: main...HEAD), or "PR-1234", or "file:path"
  --task <id>         force a Jira/Linear task ID (default: auto-detect from branch/commit)
  --timeout <secs>    per-reviewer timeout (default: 600)
  --keep-artifacts    don't delete the run dir after completion
  --dry-run           print the plan without spawning reviewers
```

## What you must do

You are the **orchestrator**. Invoke the `review-panel` skill — do NOT try to run reviewers manually inline. The skill defines the full protocol (validate args → collect context → fan out reviewers → aggregate). Follow it exactly.

The skill lives at `~/.claude/skills/review-panel/SKILL.md` and its scripts at `~/.claude/skills/review-panel/scripts/`.

### High-level flow

1. Parse `$ARGUMENTS` into variant + flags
2. Run `~/.claude/skills/review-panel/scripts/dispatch.sh "$VARIANT" --reviewers <N> --ratio <C:X> --scope <ref> [--dry-run]`
3. The dispatcher handles everything: builds the run dir, fans out reviewers in background, waits, and aggregates
4. Report is printed to stdout AND saved to `~/.claude/review-panel-runs/<RUN_ID>/report.md`

### Quick examples

```bash
/review-panel                                    # default variant, 20 reviewers (each persona × both models), current branch
/review-panel security-focused                   # security lens
/review-panel default --reviewers 10 --ratio 5:5 # cheaper pass: each persona once on one model
/review-panel default --reviewers 6 --ratio 3:3  # quick pass: 3 personas × both models
/review-panel --scope PR-1234                    # review a GitHub PR
/review-panel --dry-run                          # preview without executing
```

### Cost awareness

Each reviewer is roughly 3-8k input tokens + 1-3k output. A default run (20 reviewers + 1 aggregator) costs roughly 120-200k tokens total. The default doubles up so you get cross-model agreement/disagreement on every persona angle — drop to `--reviewers 10 --ratio 5:5` for half the cost.
