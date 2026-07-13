---
description: Multi-agent peer review — runs fixed reviewer personas in parallel (Claude Sonnet + Codex headless), aggregates a consolidated report, then runs /simplify
---

# /deep-review

Run a configurable panel of reviewer agents in parallel against the current branch (or a target file/PR), aggregate their findings into a single consolidated report, then apply a `/simplify` cleanup pass.

Each reviewer uses a **fixed, predefined prompt file** (`personas/<id>.md`) — the orchestrator never authors reviewer prompts. Claude-side reviewers always run on **Sonnet**; the Codex side stays Codex.

**Arguments:** `$ARGUMENTS`

## Argument grammar

```
/deep-review [variant] [flags]

VARIANT (positional, optional, default: "default")
  default             multi-perspective fixed roster: project-patterns, db-performance,
                      senior-frontend, senior-backend, security, edge-cases, test-coverage,
                      architecture, concurrency-races, simplicity, scope-completeness
  security-focused    every persona reviews through an OWASP/security lens
  adversarial-debate  approver-vs-rejecter pairs across 5 dimensions
  stress-test         paranoid personas simulating concrete failure scenarios
                      (races, partial failures, network chaos, time bugs, abuse)

FLAGS
  --reviewers N       total reviewers (default: 2 × persona_count, so each persona runs once on Claude + once on Codex)
  --ratio C:X         Claude:Codex split (default: N:N where N = persona_count)
  --scope <ref>       git range (default: main...HEAD), or "PR-1234", or "file:path"
  --task <id>         force a Jira/Linear task ID (default: auto-detect from branch/commit)
  --timeout <secs>    per-reviewer timeout (default: 600)
  --keep-artifacts    don't delete the run dir after completion
  --dry-run           print the plan without spawning reviewers
```

## What you must do

You are the **orchestrator**. Invoke the `deep-review` skill — do NOT try to run reviewers manually inline. The skill defines the full protocol (validate args → collect context → fan out fixed-prompt reviewers → aggregate → /simplify). Follow it exactly.

The skill lives at `~/.claude/skills/deep-review/SKILL.md` and its scripts at `~/.claude/skills/deep-review/scripts/`.

### High-level flow

1. Parse `$ARGUMENTS` into variant + flags
2. Run `~/.claude/skills/deep-review/scripts/dispatch.sh "$VARIANT" --reviewers <N> --ratio <C:X> --scope <ref> [--dry-run]`
3. The dispatcher handles everything: builds the run dir, loads each reviewer's fixed `personas/<id>.md` prompt, fans out reviewers in background (Claude Sonnet + Codex), waits, and aggregates
4. Report is printed to stdout AND saved to `~/.claude/deep-review-runs/<RUN_ID>/report.md`
5. Run `/simplify` on the reviewed scope to apply the simplicity findings

### Quick examples

```bash
/deep-review                                    # default roster (each persona × both models), current branch
/deep-review security-focused                   # security lens
/deep-review stress-test                        # paranoid mode — every persona simulates failure scenarios
/deep-review default --reviewers 11 --ratio 11:0 # cheaper pass: each persona once on Claude/Sonnet only
/deep-review default --reviewers 6 --ratio 3:3  # quick pass: 3 personas × both models
/deep-review --scope PR-1234                    # review a GitHub PR
/deep-review --dry-run                          # preview without executing
```

### Cost awareness

Each reviewer is roughly 3-8k input tokens + 1-3k output. A default run (~24 reviewers + 1 aggregator) costs roughly 130-220k tokens total. The default doubles up so you get cross-model agreement/disagreement on every persona angle — drop to `--reviewers 12 --ratio 6:6` for half the cost.
