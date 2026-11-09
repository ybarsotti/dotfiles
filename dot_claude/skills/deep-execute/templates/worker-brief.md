# Lane {{LANE}}

You are the `{{LANE}}` lane worker of a `/deep-execute` run. The rules in your system prompt
apply on every turn. This brief says what this lane builds.

## Run

- Run directory (`RUN_DIR`): `{{RUN_DIR}}`
- Worktree: `{{CWD}}`
- Approved plan: `{{PLAN}}`
- Subplan of this lane: {{SUBPLAN}}
- Report an event: `{{EVENT_SH}} {{RUN_DIR}} {{LANE}} "<task>" <type> "<message>" [--files PATH...]`
- Read the run state: `{{BOARD_SH}} {{RUN_DIR}} [--lane LANE]`
- Record a decision: `{{DECISION_SH}} {{RUN_DIR}} {{LANE}} "<task>" --title "<line>" --rationale "<why>"`

## Scope

{{SCOPE}}

- Owns (write only here): {{OWNS}}
- Must not touch: {{MUST_NOT_TOUCH}}
- Starts after these lanes are done: {{DEPENDS_ON}}
- Lane test command (`test_command`): `{{TEST_COMMAND}}`

## Contract

- `{{CONTRACT_PATH}}`, version `{{CONTRACT_VERSION}}`, kind `{{CONTRACT_KIND}}`. It is read-only.
- Other read-only files: {{SHARED}}

## Tasks

Use each label below, exactly as written, as `<task>` in every event about that task.

{{TASKS}}

## How to build each task (TDD)

1. Emit `task_start`.
2. Write the failing test first. Run it and see it fail for the expected reason.
3. Write the least code that makes the test pass.
4. Run the lane test command. Refactor while it stays green.
5. Log every path you wrote with `--files`, then emit `task_done`.

When every task is done and the lane test command passes, emit `done` and stop. The loop keeps
your session. The orchestrator sends the next instruction as a reply, which starts your next turn.
