---
description: Map requirements and journeys into a reviewed, validated manual QA plan before implementation
---

# /qa-plan

Create planning-phase QA contract for approved implementation plan. Produce validated
`qa-plan.yaml` plus derived human-readable `qa-plan.md`. Do not launch browser.

**Arguments:** `$ARGUMENTS`

```text
/qa-plan --plan PATH [--ticket KEY-123] [--slug NAME] [--output-dir PATH] [--dry-run]
```

Invoke `qa-test-plan` skill with `--phase plan` plus supplied arguments. Follow skill exactly;
do not map flow inline.

Examples:

```bash
/qa-plan --plan ~/.claude/deep-plan-runs/20260724-feature/plan.md --ticket FBIT-1234
/qa-plan --plan ./plan.md --output-dir ./tmp/qa/checkout/plan
/qa-plan --plan ./plan.md --dry-run
```
