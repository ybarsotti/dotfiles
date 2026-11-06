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

- **variant** (positional, default `"default"`): `default`, `security-focused`, `adversarial-debate`, or any `variants/<name>.yml`
- **--reviewers N** (default: `persona_count` — each persona runs **once**)
- **--ratio C:X** (default: an even reviewer split). It moves only `runner: any` personas.
  `default` pins all: Codex runs security, architecture, correctness, senior-backend and
  shortcut-watchdog; Claude runs project-fit, simplicity, ui-ux and senior-frontend.
- **--scope ref** (default `"main...HEAD"`)
- **--task id** (default: auto-detect)
- **--timeout secs** (default `600`)
- **--sarif** (default off): also write `findings.sarif` for GitHub code scanning
- **--no-simplify** (default off): skip the `/simplify` pass that otherwise runs after the report
- **--keep-artifacts** / **--dry-run** (default off)
- **--lens PATH** (repeatable): a review skill the repository owns. Run `--dry-run` first; it
  lists them. Pass at most 2 read-only lenses that fit the diff's stack. Skip plan reviewers,
  skills that start other agents, and skills that post to GitHub.

A persona with `only_when_changed` runs only when a changed file matches; each records ≤ 3 LOW.

A persona run twice duplicates its findings and doubles the cost; use `--reviewers` with care.

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

`--no-simplify` is yours, not the dispatcher's. Strip it from the args before you call
`dispatch.sh`, which rejects flags it does not know, and act on it in Phase 5.

`dispatch.sh` handles everything end-to-end: context, persona assignment, prompts, reviewers
in the background, and the `report.md`. Run it in the **foreground** to see progress. Don't background it.

## Phase 3 — Watch progress (non-dry-run only)

The dispatcher streams per-reviewer progress to stderr. A failed reviewer (timeout, non-zero
exit) is flagged in the report and does not stop the run.

## Phase 4 — Present the report

When the dispatcher finishes, the report is already on stdout. Just summarize the verdict in 1-2 sentences and offer next steps:

- If `APPROVE` → "All N reviewers cleared the changes. Ready to ship."
- If `REQUEST_CHANGES` → "N findings (X CRITICAL, Y HIGH). Top issue: <title>. Fixing now."
- If `REJECT` → "Critical blockers found. Top issue: <title>. Fixing the blockers before anything else."

Name the report path (`~/.claude/deep-review-runs/<RUN_ID>/report.md`); `findings.jsonl` and,
with `--sarif`, `findings.sarif` (for `gh code-scanning`) sit beside it.

## Phase 4.4 — Is the report still about this code?

A report is about one diff. Another commit, a rebase or a stash makes the findings read as
current while the code has moved on. `collect-context.sh` records the sha256 of the reviewed
diff, and `report.sh` prints it in the summary.

Before you act on a report this session did not just produce — the user names an older run, or
work happened between the run and now — check it:

```bash
~/.claude/skills/deep-review/scripts/check-stale.sh ~/.claude/deep-review-runs/<RUN_ID>
```

Exit 0 means the report is current. Exit 1 names the two hashes and the scope: re-run the panel
and do not act on the old findings. Exit 2 means the run cannot be checked, because it predates
the hash or its branch is gone. Say which of the three happened.

Skip it for the run you just finished in this session, where nothing has changed yet.

## Phase 4.5 — Fix, then re-review

A finding reported and not fixed is not a reviewed change, so this phase is the default rather
than a question. Do not stop at the report and wait to be asked.

1. **Fix every CRITICAL and HIGH**, from each finding's file, line and suggestion. First run
   each `prod-check:` QUESTION by `~/.claude/skills/_shared/query-check.md` §2; it can move a severity.
2. **Re-run the panel on the fix**, scoped to the changed files. A fix that introduces its own
   finding is common, and the second pass is what catches it.
3. **Stop after two fix rounds.** What survives goes in a `## Open findings` section with the
   reason, and you say plainly which findings remain.
4. **MEDIUM, LOW and QUESTION are the user's call.** List them and ask; do not fix them silently.

Skip it after `--dry-run` or an empty diff. The fixer is a separate `Agent`, never the reviewer.

## Phase 4.6 — Turn a recurring finding into a rule

A `## Recurring findings` section means earlier reviews of this repository already reported it.
Read the earlier titles and drop rows that share words but not the problem. For each real one,
propose one sentence of rule, where it goes (nearest `CLAUDE.md`, `.claude/rules/`, the repo's
rule docs) and its check (lint rule, architecture test, diff script, or "rule only"). Ask in one
multi-select `AskUserQuestion`; write only what the user picks, as a normal reviewed diff.

## Phase 5 — Simplify pass (default; skip with `--no-simplify`)

A review that names the same cleanups every time and applies none of them wastes the finding.
This pass runs by default. Say in the final summary that it ran and what it changed, so nobody
is surprised by a diff. Skip it when the user passed `--no-simplify`.

Run a cleanup pass on the reviewed scope:

```
Skill(skill="simplify")
```

Feed `/simplify` the same scope that was reviewed (the changed files). It applies the
`simplicity` reviewer's findings plus obvious dead-code / guard-clause / nesting cleanups,
running tests after each change. This is a single pass — do not loop it here.

Skip it regardless when: the run was `--dry-run`, the diff was empty, or the verdict was
`REJECT` (fix the blockers first, simplifying broken code is wasted work).

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
   HIGH is `REQUEST_CHANGES`, no findings is `APPROVE`; a `QUESTION` never blocks. A reviewer
   cannot report a CRITICAL and vote APPROVE.

`scripts/report.sh` then builds `report.md` as a pure `jq` transform — no aggregator model
call, so nothing can invent a finding. `scripts/merge.jq` defines what counts as one finding:
same file, same line, same category. `report.sh` and `sarif.sh` both use it, so the Markdown
and the SARIF always agree.

Concurrent appends are safe without a lock because each finding is one compact JSON line
under 4 KB, and `record.sh` trims prose rather than dropping a finding that would exceed it.

A variant may also pin a persona's `category`, as `security-focused` and `stress-test` do.
A focused panel then cannot scatter one concern across the closed set, and the report groups
the way the panel was meant to read. Without the field the reviewer picks per finding.

`adversarial-debate` is the one variant still on the older path, and deliberately: its
reviewers argue a `position` over a `dimension` rather than reporting findings, so there is
nothing for `record.sh` to validate and `aggregate.sh` weighs the two sides with a model.
Reviewers there print YAML and a single `claude -p` aggregator consolidates it.

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
