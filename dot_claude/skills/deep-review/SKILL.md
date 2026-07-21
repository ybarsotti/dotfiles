---
name: deep-review
description: Multi-agent peer review — runs N reviewer personas in parallel (Claude + Codex headless), aggregates findings into a consolidated report. Use when invoked via /deep-review slash command, or when the user asks for "peer review", "multi-perspective review", "panel review", "adversarial review", or wants several agents to look at the same diff with different lenses.
---

# Review Panel

You are the **orchestrator** of a peer-review panel. Your job is to dispatch N reviewer agents (mix of Claude and Codex, headless) against a diff, then aggregate their findings into a single consolidated report.

**You do NOT review the diff yourself.** Reviewers do that in parallel background processes. You parse args, kick off the dispatcher, watch progress, and present the final report.

## When this skill is invoked

The user typed `/deep-review [args]`, OR the user asked for a multi-agent peer review of the current changes. In either case, follow this protocol.

## Phase 1 — Parse args

Read `$ARGUMENTS` and extract:

- **variant** (positional, default `"default"`): one of `default`, `security-focused`, `adversarial-debate`, or any name matching a `variants/<name>.yml` file
- **--reviewers N** (default: `2 × persona_count`)
- **--ratio C:X** (default: `N:N` where N = persona_count)
- **--scope ref** (default `"main...HEAD"`)
- **--task id** (default: auto-detect)
- **--timeout secs** (default `600`)
- **--keep-artifacts** / **--dry-run** (default off)

`scripts/dispatch.sh` validates all of this itself (variant file exists, `--reviewers` is a
positive integer, `--ratio` sums correctly, required binaries are present) and exits with a
clear error if anything is wrong. **Do not try to repair invalid args silently** — pass them
through and let it fail.

## Phase 2 — Invoke the dispatcher

Call the dispatcher with the parsed args:

```bash
~/.claude/skills/deep-review/scripts/dispatch.sh \
  "<variant>" \
  --reviewers <N> \
  --ratio <C>:<X> \
  --scope <ref> \
  [--task <id>] \
  [--timeout <secs>] \
  [--keep-artifacts] \
  [--dry-run]
```

`dispatch.sh` handles everything end-to-end: context collection, persona assignment, prompt
generation, fanning reviewers out as background processes, waiting for them, and aggregating
the result into `report.md`.

You should run the dispatcher in the **foreground** so you see progress live. Don't background it.

## Phase 3 — Watch progress (non-dry-run only)

The dispatcher streams per-reviewer dispatch/completion lines to stderr as it runs. If a
reviewer fails (timeout, non-zero exit), the dispatcher continues with whoever finished and
flags the failure in the report — that's informational, not fatal.

## Phase 4 — Present the report

When the dispatcher finishes, the report is already on stdout. Just summarize the verdict in 1-2 sentences and offer next steps:

- If `APPROVE` → "All N reviewers cleared the changes. Ready to ship."
- If `REQUEST_CHANGES` → "N findings (X CRITICAL, Y HIGH). Top issue: <title>. Want me to start fixing?"
- If `REJECT` → "Critical blockers found. Top issue: <title>. Recommend stopping and addressing before any further work."

Always tell the user where the full report lives (`~/.claude/deep-review-runs/<RUN_ID>/report.md`).

## Phase 5 — Simplify pass

After presenting the report, run a cleanup pass on the reviewed scope:

```
Skill(skill="simplify")
```

Feed `/simplify` the same scope that was reviewed (the changed files). It applies the
`simplicity` reviewer's findings plus obvious dead-code / guard-clause / nesting cleanups,
running tests after each change. This is a single pass — do not loop it here.

Skip Phase 5 only when: the run was `--dry-run`, the diff was empty, or the verdict was
`REJECT` (fix the blockers first, simplifying broken code is wasted work).

## Reviewer model policy

`scripts/reviewer.sh` pins Claude-side reviewers to Sonnet and Codex-side reviewers to a
fixed high-effort model (both env-overridable — see the script). Each reviewer's prompt is a
**fixed file** at `personas/<id>.md`; the orchestrator never authors reviewer prompts.
`reviewer.sh` is also reusable as the single-persona per-round reviewer for `/deep-execute`.

## Error handling

`dispatch.sh` handles its own failure modes — empty diff, missing variant, missing
`claude`/`codex`, a persona whose required MCP isn't configured, all reviewers failing, or a
Ctrl+C mid-run (it traps SIGINT and preserves the run dir for inspection). Report what it
says; don't work around a failure it already reported.

## Constraints

- **Headless only.** Do NOT spawn reviewers in cmux panes. Use `claude -p` and `codex exec`.
- **Reviewers are non-interactive.** They read context, output structured findings, exit. No follow-up.
- **One aggregator call.** The aggregator is a single `claude -p` invocation that consumes all reviewer outputs.
- **Run dirs are scoped per invocation.** Old runs in `~/.claude/deep-review-runs/` are kept for audit; cleanup is manual.
- **Never invent findings.** If a reviewer fails, report it as failed — don't fabricate substitute findings.
