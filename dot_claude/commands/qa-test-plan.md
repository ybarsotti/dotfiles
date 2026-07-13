---
description: Manual (human, on-screen) QA test plan for a change — QA-mapper drafts it, codex reviews it, a codex+browser worker executes it on video, orchestrator reports pass/fail
---

# /qa-test-plan

Produce a **manual** QA test plan for a change (the kind a human runs on-screen — which screen, where to click, what to type, expected result), harden it, then execute it in a real browser with a video recording and return a pass/fail report.

Run this when a change alters user flows or adds screens. Referenced by `/deep-plan`'s plan handoff and by `jira-workflow`.

1. **QA-mapper (Claude Sonnet)** — acts as a QA tester. Traces the full user flow (entry → screens → actions) + edge cases, then writes a **MANUAL** test plan (human steps, never automated code) to `./tmp/<slug>-manual-test-plan.md` in the project under test.
2. **Codex doc review** — a `codex exec` agent reviews the doc for completeness (missing roles/edge cases, ambiguous steps); fixes are applied.
3. **Browser execution (codex worker in a cmux pane)** — a codex worker drives `agent-browser` to run the manual steps against the running app: start a video recording, perform steps, screenshot key states, stop recording, write `./tmp/<slug>-qa-report.md`.
4. **Orchestrator** reads the report and presents a summary + artifact paths.

**Arguments:** `$ARGUMENTS`

## Argument grammar

```
/qa-test-plan [--url <app-url>] [--ticket KEY-123] [--slug <name>] [--plan <plan.md path>] [--no-exec] [--dry-run]

FLAGS
  --url <app-url>     base URL of the running app (else prompt / infer from project)
  --ticket KEY-123    ticket key — used for the slug and scope framing
  --slug <name>       explicit artifact slug (else from branch name or ticket)
  --plan <path>       a plan.md (e.g. from /deep-plan) describing the change to test
  --no-exec           stop after the reviewed doc — skip the browser run entirely
  --dry-run           print the phases + spawned-agent counts without spawning anything
```

## What you must do

You are the **orchestrator**. Invoke the `qa-test-plan` skill — do NOT map the flow, review the doc, or drive the browser inline.

The skill lives at `~/.claude/skills/qa-test-plan/SKILL.md`. Follow its phases exactly. The doc it produces is **manual** (human on-screen steps), never automated test code.

### Quick examples

```bash
/qa-test-plan --url http://localhost:3000
/qa-test-plan --ticket FBIT-2982 --url http://localhost:3000
/qa-test-plan --plan ./tmp/dark-mode-plan.md --url http://localhost:5173
/qa-test-plan --slug checkout-redesign --no-exec
/qa-test-plan --dry-run --url http://localhost:3000
```
