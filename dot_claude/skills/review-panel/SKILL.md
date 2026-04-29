---
name: review-panel
description: Multi-agent peer review — runs N reviewer personas in parallel (Claude + Codex headless), aggregates findings into a consolidated report. Use when invoked via /review-panel slash command, or when the user asks for "peer review", "multi-perspective review", "panel review", "adversarial review", or wants several agents to look at the same diff with different lenses.
---

# Review Panel

You are the **orchestrator** of a peer-review panel. Your job is to dispatch N reviewer agents (mix of Claude and Codex, headless) against a diff, then aggregate their findings into a single consolidated report.

**You do NOT review the diff yourself.** Reviewers do that in parallel background processes. You parse args, kick off the dispatcher, watch progress, and present the final report.

## When this skill is invoked

The user typed `/review-panel [args]`, OR the user asked for a multi-agent peer review of the current changes. In either case, follow this protocol.

## Phase 1 — Parse args

Read `$ARGUMENTS` and extract:

- **variant** (positional, default `"default"`): one of `default`, `security-focused`, `adversarial-debate`, or any name matching a `variants/<name>.yml` file
- **--reviewers N** (default `10`)
- **--ratio C:X** (default `5:5`)
- **--scope ref** (default `"main...HEAD"`)
- **--task id** (default: auto-detect)
- **--timeout secs** (default `600`)
- **--keep-artifacts** (default off)
- **--dry-run** (default off)

Validate:

- Variant file exists at `~/.claude/skills/review-panel/variants/<variant>.yml`
- `--reviewers` is positive integer; `--ratio` matches `\d+:\d+` and sums to `--reviewers` (or rebalance proportionally)
- Required binaries: `claude`, `git`, `yq`. `codex` only if Codex reviewers > 0. `gh` only if `--scope PR-*`.

If validation fails, print a clear error and exit. **Do not try to repair invalid args silently.**

## Phase 2 — Invoke the dispatcher

The dispatcher script does the heavy lifting. Call it with the parsed args:

```bash
~/.claude/skills/review-panel/scripts/dispatch.sh \
  "<variant>" \
  --reviewers <N> \
  --ratio <C>:<X> \
  --scope <ref> \
  [--task <id>] \
  [--timeout <secs>] \
  [--keep-artifacts] \
  [--dry-run]
```

The dispatcher:

1. Creates a run directory at `/tmp/review-panel/run-<TIMESTAMP>-<rand>/`
2. Calls `collect-context.sh` to assemble `context.md` (git diff + repo metadata + linked task body)
3. Reads the variant YAML, picks N personas, assigns runners per `--ratio`
4. Writes per-reviewer prompt files into the run dir
5. **Dry run**: prints the plan (variant, personas, runners, scope, estimated cost) and exits
6. **Real run**: fans out reviewers as background processes, streams progress to a single log, waits for completion (with per-reviewer timeout), then calls `aggregate.sh`
7. Saves `report.md` to `~/.claude/review-panel-runs/<RUN_ID>/` and prints it to stdout

You should run the dispatcher in the **foreground** so you see progress live. Don't background it.

## Phase 3 — Watch progress (non-dry-run only)

The dispatcher streams updates like this to stderr:

```
[review-panel] run-id=run-20260428-153012-a3f
[review-panel] variant=default reviewers=10 ratio=5:5 scope=main...HEAD
[review-panel] context: 12 files, 340+ / 87-, task=PROJ-456
[review-panel] starting reviewers...
[security        ] dispatched (claude)
[edge-cases      ] dispatched (codex)
...
[security        ] done (42s, 7 findings)
[edge-cases      ] done (51s, 3 findings)
...
[review-panel] all reviewers done (8/10 ok, 2 failed: scope-completeness timeout)
[review-panel] aggregating...
[review-panel] report saved to ~/.claude/review-panel-runs/run-.../report.md
```

If reviewers fail (timeout, exit non-zero), the dispatcher continues with whoever finished. Failed reviewers are flagged in the report — they're informational, not fatal.

## Phase 4 — Present the report

When the dispatcher finishes, the report is already on stdout. Just summarize the verdict in 1-2 sentences and offer next steps:

- If `APPROVE` → "All N reviewers cleared the changes. Ready to ship."
- If `REQUEST_CHANGES` → "N findings (X CRITICAL, Y HIGH). Top issue: <title>. Want me to start fixing?"
- If `REJECT` → "Critical blockers found. Top issue: <title>. Recommend stopping and addressing before any further work."

Always tell the user where the full report lives (`~/.claude/review-panel-runs/<RUN_ID>/report.md`).

## Error handling

| Scenario | Action |
|----------|--------|
| Empty diff (no changes vs base) | Print "Nothing to review" and exit cleanly |
| Variant file missing | List available variants, suggest closest match |
| `claude` or `codex` CLI missing | Print install instructions, exit |
| Persona requires MCP not available (e.g. `requires_mcp: ["linear"]` but no Linear MCP) | Persona is skipped with note in report — not fatal |
| All reviewers fail | Aggregator should still run and produce a report explaining the failure |
| User Ctrl+C mid-run | Dispatcher kills child processes (it traps SIGINT); run dir is preserved |

## Constraints

- **Headless only.** Do NOT spawn reviewers in cmux panes. Use `claude -p` and `codex exec`.
- **Reviewers are non-interactive.** They read context, output structured findings, exit. No follow-up.
- **One aggregator call.** The aggregator is a single `claude -p` invocation that consumes all reviewer outputs.
- **Run dirs are scoped per invocation.** Old runs in `~/.claude/review-panel-runs/` are kept for audit; cleanup is manual.
- **Never invent findings.** If a reviewer fails, report it as failed — don't fabricate substitute findings.
