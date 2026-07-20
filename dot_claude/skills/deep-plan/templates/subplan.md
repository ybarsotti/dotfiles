# Subplan: {{CHAPTER}}

**Lane:** `{{LANE}}`
**Mode:** `{{MODE}}`

## Contract reference
<!-- Inherited from the root plan's `## API contract`, when it declares one. Populated by
     subplan-fanout.sh — workers build against this contract rather than re-deriving it. -->
- Contract version: `{{CONTRACT_VERSION}}`
- Materialized contract: `{{CONTRACT_PATH}}`

## Context
<why this chapter exists; how it slots into the root plan>

## Files in this chapter
{{FILES}}

## Flow diagram
```mermaid
sequenceDiagram
  participant A as <entry to this chapter>
  participant B as <next hop>
  A->>B: <call>
  B-->>A: <response>
```

## Implementation tasks
<!-- Load `superpowers:writing-plans` and follow its task structure verbatim — same rules
     as the root plan. Populated by subplan-fanout.sh: every `### Task N:` block tagged for
     this lane, copied verbatim from the root plan. -->
{{TASKS}}

## TDD test list
- `<test name>` — <intent>
- `<test name>` — <intent>
- `<test name>` — <intent>

## Edge cases & failure modes
- <bullet>
- <bullet>
- <bullet>
- <bullet>

## Verification
- <how to confirm this chapter works in isolation>

## Checklist (machine-validated; do NOT hand-edit — call tick-checklist.sh --subplan)
<!-- validate-plan.sh only records the 21 execution-shape/lane-identity items (including
     tasks-tagged-with-lane, every-lane-has-1-task, lane-task-files-subset-of-lane-owns) in
     `--root` mode — a `--subplan` run never emits them, so they can never be ticked here via
     the sanctioned tick-checklist.sh path. Do not add them to this list. -->
- [ ] mermaid-present
- [ ] mermaid-has-entry-and-exit
- [ ] tasks-≥1
- [ ] tasks-have-files-and-interfaces
- [ ] tasks-have-tdd-steps
- [ ] tdd-list-≥3
- [ ] edges-≥4
- [ ] no-tbd-placeholders
