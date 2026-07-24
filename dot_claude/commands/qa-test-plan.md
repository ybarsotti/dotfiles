---
description: Map manual QA, review contract, execute it with agent-browser, and render captioned visual evidence in HTML
---

# /qa-test-plan

Run both QA phases: create reviewed structured plan, then execute it against running app and
produce commit-bound evidence report.

**Arguments:** `$ARGUMENTS`

```text
/qa-test-plan [--phase plan|execute|all] [--plan PATH] [--qa-plan PATH]
              [--url URL] [--ticket KEY-123] [--slug NAME]
              [--output-dir PATH] [--commit SHA] [--no-exec] [--dry-run]
```

Invoke `qa-test-plan` skill. Do not map flow, review contract, drive browser, or render report
inline. `--no-exec` remains compatibility alias for `--phase plan`.

Examples:

```bash
/qa-test-plan --plan ./plan.md --url https://b2b.filterbuy.local
/qa-test-plan --phase plan --plan ./plan.md --ticket FBIT-1234
/qa-test-plan --phase execute --qa-plan ./qa/qa-plan.yaml --url https://b2b.filterbuy.local
/qa-test-plan --plan ./plan.md --url https://b2b.filterbuy.local --dry-run
```
