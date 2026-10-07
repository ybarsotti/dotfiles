---
name: qa-plan
description: Turn an approved implementation plan into a reviewed, validated manual QA contract before any code is written. Use when invoked via /qa-plan, or when the user wants the QA criteria agreed up front — "what should QA check", "write the test plan", "QA plan for this feature" — so the implementer knows what will be verified instead of QA inventing criteria from finished code. Produces qa-plan.yaml plus a human-readable qa-plan.md. Does not launch a browser and does not execute anything.
---

# qa-plan

This is the planning phase of `qa-test-plan`, nothing more. The whole workflow lives there;
duplicating it here would give two copies that drift.

Invoke it with the plan phase:

```
Skill(skill="qa-test-plan")
```

and pass `--phase plan` plus whatever the user supplied:

```text
--plan PATH [--ticket KEY-123] [--slug NAME] [--output-dir PATH] [--dry-run]
```

Follow that skill exactly. Do not map the flow inline, and do not launch a browser — this
phase only writes the contract. Execution is `qa-execute`, and it runs after implementation
against a frozen commit.

`--plan PATH` is required: without the plan there are no requirements to map.
