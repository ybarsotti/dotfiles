---
name: qa-test-plan
description: Plan and execute evidence-backed manual QA for user-facing changes. Use via /qa-plan before implementation, /qa-execute after review on a frozen commit, or /qa-test-plan for both phases. Produces a validated qa-plan.yaml, human Markdown, browser-recorded scenario evidence, annotated screenshots, WebVTT-captioned videos, structured results.json, and an HTML report tied to the tested commit.
---

# QA test plan

Orchestrate two separable phases:

1. `plan`: map requirements, personas, journeys, edge cases, steps, and evidence policy.
2. `execute`: replay approved manual steps with `agent-browser` against a frozen commit and render evidence.

Keep `qa-plan.yaml` and `results.json` as sources of truth. Generate Markdown, annotated PNGs,
WebVTT, and HTML through bundled scripts. Never parse generated Markdown back into execution data.

## Arguments

```text
--phase plan|execute|all  default: all
--plan PATH               approved implementation plan
--qa-plan PATH            validated qa-plan.yaml; required for execute
--url URL                 running application URL; required for execute
--ticket KEY              ticket used for scope and traceability
--slug NAME               stable artifact name
--output-dir PATH         explicit plan or execution bundle
--commit SHA              exact commit deployed at --url; execute defaults to HEAD
--no-exec                 compatibility alias for --phase plan
--dry-run                 print phases, paths, and worker count without spawning
```

`/qa-plan` supplies `--phase plan`. `/qa-execute` supplies `--phase execute`.
`/qa-test-plan` defaults to `--phase all`.

## Contract files

Use:

- `templates/qa-plan.yaml` as mapper starting point.
- `schemas/qa-plan.schema.json` for plan shape.
- `schemas/qa-results.schema.json` for execution result shape.
- `scripts/qa_artifacts.py` after chezmoi deployment, or
  `scripts/executable_qa_artifacts.py` inside chezmoi source.

Run:

```bash
uv run ~/.claude/skills/qa-test-plan/scripts/qa_artifacts.py validate-plan QA_PLAN
uv run ~/.claude/skills/qa-test-plan/scripts/qa_artifacts.py render-plan QA_PLAN QA_DOC
uv run ~/.claude/skills/qa-test-plan/scripts/qa_artifacts.py validate-results QA_PLAN RESULTS
uv run ~/.claude/skills/qa-test-plan/scripts/qa_artifacts.py render-report QA_PLAN RESULTS REPORT
```

## Phase 0: resolve paths

Set `PROJECT_DIR` to repository under test. Derive slug from explicit `--slug`, ticket,
branch suffix, or short feature name.

For planning:

- With `--output-dir`: use it.
- With `--plan` and no output: use `<implementation-plan-dir>/qa`.
- Otherwise: use `$PROJECT_DIR/tmp/qa/<slug>/plan`.

Set `QA_PLAN=<output>/qa-plan.yaml` and `QA_DOC=<output>/qa-plan.md`.

For execution, create immutable attempt bundle:

```text
$PROJECT_DIR/tmp/qa/<slug>/<short-sha>-attempt-<n>/
├── qa-plan.yaml
├── results.json
├── index.html
├── manifest.json
└── evidence/
```

Never overwrite an earlier attempt. Copy approved `qa-plan.yaml` into bundle.

If `--dry-run`, print selected phase, derived paths, QA-mapper ×1, reviewer ×1,
browser executor ×1, then stop.

## Phase 1: map QA plan

Run for `plan` and `all`.

Spawn one Claude Sonnet QA-mapper. Give it implementation plan, ticket body, relevant user
journey, requirements matrix, code diff when present, project instructions, and
`templates/qa-plan.yaml`.

Require mapper to write only structured `QA_PLAN` containing:

- stable requirement, persona, scenario, and step IDs;
- every requirement mapped to at least one scenario;
- one scenario per meaningful persona/flow combination;
- explicit preconditions and isolated test data;
- happy path plus invalid, empty, permission, refresh/back, concurrency, boundary, and
  dependency-failure cases when applicable;
- objective acceptance rules;
- evidence policy per step.

Store semantic actions such as `Click "Submit order"` and accessible names. Never store
ephemeral `@e1` references or brittle CSS selectors.

Validate:

```bash
uv run ~/.claude/skills/qa-test-plan/scripts/qa_artifacts.py validate-plan "$QA_PLAN"
```

Spawn one Codex document reviewer. Ask it to inspect implementation plan and validated YAML
for missing requirements, personas, branches, preconditions, data isolation, actionable steps,
objective expectations, and evidence coverage. Apply concrete fixes to YAML, then validate again.

Render human document deterministically:

```bash
uv run ~/.claude/skills/qa-test-plan/scripts/qa_artifacts.py \
  render-plan "$QA_PLAN" "$QA_DOC"
```

For `plan`, report both paths and stop.

## Phase 2: freeze execution target

Run for `execute` and `all`.

Require `QA_PLAN` and reachable `--url`. Validate plan. Resolve requested commit from `--commit`
or `git rev-parse HEAD`. Record full SHA, URL, browser, viewport, feature flags, timestamps,
ticket, plan ID, and attempt in `manifest.json`.

Confirm deployed environment represents exact SHA. If environment cannot prove SHA, mark run
blocked; do not present evidence as commit-bound.

Verify binaries: `git`, `codex`, `agent-browser`, `uv`. Prefer visible cmux worker; use existing
headless fallback with explicit visibility warning.

## Phase 3: execute with agent-browser

Launch one Codex worker through `scripts/launch-codex-worker.sh`. Before browser commands,
worker must try:

```bash
agent-browser skills get agent-browser --full
```

Use returned syntax. If installed CLI responds `Unknown command: skills`, record compatibility
mode plus output of `agent-browser --version` and `agent-browser --help`, then use only commands
advertised by that help. Any other discovery failure blocks execution. Never rely on remembered
CLI flags.

Executor responsibilities:

1. Use seeded/demo identities and data. Never expose production PII, tokens, cookies, or secrets.
2. Create isolated browser state per persona. Reuse auth state only within same persona.
3. Execute scenarios in YAML order. Re-snapshot accessibility tree after every navigation or
   DOM-changing action. Resolve live element references from semantic plan instructions.
4. Record one raw WebM per scenario. Capture monotonic video start/end offsets for every step.
5. Capture raw PNG according to evidence policy and immediately on every failure.
6. Record observed result, status (`pass`, `fail`, `blocked`, `skipped`), console errors, network
   errors, timestamps, video offsets, screenshot path, and optional target bounding box.
7. Preserve failed attempts. Never change expectations to make implementation pass.
8. Write `results.json` matching `schemas/qa-results.schema.json`. Include every planned
   scenario and step exactly once.
9. Stop recording and browser through cleanup trap on every exit.

Write `done` or `blocked: <reason>` to executor marker. Surface blocked reason immediately.

## Phase 4: validate and render

Run:

```bash
uv run ~/.claude/skills/qa-test-plan/scripts/qa_artifacts.py \
  validate-results "$QA_PLAN" "$RESULTS"
uv run ~/.claude/skills/qa-test-plan/scripts/qa_artifacts.py \
  render-report "$QA_PLAN" "$RESULTS" "$REPORT"
```

Renderer must produce:

- `index.html` with run metadata, requirement coverage, scenario/step results, expected versus
  observed behavior, console/network errors, and seek-to-step controls;
- annotated PNG beside every raw screenshot, with step/action/expected/observed/result caption;
- WebVTT beside every scenario video, timed from recorded step offsets;
- untouched raw screenshots and videos.

Open generated report in browser. Confirm HTML loads, relative assets resolve, annotated images
render, video controls work, and WebVTT track exists. This report check is mandatory.

For stakeholder narration or PR GIF, reuse `Guided Tour Video` after QA report passes. QA evidence
stays raw and audit-oriented; narrated tour stays short and presentation-oriented.

## Phase 5: report

Return:

- overall PASS/FAIL/BLOCKED/SKIPPED counts;
- failed scenario and step IDs with observed result;
- tested commit SHA and URL;
- paths to `qa-plan.yaml`, `results.json`, `index.html`, and `evidence/`;
- explicit note when cmux visibility, commit proof, video, screenshot, console, or network
  evidence was unavailable.

## Completion gates

- [ ] structured-plan-valid
- [ ] requirements-covered
- [ ] personas-and-edges-covered
- [ ] plan-reviewed-by-codex
- [ ] exact-commit-recorded
- [ ] every-step-has-result
- [ ] failures-have-visual-evidence
- [ ] scenario-videos-captioned
- [ ] screenshots-preserved-and-annotated
- [ ] html-report-rendered-and-opened

Never claim QA complete with unchecked gate. Any code change after recorded SHA requires new
attempt for affected scenarios; never relabel stale evidence.
