# review-panel

Multi-agent peer review skill. Dispatches N reviewer personas (mix of Claude and Codex, headless) against a diff, then aggregates their findings into a single consolidated report.

## Quick start

```bash
# 1. Make sure you're in a git repo with a diff vs main
cd ~/your-project

# 2. Run the slash command from Claude Code
/review-panel                              # default: 20 reviewers (each persona × both models), branch vs main
/review-panel --dry-run                    # preview the plan without spending tokens
/review-panel --reviewers 10 --ratio 5:5   # cheaper: each persona once on one model
/review-panel --reviewers 4  --ratio 2:2   # quick pass with 4 reviewers

# 3. Pick a different lens
/review-panel security-focused             # all 10 personas wear security hats
/review-panel adversarial-debate           # 5 dimensions × approver-vs-rejecter pairs

# 4. Review a specific PR or file
/review-panel --scope PR-1234              # GitHub PR (uses `gh pr diff`)
/review-panel --scope file:src/auth.ts     # single file vs main
/review-panel --scope feature-x..feature-y # arbitrary git range
```

Reports are saved to `~/.claude/review-panel-runs/<RUN_ID>/report.md`.

## Architecture

```
slash command (~/.claude/commands/review-panel.md)
   │
   ▼
SKILL.md (this skill — orchestrates)
   │
   ▼
scripts/dispatch.sh  — parses args, builds run dir, fans out, aggregates
   ├── scripts/collect-context.sh  — git diff + repo metadata + linked Jira/Linear task
   ├── scripts/reviewer.sh         — runs ONE reviewer (claude -p OR codex exec)
   └── scripts/aggregate.sh        — single claude -p call to consolidate findings
```

All reviewers run **headless in background** (no cmux panes, no UI clutter). Default uses Claude Haiku for individual reviewers (cost) and Sonnet for aggregation (quality matters most there).

## Variants

| Variant | When to use |
|---------|-------------|
| `default` | General PR review with 10 distinct lenses |
| `security-focused` | Anything touching auth, payments, secrets, or external input |
| `adversarial-debate` | When you want strong arguments both ways before merging a contentious change |

Variant files are plain YAML at `~/.claude/skills/review-panel/variants/*.yml`. Add your own — the dispatcher picks them up automatically by filename.

## Writing a custom variant

```yaml
name: my-variant
description: One-line description shown in --dry-run output
output_schema: |
  ```yaml
  verdict: APPROVE | REQUEST_CHANGES | REJECT
  findings:
    - severity: CRITICAL | HIGH | MEDIUM | LOW
      file: ...
      line: ...
      title: ...
      description: ...
      suggestion: ...
  notes: ...
  ```
personas:
  - id: my-persona              # kebab-case, becomes filename
    role: One-line role         # shown in report
    focus: |
      What this persona looks for. Free text.
    runner: any                  # `claude` | `codex` | `any` (default — assigned by --ratio)
    requires_mcp: ["linear"]     # optional — skipped if not available
    prompt: |
      System-prompt text. Be specific about scope.
      Tell the persona what to ignore (other reviewers handle it).
```

## Cost guardrails

Each reviewer is roughly **3-8k input + 1-3k output tokens**. Default 20 reviewers + 1 aggregator run is **~120-200k tokens** total.

The default doubles up — each of the 10 personas runs once on Claude AND once on Codex — so you get cross-model agreement/disagreement on every angle. The aggregator surfaces disagreements explicitly.

For lighter passes:
- `--reviewers 10 --ratio 5:5` — each persona once, half cost (no cross-model)
- `--reviewers 4 --ratio 2:2` — quick triage during iteration
- `--dry-run` — preview the plan and estimated cost before paying

The reviewers default to Claude Haiku for the Claude side (cheap); Codex uses whatever model is configured in `~/.codex/config.toml`. The aggregator uses Sonnet because synthesis quality matters most. Override by editing `scripts/reviewer.sh` and `scripts/aggregate.sh`.

## Linked task awareness

The `scope-completeness` persona compares the diff to a Jira/Linear task. Auto-detected from:
1. Branch name (e.g. `feat/PROJ-123-x`)
2. Recent commit messages (any `[A-Z]+-[0-9]+` token)
3. Override with `--task PROJ-123`

When the task is found, `collect-context.sh` tries `lineark issue view <id>` to fetch the body. If not available, the task ID is still passed but the persona notes the gap.

## Cross-tool

This skill lives in `~/.claude/commands/` so it's invoked from Claude. The reviewers themselves run as background subprocesses — half use `claude -p` (default), half use `codex exec`. Switching the orchestrator from Claude to Codex needs an equivalent command file under Codex's prompts directory (not yet built — phase 2).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `yq not installed` | First run on a fresh machine | `brew install yq` (or `chezmoi apply` once the package list is synced) |
| `no timeout binary` | macOS without coreutils | `brew install coreutils`; the skill falls back to a perl one-liner if neither is present |
| Reviewers all return "failed" | claude/codex CLIs not authenticated | Run `claude` and `codex` interactively once to log in |
| Empty diff error | Branch is identical to base | Pass `--scope` with a real range |
| codex hangs | Sandbox prompt waiting on TTY | The skill uses `--dangerously-bypass-approvals-and-sandbox` — if this still happens, check for stale interactive sessions |

## File layout

```
~/.claude/skills/review-panel/
├── README.md                         # this file
├── SKILL.md                          # protocol Claude reads when /review-panel runs
├── scripts/
│   ├── dispatch.sh                   # main orchestrator
│   ├── collect-context.sh            # builds context.md
│   ├── reviewer.sh                   # runs ONE reviewer
│   └── aggregate.sh                  # consolidates results
└── variants/
    ├── default.yml                   # 10 personas, multi-perspective
    ├── security-focused.yml          # 10 personas, security lens
    └── adversarial-debate.yml        # 5 approver-vs-rejecter pairs
```

Reports persist at `~/.claude/review-panel-runs/<RUN_ID>/report.md` (the run dir at `/tmp/review-panel/...` is cleaned up unless `--keep-artifacts`).
