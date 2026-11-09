---
name: workflow-mode
description: Choose the workflow mode (fast or standard) of a task in a repository that has `.workflow/config.json`, and write the task's `workflow.md`. Use before the first code of a task in such a repository, when another workflow stage finds no `workflow.md`, or when the user asks which mode a task needs. Recommends a mode with the reason, lets the user confirm it, and records the decision.
---

# workflow-mode

This stage chooses the mode of one task and writes `workflow.md`. It does no review.

## 1. Check the repository

If `.workflow/config.json` does not exist, say "This repository has no workflow:
`.workflow/config.json` is missing." and stop.

Run the shared commands of `~/.claude/skills/_shared/workflow-artifacts.md`. Read only its
sections "Where the artifacts live", "Shared commands", "Field rules" and the `workflow.md`
examples.

When `$TASK_DIR/workflow.md` already exists, show its mode. Ask the user with
`AskUserQuestion` whether to keep it. To change it, append a new decision with `id: "mode"`.
The verifier reads the last one. Do not delete the earlier decision.

## 2. Recommend a mode

Read `.workflow/modes.md`. It is the rule of this repository. When it differs from the summary
below, follow `modes.md`.

- **Standard**: the task touches business behavior, permissions, migrations, an integration
  with an external system, or its scope is unclear.
- **Fast**: any other narrow change.

Find the files that the task will touch: the ticket, the plan, or the user's request. Read the
active rules in the folders that `.workflow/config.json` names. Note each active rule whose
`paths` match those files. A match with a `kind: business` rule is a reason for standard.

## 3. Ask the user

Call `AskUserQuestion` with two options. Put the recommended mode first, with "(Recommended)"
after its label. Each option's description gives the reason in one sentence, with the
evidence: the file, the rule id or the ticket line.

## 4. Write `workflow.md`

Write `$TASK_DIR/workflow.md` with the fields of the example for the chosen mode:

- `stage: "workflow"`, `task` (the branch), `ran_at` (UTC, ISO 8601), `mode`.
- `decisions`: one decision `{"id": "mode", "summary": "<mode>: <reason>", "status":
  "decided", "choice": "<mode>"}`.
- Fast only: `business_rules`. Set `review` when an active business rule matches the files the
  task touches. Otherwise set `skip`, with `business_reason` that states why no business rule
  applies. `workflow-finish` adds the checks and the hash later.
- Do not set `base_commit`.

Run the verifier with `--through post-plan --enforcement advisory`. At this stage expect only
`MISSING_ARTIFACT`, `MISSING_CHECK`, `STALE_DIFF_HASH` and `RULE_NOT_COVERED`. A later stage
fixes them. Fix any other code now, such as `MODE_MISMATCH` or `BAD_FRONTMATTER`.

## Next

- Standard: plan the task with `/simple-plan` or `/deep-plan`, when no plan exists yet. After
  the user approves the plan: `Next: Skill(skill="workflow-post-plan")`
- Fast: implement the task, commit it and run its tests. Then:
  `Next: Skill(skill="workflow-finish")`
