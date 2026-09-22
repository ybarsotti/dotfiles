---
description: Multi-agent peer review — fixed reviewer personas in parallel (Claude Sonnet + Codex headless), each recording evidence-backed findings into one report
---

# /deep-review

Run a panel of reviewer agents in parallel against the current branch (or a target file/PR)
and produce one consolidated report.

Each reviewer uses a **fixed, predefined prompt file** (`personas/<id>.md`) — the orchestrator
never authors reviewer prompts. Claude-side reviewers always run on **Sonnet**; the Codex side
stays Codex.

Reviewers do not print findings. They record each one with `scripts/record.sh`, which
**rejects a finding that cites no evidence** — a `path:line` of the precedent in this repo, or
the rule the diff breaks. The report is then a `jq` transform of those records, so no model
gets a chance to invent a finding.

**Arguments:** `$ARGUMENTS`

## Argument grammar

```
/deep-review [variant] [flags]

VARIANT (positional, optional, default: "default")
  default             7 personas, each run once: security, senior-backend, senior-frontend,
                      correctness, architecture, simplicity, project-fit
  thorough            the previous 16-persona roster, for a change that earns it
  security-focused    every persona reviews through an OWASP/security lens
  adversarial-debate  approver-vs-rejecter pairs across 5 dimensions
  stress-test         paranoid personas simulating concrete failure scenarios
                      (races, partial failures, network chaos, time bugs, abuse)

FLAGS
  --reviewers N       total reviewers (default: persona_count — each persona runs ONCE)
  --ratio C:X         Claude:Codex split (default: even reviewer split)
  --scope <ref>       git range (default: main...HEAD), or "PR-1234", or "file:path"
  --task <id>         force a Jira/Linear task ID (default: auto-detect from branch/commit)
  --timeout <secs>    per-reviewer timeout (default: 600)
  --sarif             also write findings.sarif for GitHub code scanning
  --simplify          run the /simplify cleanup pass after the report (off by default)
  --keep-artifacts    don't delete the run dir after completion
  --dry-run           print the plan without spawning reviewers

MODELS
  Claude side  sonnet
  Codex side   see scripts/reviewer.sh
               override: DEEP_REVIEW_CODEX_MODEL / DEEP_REVIEW_CODEX_EFFORT
               (none|minimal|low|medium|high|xhigh|max)
```

## What you must do

You are the **orchestrator**. Invoke the `deep-review` skill — do NOT try to run reviewers
manually inline. The skill defines the full protocol. Follow it exactly.

The skill lives at `~/.claude/skills/deep-review/SKILL.md` and its scripts at
`~/.claude/skills/deep-review/scripts/`.

### High-level flow

1. Parse `$ARGUMENTS` into variant + flags. Keep `--simplify` for yourself; the dispatcher
   rejects flags it does not know.
2. Run `~/.claude/skills/deep-review/scripts/dispatch.sh "$VARIANT" --scope <ref> [flags]`
3. The dispatcher builds the run dir, loads each reviewer's fixed `personas/<id>.md` prompt,
   fans reviewers out in the background, waits, and builds the report.
4. Report goes to stdout and to `~/.claude/deep-review-runs/<RUN_ID>/report.md`, beside
   `findings.jsonl` (and `findings.sarif` with `--sarif`).
5. Only with `--simplify`: run `/simplify` on the reviewed scope.

### Findings

Every finding carries a severity (`CRITICAL`, `HIGH`, `MEDIUM`, `LOW`) and a category from a
closed set: `security`, `correctness`, `concurrency`, `db-performance`, `typing`,
`architecture`, `simplicity`, `code-reuse`, `tests`, `docs`, `project-fit`, `scope`,
`frontend`, `observability`.

There is no per-reviewer verdict. Severity decides it: any CRITICAL is `REJECT`, any HIGH is
`REQUEST_CHANGES`, nothing recorded is `APPROVE`.

### Quick examples

```bash
/deep-review                                    # 7 personas, current branch
/deep-review thorough                           # the 16-persona panel
/deep-review security-focused                   # security lens
/deep-review --scope PR-1234 --sarif            # review a GitHub PR, emit SARIF
/deep-review default --ratio 7:0                # Claude only, no Codex
/deep-review --dry-run                          # preview without executing
```

### Cost awareness

Each reviewer uses roughly 3-8k input tokens and 1-3k output tokens. The default is 7
reviewers and **no aggregator call**, because the report is built by `jq`.

The previous default ran 32 reviewers plus an aggregator. `thorough` still does 16. Reach for
it when the diff is large or risky, not by habit.
