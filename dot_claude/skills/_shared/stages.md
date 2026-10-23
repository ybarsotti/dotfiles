# Staged delivery

This file is the single definition of staged delivery for `deep-plan`, `simple-plan`,
`deep-execute` and `deep-review`. Point at this file. Do not copy its rules into another file.

A feature is staged when it is too large to review as one change but ships as one pull
request. Each stage is a working slice. Each stage gets its own plan, its own gate and its own
commit. A reviewer reads the pull request one stage commit at a time.

## 1. When to stage

Recommend stages when the feature has two or more slices that each work alone, and the whole
diff would be too large to review in one pass. Ask the user and wait for the answer. Record the
answer in the plan.

Do not stage a change that fits one review. Separate pull requests stay the better choice
when each slice can merge on its own.

## 2. The roadmap

The first plan holds a `## Stages` section with two parts:

1. **Cross-stage architecture.** What every stage shares: section ownership, data loading,
   shared components and contracts. A later stage reads this part and does not redesign it.
2. **The stage table.**

| # | stage | scope | class | status | commit |
|---|---|---|---|---|---|
| 1 | <name> | <what this stage ships> | `light` or `full` | `planned`, `in progress` or `done` | `<sha>` or `-` |

The rest of the plan details only the current stage: the first row whose status is not
`done`. Later stages stay one table row each until their turn.

## 3. The next stage

To plan the next stage, run the planner with `--roadmap <path to the previous plan>`.
The planner copies the `## Stages` section, updates the status and the commit of the finished
stage, and plans the next row. It changes the cross-stage architecture only when the user
approves the change, and it records that decision in the plan.

## 4. The gate class

Classify each stage before you plan it in detail.

| Class | When | Gate after the build |
|---|---|---|
| `full` | The stage changes a business rule, a permission, a migration, a public contract, an integration, or it removes a contract | The complete chain: `/deep-review default`, QA, fixes |
| `light` | Every other stage, for example a restyle, a layout, or a UI section on an existing contract | The visual pass of `_shared/ui-quality.md` section 11, then `/deep-review stage-light`, then QA on the changed screens |

When the class is unclear, use `full`. The user can override the class. Record the override.

## 5. Build and gate each stage

1. Build the stage from its plan.
2. Run the gate of its class.
3. Fix what the gate finds, then run the gate again.
4. Cap QA at 3 rounds per stage. At the cap, ask the user with the surviving findings.
5. Commit the stage as one commit. Its message names the stage number and the stage.
6. Set the stage status to `done` and record the commit in the stage table.

A fix to an earlier stage goes into that stage's commit when the pull request is not yet
reviewed. After review starts, add a new commit, and name the stage it fixes.

## 6. The pull request

The pull request body holds the stage table with the status and the commit of each stage.
It says which stage to review next. It says that the pull request must not merge before
every stage is `done`.

Before the pull request is marked ready, rebase it onto the latest base branch. Then run the
removed-contract search again (see `deep-review/personas/architecture.md`), because a caller
can land on the base branch while the stages are in progress.
