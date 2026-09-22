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

- **variant** (positional, default `"default"`): one of `default` (7 personas), `thorough`
  (the 16-persona panel), `security-focused`, `adversarial-debate`, or any name matching a
  `variants/<name>.yml` file
- **--reviewers N** (default: `persona_count` — each persona runs **once**)
- **--ratio C:X** (default: an even reviewer split)
- **--scope ref** (default `"main...HEAD"`)
- **--task id** (default: auto-detect)
- **--timeout secs** (default `600`)
- **--sarif** (default off): also write `findings.sarif` for GitHub code scanning
- **--simplify** (default off): run the `/simplify` pass after the report
- **--keep-artifacts** / **--dry-run** (default off)

Running a persona twice produces duplicate findings by construction and doubles the token
cost. Ask for it with `--reviewers` only when you mean it.

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
  [--sarif] \
  [--keep-artifacts] \
  [--dry-run]
```

`--simplify` is yours, not the dispatcher's. Strip it from the args before you call
`dispatch.sh`, which rejects flags it does not know, and act on it in Phase 5.

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
In record mode the raw findings sit beside it as `findings.jsonl`, and `findings.sarif` too
when `--sarif` was passed — upload that one with `gh code-scanning` to get inline PR alerts.

## Phase 5 — Simplify pass (only with `--simplify`)

A review command that edits code surprises whoever asked for an opinion, so this pass is
opt-in. When the user passed `--simplify`, run a cleanup pass on the reviewed scope:

```
Skill(skill="simplify")
```

Feed `/simplify` the same scope that was reviewed (the changed files). It applies the
`simplicity` reviewer's findings plus obvious dead-code / guard-clause / nesting cleanups,
running tests after each change. This is a single pass — do not loop it here.

Skip it even with the flag when: the run was `--dry-run`, the diff was empty, or the verdict
was `REJECT` (fix the blockers first, simplifying broken code is wasted work).

## How findings are recorded

A variant with `record_findings: true` — the `default` variant does — changes how reviewers
report. Instead of printing YAML for an aggregator to parse, each reviewer appends findings
by running `scripts/record.sh`, one call per finding, to a shared `findings.jsonl`.

Three things follow from that:

1. **Every finding must cite evidence.** `record.sh` rejects a finding with no `--evidence`:
   a `path:line` of the precedent in this repo, or the exact rule the diff breaks. An
   ungrounded opinion never reaches the report.
2. **`--category` is a closed set**, so the report groups and SARIF gets a stable `ruleId`.
3. **There is no per-reviewer verdict.** Severity decides it: any CRITICAL is `REJECT`, any
   HIGH is `REQUEST_CHANGES`, no findings is `APPROVE`. A reviewer cannot report a CRITICAL
   and vote APPROVE.

`scripts/report.sh` then builds `report.md` as a pure `jq` transform — no aggregator model
call, so nothing can invent a finding. `scripts/merge.jq` defines what counts as one finding:
same file, same line, same category. `report.sh` and `sarif.sh` both use it, so the Markdown
and the SARIF always agree.

Concurrent appends are safe without a lock because each finding is one compact JSON line
under 4 KB, and `record.sh` trims prose rather than dropping a finding that would exceed it.

Variants without `record_findings` keep the older path: reviewers print YAML and a single
`claude -p` aggregator consolidates it.

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

- **Headless only.** Do NOT spawn reviewers in cmux panes or Orca terminals. Use `claude -p`
  and `codex exec` — an interactive pane costs more and buys nothing a log does not.
- **Reviewers are non-interactive.** They read context, record findings, exit. No follow-up.
- **No aggregator call in record mode.** `report.sh` is a `jq` transform. Variants without
  `record_findings` still use a single `claude -p` aggregator.
- **Run dirs are scoped per invocation.** Old runs in `~/.claude/deep-review-runs/` are kept for audit; cleanup is manual.
- **Never invent findings.** If a reviewer fails, report it as failed — don't fabricate substitute findings.
