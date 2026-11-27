# Plan format

This file defines the shape of every implementation plan that `simple-plan` and `deep-plan`
write. It replaces `superpowers:writing-plans`. Do not invoke that skill: its header and its
execution handoff send the build to an executor outside this workflow.

Write the plan for an engineer who has not seen this codebase or this spec. The engineer writes
idiomatic code once they know the exact interface and the exact test. The engineer cannot know
what you decided: which files, which names and signatures, which values from the spec, and which
tests prove each task. Write those decisions down. DRY. YAGNI. TDD.

Save the plan to `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`, unless the project or
the user names another place.

## 1. Scope

When the spec covers several independent subsystems, write one plan per subsystem. Each plan
produces working, testable software on its own.

## 2. File structure

Before you write the tasks, list the files to create or change and the job of each one.

- Give each file one clear job and a clear interface.
- Prefer small, focused files. Split by job, not by technical layer.
- Keep files that change together in one place.
- In an existing codebase, follow its patterns. Split a file only when the plan already
  changes it and it has grown too large.

## 3. Task size

A task is the smallest unit that has its own test cycle and is worth its own review. Fold set-up,
configuration and documentation into the task whose result needs them. Split two tasks only when
a reviewer could reject one and approve the other. Each task ends with a result that you can test
on its own.

Each step is one action with a result that you can check: write the failing test, run it and see
it fail, write the code, run the tests and see them pass.

## 4. Header

Every plan starts with this header:

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** Build this plan with the `implement` skill, or with the executor that
> `~/.claude/skills/_shared/plan-routing.md` picks. After the build, run
> `~/.claude/skills/_shared/after-approval.md` to the end, through the final deep review and the
> PR. Track each step with `~/.claude/skills/_shared/workflow.sh` in the step file below. Do not
> use `superpowers:finishing-a-development-branch`.

**Goal:** [One sentence that says what this builds]

**Architecture:** [Two or three sentences about the approach]

**Tech Stack:** [The main technologies and libraries]

**Spec:** [The path of the spec or design that this plan implements]

**Step file:** [The absolute path of `$RUN_DIR/chain.md`]

## Global Constraints

[The project-wide requirements of the spec, one per line, with the exact values from the spec:
version floors, dependency limits, naming and copy rules, platform requirements. Every task
inherits this section.]

## Review Focus

[The five inputs or failure modes that the spec implies and no test covers yet, most likely
first. Name the input and the behavior that a person expects. Then add the test for each line
to the task that owns the code.]

---
```

## 5. Task structure

````markdown
### Task N: [Component name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Interfaces:**
- Consumes: [what this task uses from earlier tasks, with exact signatures]
- Produces: [what later tasks use: exact names, parameter types and return types]

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run the test and see it fail**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Implement `function(input: InputType) -> ResultType` in `exact/path/to/file.py`**

One line on the approach when the signature and the test leave a choice.

- [ ] **Step 4: Run the test and see it pass**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS
````

A task has no commit step. The orchestrating session reviews the diff of each task, runs its
gates and commits it. The implementer agents never commit.

## 6. What a step contains

A step is ready when the implementer can write exactly one reasonable thing from it.

- **A test step:** the name of the test and its assertions, as code, with the exact values of
  the spec.
- **A code step:** the exact signature, the file, and the values that the spec fixes. The
  implementer writes the body. Write a body only for an algorithm that the signature and the
  tests do not decide, or for exact copy that the spec fixes.
- **A verification step:** the command and the output that means it passed.
- **A reference to another task:** point to the Interfaces block of that task. Do not repeat
  its code.

Exact user-facing copy in the plan follows section 6b of `~/.claude/skills/_shared/ui-quality.md`:
it says what the user sees or gets, never how the system works underneath.

Write each fact once, in the task that owns it. Another section points to that task
(`Task 4`) and does not repeat the test names, file paths or values. A summary table holds
one line per row, not a copy of the task.

A plan holds the decisions that the implementer cannot make alone. A plan longer than its code
is a transcript, not a plan. A line that decides nothing ("TBD", "handle edge cases", "add
validation", a type that no task defines) is a gap.

## 7. Self-review

After you write the plan, check it against the spec. Fix each problem in the plan.

1. **Spec coverage.** Each requirement of the spec maps to a task. Add a task for a gap.
2. **Steps.** Each step lets the implementer write one reasonable thing. Remove a body that the
   signature and the tests already decide.
3. **Types.** Each name, signature and property in a later task matches its definition in an
   earlier task.
4. **Review Focus.** Each line has its test in the task that owns the code.
5. **Proportion.** When code blocks are most of the plan, replace bodies with signatures, test
   names and assertions.
6. **Source for each addition.** Each new table, column, field, setting and UI control names
   its source: the ticket, a linked document, or the user's words. Cut an addition with no
   source, or ask the user about it. A convenience that you thought of is not a source.
7. **Least new state.** Use the first rung that holds:
   1. reuse a concept that the product already has, such as an existing option or setting;
   2. derive the value from data that already exists, instead of storing a flag;
   3. change the existing choice, instead of adding an override column;
   4. only then, add new state.
8. **Domain names.** A table, column or enum value names the domain role, not the vendor:
   `tracking_source = "carrier_api"`, not `<vendor>_booked`. The vendor name stays inside its
   adapter (`external-services.md`).
9. **Size.** A plan above 60 KB repeats itself or holds too much scope. Remove the repeats
   first, then move scope to a stage or a follow-up ticket.

## 8. After the plan

The planning skill presents the plan and gets the approval. It does not ask for an execution
method: `plan-routing.md` picks the executor, and `after-approval.md` runs the build chain.
