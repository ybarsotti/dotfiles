---
name: qa-test-plan
description: Produce a MANUAL (human, on-screen) QA test plan for a change, review it, then execute it in a real browser recording a video, and return a pass/fail report. Use when invoked via /qa-test-plan, when the user asks for a "QA test plan", "manual test plan", to "test the flow", or after a change that alters user flows or adds screens. Referenced by /deep-plan's plan handoff and by jira-workflow. The plan is human steps (which screen, where to click, what to type) — never automated test code.
---

# qa-test-plan

You are the **orchestrator** of a QA pipeline. Your job is to coordinate a QA-mapper agent, a codex doc reviewer, and a codex browser executor — you do **not** map the flow, review the doc, or drive the browser yourself. You parse args, dispatch agents, apply their fixes, and present the final report.

The document this pipeline produces is a **MANUAL test plan**: the steps a human runs on-screen (which screen, where to click, what to type, what to expect). It is **never** automated test code (no Playwright/Cypress/Jest source). Only the browser-execution phase automates anything, and only to *replay* the manual steps for evidence.

## Model-split convention (mandatory)

Multi-agent work splits Claude + codex and uses **cmux** for visibility:

| Role | Model | How |
|------|-------|-----|
| QA-mapper (flow + doc author) | **Claude Sonnet** | subagent / cmux worker |
| Doc reviewer | **codex** | `codex exec` |
| Browser executor | **codex** | codex worker in a cmux pane driving `agent-browser` |

## Phase 0 — Parse args & sanity checks

Read `$ARGUMENTS`. Extract:

- `--url <app-url>` (base URL of the running app; if absent, prompt the user or infer from the project's dev-server config)
- `--ticket KEY-123` (used for slug + scope framing; else auto-detect from branch/commit)
- `--slug <name>` (else derive: ticket key lowercased, else the git branch's last path segment, else a kebab summary of the change)
- `--plan <path>` (a plan.md, e.g. from /deep-plan, describing the change under test)
- `--no-exec` (default off — stop after the reviewed doc, skip Phase 3)
- `--dry-run` (default off)

Set:
- `PROJECT_DIR` = the project being tested (cwd of the repo under test).
- `TMP_DIR="$PROJECT_DIR/tmp"` — create it with `mkdir -p "$TMP_DIR"` (this is the project's `./tmp/`, where the doc + all artifacts land).
- `DOC="$TMP_DIR/<slug>-manual-test-plan.md"`, `REPORT="$TMP_DIR/<slug>-qa-report.md"`, `VIDEO="$TMP_DIR/<slug>.webm"`.
- `RUN_DIR=~/.claude/qa-test-plan-runs/$(date +%Y%m%d-%H%M%S)-<slug>` — orchestration scratch (prompts, done markers). `mkdir -p`.

Verify binaries: `git`, `codex`, `agent-browser`. Verify you are inside cmux for Phase 3: `cmux identify --json` and `which claude`.

If `--dry-run`: print the phases below with spawned-agent counts (QA-mapper ×1 Sonnet, reviewer ×1 codex, executor ×1 codex) and exit. Spawn nothing.

## Phase 1 — QA-mapper writes the MANUAL test plan (Claude Sonnet)

Spawn one **Claude Sonnet** QA-tester agent. Give it: the change under test (git diff `main...HEAD`, the `--plan` file if given, the ticket body if `--ticket`), the app `--url`, the template at `~/.claude/skills/qa-test-plan/templates/manual-test-plan.md`, and the target path `DOC`.

Its brief:

1. **Detect the FULL user flow** for the change — trace entry point → each screen → each action. Do not stop at the happy path; enumerate branches.
2. **Enumerate edge cases**: invalid input, empty states, permission-denied, back/refresh mid-flow, concurrent sessions, boundary values, error/timeout responses.
3. **Identify every persona/role** the flow touches (anonymous, standard user, admin, etc.) and the test data each needs.
4. **Write the MANUAL plan** into `DOC` using the template. For each scenario: the **role**, **preconditions**, then **numbered steps** where every step names *which screen*, *where to click / which control*, *what to type*, and the *expected result*. Add per-scenario **edge cases** and **acceptance rules** (objective pass/fail criteria).
5. It writes **prose steps a human could follow**, never automated test code.

When it returns, confirm `DOC` exists and follows the template (scenarios, steps, edge cases, acceptance rules).

## Phase 2 — Codex doc review

Spawn a `codex exec` agent to review `DOC` for completeness. Prompt it to check for: missing roles/personas, missing edge cases, ambiguous or non-actionable steps (a step a human couldn't unambiguously follow), missing or subjective acceptance rules, and steps that describe automated code instead of human actions. Have it output a concrete edit list.

Apply its fixes to `DOC`. If it finds nothing, note "codex review: clean".

**If `--no-exec`:** stop here. Present `DOC`'s path and a one-line summary of scenarios/edge cases. Tick the checklist through `doc-reviewed-by-codex` and report the executed/video/report items as skipped.

## Phase 3 — Browser execution (codex worker via cmux)

Launch a **codex** worker in a **cmux** pane (for visibility) that drives `agent-browser` to execute the manual steps against the running app.

1. Write the executor task file `$RUN_DIR/executor-task.md`. It must instruct the codex worker to, from `PROJECT_DIR`:
   - `mkdir -p ./tmp` (no auto-dir for the recording).
   - Set a cleanup trap: `trap 'agent-browser record stop 2>/dev/null || true; agent-browser close 2>/dev/null || true' EXIT`.
   - `agent-browser record start ./tmp/<slug>.webm` to begin the video.
   - For **each scenario** in `DOC`: `agent-browser open <url>` → `agent-browser wait --load networkidle` → `agent-browser snapshot -i` (lists interactive elements as `@e1,@e2,…`), then perform each step with `agent-browser click @eN` / `fill @eN "text"` / `type @eN "text"` / `select @eN "Value"` / `check @eN`. Semantic fallback: `agent-browser find role button click --name "Submit"` or `agent-browser find text "Sign In" click`. **Re-snapshot after any DOM change or navigation.**
   - `agent-browser screenshot ./tmp/<slug>-<scenario>-<state>.png` at key states.
   - Compare each step's observed result to the doc's expected result; record **pass/fail per step** against the acceptance rules.
   - `agent-browser record stop` when done.
   - Auth: if the flow needs a logged-in session, `agent-browser state save ./tmp/<slug>-auth.json` once and `state load` it in later scenarios.
   - Write `REPORT` (`./tmp/<slug>-qa-report.md`): pass/fail per scenario+step, the failure detail for any fail, and artifact paths (video + screenshots).
   - On completion write exactly `done` (or `blocked: <reason>`) to `$RUN_DIR/executor.done`.

2. Launch the worker:
   ```
   ~/.claude/skills/qa-test-plan/scripts/launch-codex-worker.sh "$RUN_DIR" "$PROJECT_DIR" qa-exec "$RUN_DIR/executor-task.md"
   ```
   It opens one cmux pane split-right, `cd`s to `PROJECT_DIR`, runs `codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check` on the task file, and echoes the pane/surface ref. If any cmux primitive is unavailable it falls back to a plain background `codex exec` (no pane) — note the loss of visibility to the user.

3. Monitor: poll `$RUN_DIR/executor.done` every 30–60s; peek with `cmux capture-pane --surface <ref> --lines 5`. If the marker reads `blocked: <reason>`, surface it to the user immediately.

## Phase 4 — Present the report

Read `REPORT`. Present:
- one-line verdict (e.g. `QA: 4/5 scenarios pass, 1 fail`),
- the failing scenario/step and why (if any),
- artifact paths: `DOC`, `REPORT`, `VIDEO`, and the screenshots directory (all under `PROJECT_DIR/tmp/`).

If any scenario failed, offer to open the video/screenshots or to start fixing.

## Checklist (machine-tickable — every box must be `[x]` before reporting complete)

- [ ] flow-mapped — full user flow traced (entry → screens → actions)
- [ ] edges-listed — edge cases enumerated per scenario
- [ ] acceptance-rules-listed — objective pass/fail rules per scenario
- [ ] doc-reviewed-by-codex — codex completeness review applied
- [ ] executed-in-browser — manual steps replayed via agent-browser *(skipped if `--no-exec`)*
- [ ] video-recorded — `.webm` captured in `./tmp/` *(skipped if `--no-exec`)*
- [ ] report-written — `<slug>-qa-report.md` written with pass/fail per scenario *(skipped if `--no-exec`)*

## Constraints & failure modes

- **The doc is MANUAL.** Human on-screen steps only — never emit or ask for Playwright/Cypress/Jest source. Only Phase 3 automates, and only to replay the manual steps for evidence.
- **Artifacts live in the project's `./tmp/`**, not the home dir — the doc, video, screenshots, and report are all relative to `PROJECT_DIR`.
- App URL missing/unreachable → ask the user for the running app's URL before Phase 3; do not guess.
- `agent-browser` not installed → halt Phase 3, tell the user (`agent-browser` skill / CLI required), keep the reviewed doc.
- Not inside cmux, or `launch-codex-worker.sh` can't get a pane → executor falls back to headless `codex exec`; warn that the run is not visible.
- Executor `blocked: <reason>` → surface immediately; do not fabricate pass results for un-run steps.
