# Graph Report - chezmoi  (2026-08-13)

## Corpus Check
- 22 files · ~99,306 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 145 nodes · 263 edges · 23 communities (18 shown, 5 thin omitted)
- Extraction: 76% EXTRACTED · 24% INFERRED · 0% AMBIGUOUS · INFERRED: 63 edges (avg confidence: 0.54)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `2fc7397d`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Code Structure|Code Structure]]
- [[_COMMUNITY_Code Structure|Code Structure]]
- [[_COMMUNITY_Code Structure|Code Structure]]
- [[_COMMUNITY_Code Structure|Code Structure]]
- [[_COMMUNITY_Code Structure|Code Structure]]
- [[_COMMUNITY_Code Structure|Code Structure]]
- [[_COMMUNITY_Code Structure|Code Structure]]
- [[_COMMUNITY_Code Structure|Code Structure]]
- [[_COMMUNITY_Code Structure|Code Structure]]
- [[_COMMUNITY_Code Structure|Code Structure]]

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

## Communities (23 total, 5 thin omitted)

### Community 0 - "Code Structure"
Cohesion: 0.11
Nodes (29): applyMarkerParams(), authHeaders(), captureConfig(), captureGlob(), captureNormalize(), captureParseArray(), capturePolicy(), captureTool() (+21 more)

### Community 1 - "Code Structure"
Cohesion: 0.19
Nodes (29): BaseModel, BoundRun, CapturePolicy, EvidencePolicy, FrozenModel, HighlightBox, Persona, QAEnvironment (+21 more)

### Community 2 - "Code Structure"
Cohesion: 0.14
Nodes (15): BaseHTTPRequestHandler, build_snapshot(), Handler, _invalid(), list_runs(), parse_event(), Read every event, plus the streaming lane-status fold.      board.sh:56-64 group, Every decision record a lane wrote, oldest id first.      Absence here is meanin (+7 more)

### Community 3 - "Code Structure"
Cohesion: 0.2
Nodes (13): bind_run(), load_plan(), load_results(), Parse a QA plan and reject invalid or dangling references., Render human-readable Markdown from the structured QA plan., Parse results and prove complete scenario/step coverage against the plan., Render HTML, WebVTT captions, and annotated screenshots from a bound run., Write versioned JSON Schemas for QA plan and results contracts. (+5 more)

### Community 4 - "Code Structure"
Cohesion: 0.29
Nodes (12): _annotate_screenshot(), _build_scenario_views(), _build_step_view(), _overall_status(), render_plan(), render_report(), _requirement_views(), _status_color() (+4 more)

## Knowledge Gaps
- **11 isolated node(s):** `Parse a QA plan and reject invalid or dangling references.`, `Render human-readable Markdown from the structured QA plan.`, `Parse results and prove complete scenario/step coverage against the plan.`, `Render HTML, WebVTT captions, and annotated screenshots from a bound run.`, `Write versioned JSON Schemas for QA plan and results contracts.` (+6 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `BoundRun` connect `Code Structure` to `Code Structure`?**
  _High betweenness centrality (0.067) - this node is a cross-community bridge._
- **Why does `bind_run()` connect `Code Structure` to `Code Structure`?**
  _High betweenness centrality (0.061) - this node is a cross-community bridge._
- **Are the 9 inferred relationships involving `StepView` (e.g. with `BoundRun` and `Persona`) actually correct?**
  _`StepView` has 9 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `ScenarioView` (e.g. with `BoundRun` and `Persona`) actually correct?**
  _`ScenarioView` has 9 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `RequirementView` (e.g. with `BoundRun` and `Persona`) actually correct?**
  _`RequirementView` has 9 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `ReportView` (e.g. with `BoundRun` and `Persona`) actually correct?**
  _`ReportView` has 9 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Parse a QA plan and reject invalid or dangling references.`, `Render human-readable Markdown from the structured QA plan.`, `Parse results and prove complete scenario/step coverage against the plan.` to the rest of the system?**
  _11 weakly-connected nodes found - possible documentation gaps or missing edges._
