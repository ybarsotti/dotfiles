---
description: Execute an approved QA plan against an exact commit and produce captioned visual evidence plus HTML report
---

# /qa-execute

Replay approved manual QA contract with `agent-browser` against exact deployed commit. Produce
structured results, raw scenario videos, WebVTT captions, raw and annotated screenshots, and HTML.

**Arguments:** `$ARGUMENTS`

```text
/qa-execute --qa-plan PATH --url URL [--commit SHA] [--slug NAME] [--output-dir PATH] [--dry-run]
```

Invoke `qa-test-plan` skill with `--phase execute` plus supplied arguments. Follow skill exactly;
do not drive browser inline.

Examples:

```bash
/qa-execute --qa-plan ./qa/qa-plan.yaml --url https://b2b-feature.filterbuy.dev
/qa-execute --qa-plan ./qa/qa-plan.yaml --url https://b2b.filterbuy.local --commit "$(git rev-parse HEAD)"
/qa-execute --qa-plan ./qa/qa-plan.yaml --url https://b2b.filterbuy.local --dry-run
```
