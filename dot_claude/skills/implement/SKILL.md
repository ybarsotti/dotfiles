---
name: implement
description: Use when invoked via /implement, or when the user asks to build an approved serial plan, PRD or issue set in this session. Builds under strict TDD, commits, then runs the shared after-approval chain (review, QA, PR). For a parallel plan use deep-execute.
---

# implement

Build the work that the approved plan, the PRD or the issues describe. This skill only
builds. Review, QA, the PR and the report belong to `~/.claude/skills/_shared/after-approval.md`.

## Input

- The approved plan path (`$PLAN`), or the PRD or the issues that the user gave.
- The current branch. Commit to it. Do not create a new branch.

## Before the first task

Run section 0 of `after-approval.md`: open `/goal` with the finished result "built, reviewed,
QA green, PR open, report delivered". The goal keeps the session going after the last commit.
This applies when `/implement` is the first command too.

Find the step file. The plan header names it (`**Step file:**`). When the plan has none,
create it in a new run folder:
`RUN_DIR=~/.claude/implement-runs/$(date +%Y%m%d-%H%M%S)`, then
`~/.claude/skills/_shared/workflow.sh init "$RUN_DIR/chain.md" implement --plan "$PLAN"`.
The Stop hook trusts only step files under `~/.claude/*-runs/`.
Add one `build.<n>` row per task, in order: `workflow.sh add <file> build.<n> "<task>" --after build`.

## Build

1. Read the plan. Take its tasks in order. When the plan has no tasks, split the work into
   small tasks first, ordered from the foundation up.
2. Start one implementer worker per task, as `~/.claude/skills/_shared/orca-workers.md`
   describes. Run its three checks before the first task, and print the mode line it names.
   In Orca, each task runs as an Orca worker in its own pane. This session reviews each task.
   It writes feature code only when the user asks for that.
   In the subagent mode, run this loop per task: start the predefined implementer agent with
   the `Agent` tool, read its diff, run the task's tests and gates, send a fix back with
   `SendMessage` when one fails, then commit. When the harness has no subagent tool, build the
   task in this session with the same steps. Do not use `superpowers:subagent-driven-development`,
   `superpowers:executing-plans` or `superpowers:finishing-a-development-branch`: they stop to
   ask, and the chain of `after-approval.md` replaces them.
3. Invoke the `ub-mode` skill and build by it. Tell each implementer worker to invoke it too,
   or to read `~/.claude/skills/ub-mode/SKILL.md`. Before each commit, run its local gates on the
   changed files: `crapper --changed --no-coverage --threshold 10` and
   `dryer --changed --threshold 0.8`. `mutator` and coverage CRAP run in CI, as "Where the
   gates run" in the `ub-mode` skill says. Build each task with
   strict TDD: `superpowers:test-driven-development`, or the `tdd` skill when it is installed. Write the tests at the seams that the plan agreed. Mock only
   the outermost boundaries: the network, a third-party API, the clock.
4. For a bug or a regression, use `superpowers:systematic-debugging` before you write the fix.
5. Record each departure from the plan as a `D-NNN` row under the plan's `## Deviations`.
   When the plan has a UI design pass, check each screen as soon as it renders, as section 4
   of `after-approval.md` says. The next task that touches a screen waits for its `MATCH`.
6. After each task, read its diff and run its tests and the gates of step 3. Then commit.
   Mark its row: `workflow.sh done <file> build.<n> "<commit sha>: <test command and result>"`.
   Run `workflow.sh status <file>` and tell the user what is done, what is next and what is
   left. The panel review runs once, in section 2 of `after-approval.md`.

## Test

- Run only the focused tests of the change locally, through `~/.local/bin/test-local`: the
  TDD test of each task and the test files of the changed code. Run the type checker on the
  changed files.
- Do not run the full suite locally. CI runs it on the PR, and the `/ship-it` watch fixes a red
  check. Run it locally only when the user asks.
- Do not weaken a test, a lint rule or a threshold to get to green.

## Commit

Commit each reviewed task to the current branch with a Conventional Commit message. Do not
skip the hooks.

## Next

The last commit is not the end. Mark the `build` step done. In the same turn, continue with
sections 2 to 8 of `~/.claude/skills/_shared/after-approval.md`: the final `/deep-review` with
its full process, QA, the fixes, the demo, the report, and the PR with its watch. Do not stop to report the build, and do not ask whether to continue. Stop only
in the cases that `after-approval.md` lists. Do not run a review, QA or PR flow of your own.
