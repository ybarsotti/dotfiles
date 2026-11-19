# Phase 1.5 breakdown agent and file format

This file belongs to `simple-plan`. `SKILL.md` names the step that needs it.

Dispatch **one** agent to split it. That agent does not plan and does not write code. Give it
`$RUN_DIR/context.md` and `~/.claude/skills/simple-plan/references/constraints.md`, and require an
ordered list where:

- **Each task ships on its own.** A person can exercise it and say whether it works. A task
  that cannot be validated alone is merged into the one that makes it validatable.
- **Each names the observable outcome** that proves it is done — what a reviewer sees, not
  what the code does.
- **The first task is the foundation** the rest build on: the schema, the type, the contract,
  the seam. Later tasks depend only on earlier ones.
- **The list holds 2 to 6 tasks.** More than six means the split is still too coarse; tell the
  agent to group them.

The agent writes the list to `$RUN_DIR/breakdown.md` in exactly this shape, so the next step
can parse it:

```markdown
## Task 1 — <short title>
- **Delivers:** <the observable outcome a person can check>
- **Validated by:** <what someone does to confirm it, in one sentence>
- **Touches:** <paths or directories>
- **Depends on:** none

## Task 2 — <short title>
- **Delivers:** ...
- **Validated by:** ...
- **Touches:** ...
- **Depends on:** Task 1
```

When the user chooses stages (below), each task also carries `- **Class:** light|full`,
`- **Status:** planned` and `- **Commit:** -`, and the file follows
`~/.claude/skills/_shared/stages.md`.

Task 1 depends on nothing. Every later task depends only on earlier ones.
