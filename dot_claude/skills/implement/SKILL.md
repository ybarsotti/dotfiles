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

## Build

1. Read the plan. Take its tasks in order. When the plan has no tasks, split the work into
   small tasks first, ordered from the foundation up.
2. Dispatch one implementer agent per task with `superpowers:subagent-driven-development`.
   This session reviews each task. It writes feature code only when the user asks for that.
   Without subagents, use `superpowers:executing-plans`.
3. Build each task with strict TDD: `superpowers:test-driven-development`, or the `tdd`
   skill when it is installed. Write the tests at the seams that the plan agreed. Mock only
   the outermost boundaries: the network, a third-party API, the clock.
4. For a bug or a regression, use `superpowers:systematic-debugging` before you write the fix.
5. Record each departure from the plan as a `D-NNN` row under the plan's `## Deviations`.
6. After each task, run the part review of `after-approval.md` section 1. Then commit.

## Test

- Run the type checker and the single test files of the changed code often.
- Run the full test suite once, at the end. Cap the workers: `jest --maxWorkers=2`,
  `vitest --maxWorkers=2`, `pytest -n 2`. Run one full suite at a time.
- Do not weaken a test, a lint rule or a threshold to get to green.

## Commit

Commit each reviewed task to the current branch with a Conventional Commit message. Do not
skip the hooks.

## Next

Continue with sections 2 to 9 of `~/.claude/skills/_shared/after-approval.md`. Do not run a
review, QA or PR flow of your own.
