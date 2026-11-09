# Graph Report - chezmoi  (2026-11-09)

## Corpus Check
- 44 files · ~251,127 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 240 nodes · 409 edges · 37 communities (31 shown, 6 thin omitted)
- Extraction: 84% EXTRACTED · 16% INFERRED · 0% AMBIGUOUS · INFERRED: 67 edges (avg confidence: 0.56)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `263fadc3`
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
- [[_COMMUNITY_Code Structure|Code Structure]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]

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
- `markdown()` --calls--> `label()`  [INFERRED]
  docs/skills-map.mjs → dot_claude/skills/video-demo/assets/template/src/scenes/Compare.tsx
- `bind_run()` --calls--> `BoundRun`  [INFERRED]
  dot_claude/skills/qa-test-plan/scripts/qa_artifacts_lib/binding.py → dot_claude/skills/qa-test-plan/scripts/qa_artifacts_lib/models.py
- `edges()` --calls--> `extractEdges()`  [INFERRED]
  docs/skills-map.test.mjs → docs/skills-map.mjs
- `validate_plan()` --calls--> `load_plan()`  [INFERRED]
  dot_claude/skills/qa-test-plan/scripts/executable_qa_artifacts.py → dot_claude/skills/qa-test-plan/scripts/qa_artifacts_lib/binding.py
- `render_plan()` --calls--> `load_plan()`  [INFERRED]
  dot_claude/skills/qa-test-plan/scripts/executable_qa_artifacts.py → dot_claude/skills/qa-test-plan/scripts/qa_artifacts_lib/binding.py

## Communities (37 total, 6 thin omitted)

### Community 0 - "Code Structure"
Cohesion: 0.11
Nodes (29): applyMarkerParams(), authHeaders(), captureConfig(), captureGlob(), captureNormalize(), captureParseArray(), capturePolicy(), captureTool() (+21 more)

### Community 1 - "Code Structure"
Cohesion: 0.19
Nodes (29): BaseModel, BoundRun, CapturePolicy, EvidencePolicy, FrozenModel, HighlightBox, Persona, QAEnvironment (+21 more)

### Community 2 - "Code Structure"
Cohesion: 0.12
Nodes (15): label(), Grain(), Letterbox(), Vignette(), clipCues(), push(), clipPlayback(), findTargetBox() (+7 more)

### Community 3 - "Code Structure"
Cohesion: 0.14
Nodes (19): buildGraph(), byName(), chainDiagram(), clusterOf(), cmp(), countOfType(), exists(), extractEdges() (+11 more)

### Community 4 - "Code Structure"
Cohesion: 0.14
Nodes (15): BaseHTTPRequestHandler, build_snapshot(), Handler, _invalid(), list_runs(), parse_event(), Read every event, plus the streaming lane-status fold.      board.sh:56-64 group, Every decision record a lane wrote, oldest id first.      Absence here is meanin (+7 more)

### Community 5 - "Code Structure"
Cohesion: 0.2
Nodes (13): bind_run(), load_plan(), load_results(), Parse a QA plan and reject invalid or dangling references., Render human-readable Markdown from the structured QA plan., Parse results and prove complete scenario/step coverage against the plan., Render HTML, WebVTT captions, and annotated screenshots from a bound run., Write versioned JSON Schemas for QA plan and results contracts. (+5 more)

### Community 6 - "Code Structure"
Cohesion: 0.34
Nodes (12): bandpass_noise(), chime(), click(), ding(), envelope(), riser(), seconds(), swell() (+4 more)

### Community 7 - "Code Structure"
Cohesion: 0.29
Nodes (12): _annotate_screenshot(), _build_scenario_views(), _build_step_view(), _overall_status(), render_plan(), render_report(), _requirement_views(), _status_color() (+4 more)

### Community 8 - "Code Structure"
Cohesion: 0.36
Nodes (8): align(), edge(), eleven(), main(), merge_spelled(), plain(), seconds(), words_from_characters()

### Community 9 - "Code Structure"
Cohesion: 0.43
Nodes (7): annotate(), default_label_at(), load_font(), main(), pad(), Place a callout right of the box, else left, else above, else under (CSS px)., shift()

## Knowledge Gaps
- **13 isolated node(s):** `Parse a QA plan and reject invalid or dangling references.`, `Render human-readable Markdown from the structured QA plan.`, `Parse results and prove complete scenario/step coverage against the plan.`, `Render HTML, WebVTT captions, and annotated screenshots from a bound run.`, `Write versioned JSON Schemas for QA plan and results contracts.` (+8 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `BoundRun` connect `Code Structure` to `Code Structure`?**
  _High betweenness centrality (0.024) - this node is a cross-community bridge._
- **Why does `markdown()` connect `Code Structure` to `Code Structure`?**
  _High betweenness centrality (0.023) - this node is a cross-community bridge._
- **Why does `label()` connect `Code Structure` to `Code Structure`?**
  _High betweenness centrality (0.023) - this node is a cross-community bridge._
- **Are the 9 inferred relationships involving `StepView` (e.g. with `BoundRun` and `Persona`) actually correct?**
  _`StepView` has 9 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `ScenarioView` (e.g. with `BoundRun` and `Persona`) actually correct?**
  _`ScenarioView` has 9 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `RequirementView` (e.g. with `BoundRun` and `Persona`) actually correct?**
  _`RequirementView` has 9 INFERRED edges - model-reasoned connections that need verification._
- **Are the 9 inferred relationships involving `ReportView` (e.g. with `BoundRun` and `Persona`) actually correct?**
  _`ReportView` has 9 INFERRED edges - model-reasoned connections that need verification._
