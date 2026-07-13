# qa-test-plan

Produce a **manual** (human, on-screen) QA test plan for a change, review it, execute it in a real
browser with a video recording, and return a pass/fail report.

Run it when a change alters user flows or adds screens. Referenced by `/deep-plan`'s plan handoff and
by `jira-workflow`.

## Invocation

```bash
/qa-test-plan [--url <app-url>] [--ticket KEY-123] [--slug <name>] [--plan <plan.md>] [--no-exec] [--dry-run]
```

Or naturally: "write a QA test plan", "manual test plan", "test the flow". `--no-exec` stops after
the reviewed doc (no browser run).

## What it does

1. **QA-mapper (Claude Sonnet)** traces the full user flow + edge cases and writes a **MANUAL** test
   plan — human steps (which screen, where to click, what to type, expected result), never automated
   test code.
2. **Codex doc review** checks the doc for missing roles/edge cases and ambiguous steps; fixes applied.
3. **Browser executor (codex worker in a cmux pane)** drives `agent-browser` to replay the steps
   against the running app: starts a video, performs steps, screenshots key states, writes a report.
4. **Orchestrator** reads the report and presents a summary + artifact paths.

## Model split (mandatory)

| Role | Model |
|------|-------|
| QA-mapper (flow + doc author) | Claude Sonnet |
| Doc reviewer | codex |
| Browser executor | codex |

All multi-agent work runs through **cmux** for visibility.

## Runtime dependencies

- `agent-browser` — browser automation CLI (open/snapshot/click/fill, `record start|stop`, screenshot).
- `cmux` — visible panes for the codex executor (must be invoked from inside cmux; falls back to
  headless `codex exec` otherwise).
- `codex` — doc reviewer + browser executor.
- `git` — diff/branch for scope + slug.

## Where artifacts land

Everything goes to the **project under test**'s `./tmp/` (relative to the repo being QA'd):

- `./tmp/<slug>-manual-test-plan.md` — the manual test plan
- `./tmp/<slug>.webm` — the execution video
- `./tmp/<slug>-<scenario>-<state>.png` — screenshots
- `./tmp/<slug>-qa-report.md` — pass/fail per scenario + artifact paths

Orchestration scratch (prompts, done markers) lives under `~/.claude/qa-test-plan-runs/`.

## Files

- `SKILL.md` — the 4-phase pipeline.
- `templates/manual-test-plan.md` — the doc template.
- `scripts/executable_launch-codex-worker.sh` — launches the codex browser worker in a cmux pane
  (raw cmux primitives; headless fallback if cmux is unavailable).
