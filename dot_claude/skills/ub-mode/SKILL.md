---
name: ub-mode
description: >
  Follow the reduced principles when writing or changing code. Every change
  follows First Make it Work, then Then Make it Right, then Follow Practice.
  Use when the user runs /ub-mode or asks for the reduced principles, and when
  a planning, build or review skill says to apply ub-mode.
---

<!-- From https://github.com/unclebob/ub-mode (MIT license, Copyright Robert C. Martin; see
     LICENSE). Local changes: the last sentence of the description, and "This machine" at the
     end. The rest is the upstream text. -->

# ub-mode

Every time you are asked to make a change follow:
* First Make it Work.
* Then Make it Right.
* Follow Practice

# First Make it Work

## Laziness Protocol

* One decision lives in one place.
* Ship the smallest edit that solves the problem.

## Foundational Thinking

* Get the data shape right before you write the logic.
* Do first whatever helps every later phase.
* If a concurrent writer would matter, do not share state.

## TDD

* Write the failing test before you change the code.
* See it fail for the reason you expect.
* Make the smallest change that makes it pass.
* If an honest test is impractical, do not write a bad one.

## Redesign From First Principles

* Do not bolt a new requirement onto the old design.
* Ask what you would have built if it had been there from the start, think that through, and deliver it in pieces.

## Attack the Premise

* When two fixes that share one premise fail the same gate, write that premise in one sentence and count which actors hold the imbalance.
* Remove the assignment.
* Do not start another fix until you have done that.

## Subtract Before You Add

* Take complexity out before you add anything.

## Outcome-Oriented Execution

* Aim at the end state you can check.
* A break in the middle is allowed when you planned it and can undo it.

## Build the Lever

* If the work is not obvious at a glance, build the tool that does it.
* Do one unit by hand, then make the tool match that unit.

## Architecture

### Model the Domain

* Put the domain in a structure that makes the illegal states impossible.
* Maintain a glossary of domain terms.
* If the code is already clear and local, leave it.

### Boundary Discipline

* Check the data where it enters.
* Inside, trust it.
* Keep the business logic in a pure function.

### Type System Discipline

* Make the illegal value impossible to write.
* Parse outside data once, where it comes in.
* Do not silence the compiler.

### Make Operations Idempotent

* Running it twice, or running it after a crash halfway through, ends in the same state.

### Separate Before Serializing Shared State

* If they do not need the same mutable thing, give each its own.
* If they do, allow one writer, and enforce that in the structure.

# Then Make it Right

## Fix Root Causes

* Reproduce it.
* Fix the cause.
* A guard that only hides the crash is not a fix.

## Sequence work into verifiable units

* Finish one small unit and check it.
* Then start the next.

## Test Behavior, Not Implementation

* The test calls the code the way its user does and checks the result that user would see.
* If the test would still pass when every function returned nothing, throw it out.

## Crapper

* Use the crapper tool
* Reduce each function under  CRAP 10 by splitting it, by testing it, or both.
* Consider whether case statements are worth reducing.

## Dryer

* Use the dryer tool to eliminate duplication that rank 0.8 or above.

## Mutator

* Use the mutator tool
* Cover the uncovered.
* Kill the survivors.
* Delete dead code.

## Refactoring

* Pin what the code does.
* Change the structure.
* Prove the behavior did not change.

# Practice

## Keep a Log

* Keep a log of every action you take and the reason you took it.
* Report that log upon completion.

## Guard the Context Window

* Keep the main thread small.
* Send the bulk elsewhere, and keep the summary.

## Worktree Cleanup

* Find what is safe to remove, confirm nothing still in use needs it, then reclaim the disk.
* Uncommitted work waits for a decision.

## Commit and Push

* Commit often, in small ordered commits.
* Each commit says why, what changed, and how you proved it.
* Push to the main line at the end.

# This machine

The local section. It does not change a rule above. It says how to run the tools here.

## Tools

`crapper`, `dryer` and `mutator` are on the `PATH`. Each runs from a pinned checkout in
`~/.local/share/unclebob/` (see `.chezmoiexternal.toml` in the dotfiles). The first run of
each tool creates its `.venv`. Run each tool from the project root.

| Tool | Command for the current change | Gate |
|---|---|---|
| crapper | `crapper --changed`, or `crapper <files>` | Each function under CRAP 10. `--threshold 10` exits 2 above it. |
| dryer | `dryer --changed`, or `dryer <files or trees>` | No pair at 0.8 or above. Pass `--threshold 0.8`; the default is 0.82. |
| mutator | `mutator <file>`, or `mutator --changed` | No `SURVIVED` and no `UNCOVERED` line. Exit 3 means a mutant survived. |

- crapper and mutator measure coverage with the project's own test tool. For Python, the
  project needs a virtualenv that has `pytest` and `coverage`. Without them, the coverage is
  0% and every CRAP score is too high. `crapper --no-coverage` gives only the complexity.
- CRAP is never lower than the cyclomatic complexity. A function with a complexity of 10 or
  more fails the gate at any coverage.
- mutator runs the tests once for each mutant. Start with the file you changed, not the tree.
  Cap the workers with `--max-workers 2` when other sessions share the machine.
### Where the gates run

Tests run in CI, not on this machine. A gate that runs the tests follows that rule.

- **Locally**, run only the gates that do not run tests: `crapper --no-coverage --threshold 10`
  (complexity) and `dryer --threshold 0.8`, on the changed files.
- **In CI**: `mutator` and `crapper` with coverage. When the project's CI has a job for them
  (for example `just mutate`), read its result on the PR with `gh pr checks`, and treat a red
  job like a failing test. When the CI has no such job, do not run them locally. Record the
  line "mutation and coverage CRAP gates: not in CI" in the open items of the run report and
  in the verification of the PR.
- Run `mutator` or `crapper` with coverage locally only when the user asks for it.

- The tools write `.metrics/` in the project, and mutator writes `target/`. The global git
  ignore file ignores `.metrics/`. Commit it only when the project already tracks it.

## Precedence

- The project's rules win over "Commit and Push". Where the project works through pull
  requests, push the branch and open the pull request. Do not push to the main line.
- "Keep a Log": put the log in the final report of the task.
