# Subplan: {{CHAPTER}}

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
- [ ] mermaid-present
- [ ] mermaid-has-entry-and-exit
- [ ] tdd-list-≥3
- [ ] edges-≥4
- [ ] no-tbd-placeholders
