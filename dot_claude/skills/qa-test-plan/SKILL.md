---
name: qa-test-plan
description: Use via /qa-plan before implementation (write the QA test plan), /qa-execute after review on a frozen commit (run the plan, produce QA evidence for the PR), or /qa-test-plan for both. Produces qa-plan.yaml, videos, screenshots and an HTML report.
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

`/qa-plan` supplies `--phase plan`; it needs `--plan PATH`, because without the plan there are
no requirements to map. `/qa-execute` supplies `--phase execute`. `/qa-test-plan` defaults to
`--phase all`.

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
- **a risk score for each scenario**, so the depth follows the risk. Score blast radius,
  reversibility and data risk from 1 to 5, and keep the highest as the scenario's risk.
  Reversibility 5 means a data rewrite, a sent email or a payment. Order the scenarios by
  risk. A scenario at 4 or 5 gets every applicable edge case and checks each side effect in
  each system it reaches. A scenario at 1 or 2 gets the happy path and one failure case;
- **regression scenarios for the existing flows that the change can break**, from the
  regression map below;
- one scenario per meaningful persona/flow combination;
- explicit preconditions and isolated test data;
- happy path plus invalid, empty, permission, refresh/back, concurrency, boundary, and
  dependency-failure cases when applicable;
- **out-of-pattern user input, for every field and every upload of the flow.** Write these as
  scenarios with steps and the literal value in `input`, not only as a line in `edge_cases`.
  The expected result names what the user sees (the field message, the disabled action) and
  what does not happen (no row saved, no email sent). Pick the classes that apply from the
  catalog below.

**Regression map.**

The plan lists what the change must do. The regression map lists what the change must not
break: the flows that already exist and share code, data or contracts with the change.

1. List what the change touches: the changed symbols from the diff or the plan, the tables
   and columns, the API routes and payloads, the shared components, the jobs, the settings
   and the feature flags.
2. Find who else uses each one. In a project with a GitNexus index, run `impact` on each
   changed symbol, and `detect_changes` on the diff. Else search the callers with `rg`. Group
   the callers into user flows: a screen, an API consumer, a job, a report, an email.
3. Drop the flows that the plan already covers. For each remaining flow, score its risk with
   the same 1 to 5 scale as the scenarios. Write why the change can reach it.
4. Check the automated tests. A flow with a test that runs the changed code path is covered
   by CI. Name the test and add no scenario for it. QA covers the flows that no test reaches.
5. Add one requirement per remaining flow, with the id `REG-<n>` and the text "<flow> keeps
   working as before". Map it to a scenario. A flow at risk 1 or 2 gets one happy-path
   scenario. A flow at risk 3 or more also gets the failure case that the change can affect.
6. Write the map to `regression-map.md` beside `qa-plan.yaml`: one row per flow, with its
   risk, the reason, and its coverage (`REG` scenario, a named test, or `not reachable`). When the change
   shares nothing with other flows, write one line that says so and why. Never leave the map
   out without that line.


Start from the rules of the project, not from generic values. For each field, read its limits
where the code defines them: the column size and type, the model or ORM validators, the API
schema (serializer, pydantic, zod), the form rules in the frontend, and the business rules in
the plan and the ticket. Test at each limit, one step past it, and where the frontend and the
backend disagree. A free-text field that a user fills gets the most cases.

| Class | Values to try |
|---|---|
| Empty and blank | empty, only spaces, only a line break, a required field left out |
| Whitespace | leading and trailing spaces, double spaces, a tab, a pasted line break |
| Length | 1 character, the maximum, the maximum + 1, a very long text (10 000 characters) |
| Numbers | 0, negative, decimal in an integer field, comma vs dot decimal, thousands separator, `1e5`, a value above the limit, letters in a number field |
| Money and percent | more decimals than the currency allows, a currency symbol pasted in, 100.01 % |
| Dates and times | 31 Feb, 29 Feb in a non-leap year, a past date where a future one is needed, the other locale's format (`02/03`), DST change, end before start |
| Text content | accents, emoji, right-to-left text, `<script>alert(1)</script>`, `' OR 1=1 --`, `{{7*7}}`, a URL, a value copied with formatting |
| Identity values | an email with `+tag`, upper case, no TLD, spaces; a phone with country code, dashes and spaces; a tax id with and without its mask |
| Choices | a value outside the list sent through the URL or the API, no selection, a removed option |
| Files | empty file, wrong type with the right extension, a file over the size limit, a long name with accents, the same file twice |
| Repetition | double click on submit, the back button after submit, a refresh in the middle, two tabs editing the same record |
| Project limits | the exact limit of each field from the model, the schema and the business rules; one past it; a value that the frontend accepts and the backend refuses, or the reverse |
| AI input (a field, a file or a message that reaches a model) | "ignore all previous instructions and …"; a request for the system prompt or the hidden rules; a role-play or jailbreak that asks to drop the guardrails; instructions hidden in an uploaded file, a pasted URL, an email or a web page the feature reads; a request to act outside its scope (send, delete, pay, read another account); a request for another user's or tenant's data; a prompt in another language; a text long enough to blow the token budget; a request whose answer would carry HTML, a script or a link that the UI then renders |

Mark a class `n/a` with the reason when it does not apply. Never skip it silently. For AI
input, the expected result is that the feature keeps its rules: it refuses or ignores the
injected instruction, reveals no prompt and no other user's data, takes no action without the
user's confirmation, stays within the cost limit, and renders the model output as plain
text.
- objective acceptance rules;
- evidence policy per step;
- **a design-comparison scenario for every screen the change adds or alters.** Ask first
  whether a design exists — a claude.design output, a Figma frame, exported images in the
  plan or ticket. When one exists, the mapper attaches it to the scenario and the
  acceptance rule is that the captured screenshot matches it on layout, hierarchy, states
  and exact copy. When none exists, record the scenario with acceptance `unverifiable — no
  design supplied` rather than dropping it: a screen nobody could check against anything
  must show up as an unanswered question, not as a pass. Skip only when the change touches
  no user-facing screen.

Store semantic actions such as `Click "Submit order"` and accessible names. Never store
ephemeral `@e1` references or brittle CSS selectors.

Validate:

```bash
uv run ~/.claude/skills/qa-test-plan/scripts/qa_artifacts.py validate-plan "$QA_PLAN"
```

Spawn one Codex document reviewer on `gpt-6.1-terra` (`codex exec --model gpt-6.1-terra`). Ask it to inspect implementation plan, validated YAML and
`regression-map.md` for missing requirements, callers the regression map missed, personas, branches, preconditions, data isolation, actionable steps,
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

Verify binaries: `git`, `codex`, `agent-browser`, `uv`. Prefer a visible Orca terminal; use the
headless fallback with explicit visibility warning.

## Phase 3: execute with agent-browser

Launch one Codex worker through `scripts/launch-codex-worker.sh`. It prints the terminal
handle. When the worker finishes or fails, close its tab:
`orca terminal close --terminal <handle> --tab --json`. Before browser commands,
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
- explicit note when Orca terminal visibility, commit proof, video, screenshot, console, or network
  evidence was unavailable.

## Completion gates

- [ ] structured-plan-valid
- [ ] requirements-covered
- [ ] regression-map-written
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
