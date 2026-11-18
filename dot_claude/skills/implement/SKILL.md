---
name: implement
description: Single-session executor for an approved plan, a PRD or a set of issues. Use when the plan routing picks option B (a serial plan, one lane, or no declared execution shape), when invoked via /implement, or when the user asks to implement, build or execute an approved plan in this session. Builds task by task under strict TDD, runs the narrow tests often and the full suite once, commits to the current branch, then hands off to the shared after-approval chain for review, QA and the PR.
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

## Build

1. Read the plan. Take its tasks in order. When the plan has no tasks, split the work into
   small tasks first, ordered from the foundation up.
2. Start one implementer worker per task, as `~/.claude/skills/_shared/orca-workers.md`
   describes: an Orca worker when the session runs in Orca, else a subagent. This session
   reviews each task. It writes feature code only when the user asks for that.
   In the subagent mode, use the per-task loop of `superpowers:subagent-driven-development`,
   or `superpowers:executing-plans` without subagents. Skip their last step,
   `superpowers:finishing-a-development-branch`: it asks to merge, open a PR or keep the
   branch, and waits. Sections 2 to 9 of `after-approval.md` replace it.
3. Invoke the `ub-mode` skill and build by it. Tell each implementer worker to invoke it too,
   or to read `~/.claude/skills/ub-mode/SKILL.md`. Before each commit, run its gates on the
   changed files: `crapper --changed --threshold 10`, `dryer --changed --threshold 0.8`, and
   `mutator --max-workers 2 <file>` for each changed source file. Build each task with
   strict TDD: `superpowers:test-driven-development`, or the `tdd` skill when it is installed. Write the tests at the seams that the plan agreed. Mock only
   the outermost boundaries: the network, a third-party API, the clock.
4. For a bug or a regression, use `superpowers:systematic-debugging` before you write the fix.
5. Record each departure from the plan as a `D-NNN` row under the plan's `## Deviations`.
6. After each task, read its diff and run its tests and the gates of step 3. Then commit.
   The panel review runs once, in section 2 of `after-approval.md`.

## Test

- Run the type checker and the single test files of the changed code often.
- Run the full test suite once, at the end. Cap the workers: `jest --maxWorkers=2`,
  `vitest --maxWorkers=2`, `pytest -n 2`. Run one full suite at a time.
- Do not weaken a test, a lint rule or a threshold to get to green.

## Commit

Commit each reviewed task to the current branch with a Conventional Commit message. Do not
skip the hooks.

## Next

The last commit is not the end. In the same turn, continue with sections 2 to 9 of
`~/.claude/skills/_shared/after-approval.md`: the review, QA, the fixes, the PR, the report and
the PR watch. Do not stop to report the build, and do not ask whether to continue. Stop only
in the cases that `after-approval.md` lists. Do not run a review, QA or PR flow of your own.
