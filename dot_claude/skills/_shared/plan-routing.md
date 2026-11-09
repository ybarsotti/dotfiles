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

| Option | Recommend it when | Executor |
|---|---|---|
| A | every rule of the option A test below holds | `/deep-execute "$PLAN"` |
| B | every other plan, and the default | `Skill(skill="implement", args="$PLAN")` |
| C | many uniform mechanical slices, such as a migration, a codemod or a sweep over N files | the Claude `Workflow` tool |
| D | the user wants Codex to write one self-contained slice | `codex exec`, this session reviews |

The option A test. Parallel lanes cost a contract, a round gate and a review per round, so
they pay off only on large work that splits cleanly. Recommend option A only when all of
these hold:

1. The plan's `## Work size` says `Size: L`.
2. `## Execution shape` says `Mode: parallel` and declares a materialized API contract.
3. Two or more non-orchestrator lanes have no `depends_on` between them.
4. Each of those lanes owns 3 or more tasks in `## Implementation tasks`.
5. The `test_command` of each of those lanes passes on its own on the current commit. Run
   each one before you recommend option A.

When one rule fails, recommend option B, and name the failed rule in the reason.
`/deep-execute` refuses a plan that is not `Mode: parallel`, so never give it a serial plan.
