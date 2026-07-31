# Graph Report - .  (2026-07-31)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 122 nodes · 231 edges · 27 communities (22 shown, 5 thin omitted)
- Extraction: 73% EXTRACTED · 27% INFERRED · 0% AMBIGUOUS · INFERRED: 63 edges (avg confidence: 0.54)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `358ed1a7`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]

## God Nodes (most connected - your core abstractions)
1. `FrozenModel` - 13 edges
2. `StepView` - 11 edges
3. `ScenarioView` - 11 edges
4. `RequirementView` - 11 edges
5. `ReportView` - 11 edges
6. `ScreenshotAnnotation` - 11 edges
7. `ScenarioCaption` - 11 edges
8. `ResultStatus` - 8 edges
9. `Requirement` - 8 edges
10. `Persona` - 8 edges

## Surprising Connections (you probably didn't know these)
- `bind_run()` --calls--> `BoundRun`  [INFERRED]
  dot_claude/skills/qa-test-plan/scripts/qa_artifacts_lib/binding.py → dot_claude/skills/qa-test-plan/scripts/qa_artifacts_lib/models.py
- `validate_plan()` --calls--> `load_plan()`  [INFERRED]
  dot_claude/skills/qa-test-plan/scripts/executable_qa_artifacts.py → dot_claude/skills/qa-test-plan/scripts/qa_artifacts_lib/binding.py
- `render_plan()` --calls--> `load_plan()`  [INFERRED]
  dot_claude/skills/qa-test-plan/scripts/executable_qa_artifacts.py → dot_claude/skills/qa-test-plan/scripts/qa_artifacts_lib/binding.py
- `validate_results()` --calls--> `bind_run()`  [INFERRED]
  dot_claude/skills/qa-test-plan/scripts/executable_qa_artifacts.py → dot_claude/skills/qa-test-plan/scripts/qa_artifacts_lib/binding.py
- `validate_results()` --calls--> `load_plan()`  [INFERRED]
  dot_claude/skills/qa-test-plan/scripts/executable_qa_artifacts.py → dot_claude/skills/qa-test-plan/scripts/qa_artifacts_lib/binding.py

## Communities (27 total, 5 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.2
Nodes (13): bind_run(), load_plan(), load_results(), Parse a QA plan and reject invalid or dangling references., Render human-readable Markdown from the structured QA plan., Parse results and prove complete scenario/step coverage against the plan., Render HTML, WebVTT captions, and annotated screenshots from a bound run., Write versioned JSON Schemas for QA plan and results contracts. (+5 more)

### Community 1 - "Community 1"
Cohesion: 0.51
Nodes (15): BoundRun, Persona, QAPlan, QAScenario, QAStep, Requirement, ResultStatus, ScenarioResult (+7 more)

### Community 2 - "Community 2"
Cohesion: 0.22
Nodes (8): captureConfig(), captureGlob(), captureNormalize(), captureParseArray(), capturePolicy(), captureTool(), captureTrimComment(), readFileSync()

### Community 3 - "Community 3"
Cohesion: 0.29
Nodes (12): _annotate_screenshot(), _build_scenario_views(), _build_step_view(), _overall_status(), render_plan(), render_report(), _requirement_views(), _status_color() (+4 more)

### Community 4 - "Community 4"
Cohesion: 0.27
Nodes (8): CapturePolicy, references_exist(), _require_known(), _require_unique(), run_is_consistent(), scenario_is_consistent(), ScreenshotPolicy, StrEnum

### Community 5 - "Community 5"
Cohesion: 0.33
Nodes (6): BaseModel, EvidencePolicy, FrozenModel, HighlightBox, QAEnvironment, QAResults

### Community 6 - "Community 6"
Cohesion: 0.47
Nodes (6): cwdFor(), endSession(), postHook(), postPreCompact(), rememberCwd(), startSession()

### Community 7 - "Community 7"
Cohesion: 0.5
Nodes (5): authHeaders(), drainHookQueue(), fetchHandoff(), sleep(), timeoutSignal()

### Community 8 - "Community 8"
Cohesion: 0.4
Nodes (5): applyMarkerParams(), findMarker(), repoRootProject(), tomlFlag(), tomlKey()

### Community 9 - "Community 9"
Cohesion: 0.4
Nodes (5): disposeDrainTimeout(), drainHookQueueForDispose(), enqueueHook(), requestHookDrain(), scheduleHookFlush()

## Knowledge Gaps
- **5 isolated node(s):** `Parse a QA plan and reject invalid or dangling references.`, `Render human-readable Markdown from the structured QA plan.`, `Parse results and prove complete scenario/step coverage against the plan.`, `Render HTML, WebVTT captions, and annotated screenshots from a bound run.`, `Write versioned JSON Schemas for QA plan and results contracts.`
  These have ≤1 connection - possible missing edges or undocumented components.
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `BoundRun` connect `Community 1` to `Community 0`, `Community 4`?**
  _High betweenness centrality (0.095) - this node is a cross-community bridge._
- **Why does `bind_run()` connect `Community 0` to `Community 1`?**
  _High betweenness centrality (0.087) - this node is a cross-community bridge._
- **Are the 9 inferred relationships involving `StepView` (e.g. with `ResultStatus` and `Requirement`) actually correct?**
  _`StepView` has 9 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `ScenarioView` (e.g. with `ResultStatus` and `Requirement`) actually correct?**
  _`ScenarioView` has 9 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `RequirementView` (e.g. with `ResultStatus` and `Requirement`) actually correct?**
  _`RequirementView` has 9 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `ReportView` (e.g. with `ResultStatus` and `Requirement`) actually correct?**
  _`ReportView` has 9 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Parse a QA plan and reject invalid or dangling references.`, `Render human-readable Markdown from the structured QA plan.`, `Parse results and prove complete scenario/step coverage against the plan.` to the rest of the system?**
  _5 weakly-connected nodes found - possible documentation gaps or missing edges._