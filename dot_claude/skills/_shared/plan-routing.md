# Plan routing — which pipeline plans, and which executor builds

This file holds two routing decisions. The first section chooses the planning pipeline:
`deep-plan` (Phase 0.4), `simple-plan` (Phase 0.5) and `workflow-mode` (section 2) read it.
The last section chooses the executor after plan approval: `after-approval.md` section 1,
`deep-plan`, `simple-plan` and `jira-workflow` read it. Each skill asks its own question.

## The criteria

The thorough path is `/deep-plan`, or the `standard` workflow mode. Recommend it when the
evidence shows any of these:

- business behavior: pricing, billing, an order or an approval path;
- who may do what: a role, a permission, a policy, a guard;
- a migration, or any change to a table or a column;
- a third-party integration, or a new contract with another service;
- scope that the evidence cannot pin down, with more than one reasonable reading.

The lean path is `/simple-plan`, or the `fast` workflow mode. Recommend it for any other
narrow change: one module, a pattern that the repository already has, no new contract.

In a repository with `.workflow/config.json`, an active `kind: business` rule whose `paths`
match the changed files is a reason for the thorough path. The repository's
`.workflow/modes.md` overrides this list when the two differ.

## The question

1. Recommend one path. Give the reason in one sentence, with the path or the rule id that
   drove it.
2. Stop and wait. Silence is not an answer, and neither is the absence of an objection.
3. The user accepts or overrides. An override needs no reason.
4. Record the recommendation, the reason, the user's words and the chosen path.
5. When the scope grows during the run, recommend again before the work that depends on it.
   Append a second decision. Do not rewrite the first one.

## The executor after approval

Read the approved plan's `## Execution shape`. Recommend the executor from what is there. Do
not ask the user again: the recommended option runs, unless the user named another one.
Option C is the one exception. It needs ultracode, and only the user can turn ultracode on.

| Option | Recommend it when | Executor |
|---|---|---|
| A | every rule of the option A test below holds | `/deep-execute "$PLAN"` |
| B | every other plan, and the default | `Skill(skill="implement", args="$PLAN")` |
| C | the option A test fails, and the option C test below holds | a `Workflow` run (ultracode) |
| D | the user wants Codex to write one self-contained slice | `codex exec`, this session reviews |

**The options depend on the harness that runs the session.**

- **Claude Code** offers all four options.
- **Codex** offers options A and B only. Codex has no `Workflow` tool and no ultracode effort.
  Its `multi_agent` subagents start agents, but no script orchestrates them, so they do not
  replace option C. Option D needs a second model, and the session is already Codex.
- Under Codex, never ask the ultracode question. When the option C test holds, recommend
  option A if the option A test holds, else option B.

**Always show the recommendation when the plan is final.** Before the build starts, print:

1. the recommended option and the reason, in one sentence;
2. each other option that this harness offers, with the rule that ruled it out.

Then run the recommended option, unless the user names another.

The option A test. Parallel lanes cost a contract, a round gate and a review per round, so
they pay off only on large work that splits cleanly. Recommend option A only when all of
these hold:

1. The plan's `## Work size` says `Size: L`.
2. `## Execution shape` says `Mode: parallel` and declares a materialized API contract.
3. Two or more non-orchestrator lanes have no `depends_on` between them.
4. Each of those lanes owns 3 or more tasks in `## Implementation tasks`.
5. The `test_command` of each of those lanes passes on its own on the current commit. Run
   each one before you recommend option A.

When one rule fails, name the failed rule in the reason, and check option C next.
`/deep-execute` refuses a plan that is not `Mode: parallel`, so never give it a serial plan.
Option A stays the executor for long runs with a contract over several rounds, where a
question during the build can change the build.

The option C test. A unit is a non-orchestrator lane of a `Mode: parallel` plan, or a
`### Task N:` block of a serial plan. Recommend option C only when all of these hold:

1. The plan has two or more units, and every pair of units is independent. Two lanes are
   independent when no `depends_on` links them. Two tasks are independent when neither
   task's `**Interfaces:**` block uses a symbol that the other task creates.
2. Each unit declares its files: a lane's `owns` globs, or a task's `**Files:**` block. No
   path or glob of one unit overlaps a path or glob of another unit.
3. Each unit's tests pass on their own on the current commit. For a lane, run its
   `test_command`, as option A rule 5 does. For a task, run the existing tests of the paths in
   its `**Files:**` block. Run each one before you recommend option C.

When one rule fails, name the failed rule in the reason, and recommend option B. A
`simple-plan` plan holds one task, so it always fails rule 1.

The option C question. Ask it once, at plan approval, before the after-approval chain starts.
The chain never asks it. The `ultracode` keyword counts only in a prompt that the user types.
An agent cannot turn ultracode on. Never say or imply that you turned it on.

1. When the session already runs at ultracode effort, run option C. Do not ask.
2. When ultracode is off, ask the question below in plain chat text, in the user's language.
   Never ask it through `AskUserQuestion` or the Inbox: a click is not a typed keyword. Then
   stop and wait.
3. The user opts in only when the reply contains the word `ultracode`, or when the user runs
   `/effort ultracode`.
4. When the user does not opt in, run option B.
5. Record the question and the reply in `$RUN_DIR/decisions.md`.

> This plan has N independent tasks. Do you want to build it with ultracode, a parallel
> workflow with adversarial review? Only you can turn ultracode on: reply `ultracode`, or run
> `/effort ultracode`. Otherwise I build it with option B, one task at a time.

How option C runs:

1. Load `Skill(skill="workflow-authoring")` before you write the script.
2. Split the work into stages: build, then review. Each stage is its own workflow.
3. A workflow cannot stop for an answer. When an agent meets a stop case of
   `after-approval.md`, the workflow records it and ends. Ask it before the next workflow.
4. The build script runs one `pipeline()` over the units. Each agent works in its own worktree.
5. Each agent receives its unit's files from rule 2, and the contract file when the plan has one.
6. A verify agent compares `git diff --name-only` with those files, and fails a unit that
   changed any other path. It also runs the unit's tests.
7. An adversarial reviewer checks each unit before the merge. This review replaces the
   per-part review of `after-approval.md` section 1.
8. Cap the concurrent agents at 4 when the agents run test suites.
9. This session merges each worktree back, then continues the after-approval chain. Its
   section 2 runs one `/deep-review` over the whole branch.
