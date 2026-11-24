# The repository's own workflow comes first

Some repositories define their own development workflow: stages for planning, plan review,
code review, verification and the PR. When a repository has one, it owns each stage that it
covers. This chain adds only the stages that the repository workflow does not have. Two
review systems on one change double the time and find the same things.

## 1. Find it

Read these before the plan is drafted. Stop at the first that defines stages:

1. The project instructions: `CLAUDE.md`, `AGENTS.md`, `CLAUDE.local.md`, and the files they
   import. Look for a section that names workflow stages, modes or required gates.
2. A workflow config folder at the repository root: a dot-folder or folder whose name contains
   `workflow`, with a config file (`config.yaml`, `config.json`) and stage or mode files.
3. The project skills in `.claude/skills/` and `.agents/skills/`: skills whose descriptions
   name a stage of a task (start, plan review, execute, post-implementation, finish, PR).
4. Required CI checks that verify workflow records (a check that reads plan or review files).

Our own `.workflow/config.json` (from the project template) is one such workflow. Its stages
are the `workflow-*` skills.

## 2. Map the stages

Write one table in `$RUN_DIR/decisions.md`: each step of this chain, and the repository
stage that covers it, or `none`.

| Chain step | Covered when the repository workflow has |
|---|---|
| plan review (`plan-reviewer`, deep-plan Phase 2) | a stage that reviews the plan |
| `/deep-review` and the `/simplify` pass | a stage that reviews the code |
| `blindspot` on the PR body | a stage that checks claims before the PR |
| the codex review of `/ship-it` | a stage that reviews the PR text or the PR |
| CI watch and repair | a stage that watches and repairs CI |

The repository workflow sets the mode, the stage order and the records. Follow its rules for
choosing a mode, and use its lightest mode when its rules allow it.

## 3. Run

- For each covered step, run the repository stage, and mark the chain step with
  `workflow.sh done <file> <id> "<the record of that stage>"`. The `review` step cannot be
  skipped, so its evidence is the record of the repository's code review stage.
- Run each step marked `none` as this chain describes. These usually stay: the build
  under TDD, `qa-ui`, `qa-business` (their recordings are the real-flow evidence that a
  verification stage asks for), the demo of a user feature, the report, and the PR body of
  `/ship-it`.
- When a repository stage and a chain step disagree, the repository stage wins.
- The user can still ask for any skipped step by name.
