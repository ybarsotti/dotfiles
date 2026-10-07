---
name: qa-execute
description: Replay an approved QA contract against a deployed commit with agent-browser and produce evidence. Use when invoked via /qa-execute, or when the user wants a feature verified in a live environment — "run the QA plan", "test this against staging", "produce QA evidence for the PR". Yields structured results, scenario videos, WebVTT captions, raw and annotated screenshots, and an HTML report tied to the exact commit tested.
---

# qa-execute

This is the execute phase of `qa-test-plan`, nothing more. The whole workflow lives there;
duplicating it here would give two copies that drift.

Invoke it with the execute phase:

```
Skill(skill="qa-test-plan")
```

and pass `--phase execute` plus whatever the user supplied:

```text
--qa-plan PATH --url URL [--commit SHA] [--slug NAME] [--output-dir PATH] [--dry-run]
```

Follow that skill exactly. Do not drive the browser inline.

`--qa-plan PATH` and `--url URL` are both required. Pass `--commit` whenever you can: a result
that does not name the commit it tested cannot be trusted later, because the code moves.

When QA finds failures, a **different** agent fixes them and QA re-runs on the fix. The agent
that tested does not grade its own repair.
