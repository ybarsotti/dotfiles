# Spec validity and evidence

A plan is the contract for a change. This file keeps the contract true after the approval, and
makes the pull request prove each part of it. `deep-plan`, `simple-plan`, `deep-execute` and
`pr-description` follow it.

## 1. The plan lives in the repository

Save the approved plan inside the project, so it is versioned with the code it describes.

- `simple-plan`: `docs/superpowers/plans/YYYY-MM-DD-<slug>.md`.
- `deep-plan`: `docs/superpowers/plans/YYYY-MM-DD-<slug>/plan.md`, with its `subplans/`.

When the project ignores `docs/superpowers/`, or its rules forbid plan files, keep the plan
in the run directory and say so in the handoff. Do not change a team convention to fit this file.

## 2. The approval binds to the exact text

Stamp the plan when the user approves it:

```bash
~/.claude/skills/_shared/plan-stamp.sh approve <plan.md>
```

The script writes `<plan.md>.approved` with a hash of the plan and its subplans. Commit the
stamp with the plan. Before execution starts, and again before the pull request opens, run:

```bash
~/.claude/skills/_shared/plan-stamp.sh check <plan.md>
```

- Exit 0: the plan is still the approved one.
- Exit 1: someone edited the approved text. Stop. Move the change into `## Deviations` and
  restore the approved text, or get the edited plan approved again.
- Exit 2: the plan has no stamp. Ask the user to approve it, or record that it was not approved.

## 3. A deviation updates the plan

Execution finds things that the plan got wrong. Record each one in the plan itself, in a
`## Deviations` section at the end. A deviation kept only in a ledger or a commit message
leaves the plan describing code that does not exist.

| id | the plan said | what was built | why | approved by |
|---|---|---|---|---|
| D-001 | <the planned behavior> | <the actual behavior> | <the reason> | <user / executor> |

- An executor approves a deviation that keeps every requirement, rule and contract. Examples:
  another helper name, another file, one more test.
- A deviation that changes a requirement, a rule, an edge-case decision or an API contract needs
  the user. Ask through `AskUserQuestion` before you build it.
- Edit only the `## Deviations` section after the approval. The stamp ignores that section and
  covers the rest.

## 4. The plan maps each claim to its proof

The plan holds an `## Evidence map`. Each row names one thing the change must hold and the proof
that will show it.

| id | covers | proof | proof kind |
|---|---|---|---|
| R-001 | <requirement, as the requirements matrix states it> | `<test node id or command>` | test |
| <rule id> | <rule, as the Rules table states it> | `<test or check>` | test |
| EC-003 | <edge case with decision Cover now or Fail loudly> | `<test node id>` | test |

- Give one row per requirement (`R-NNN`, in the order of the requirements matrix), per
  applicable rule, and per edge case decided `Cover now` or `Fail loudly`.
- `proof kind` is `test`, `command`, `qa` (a QA scenario with a screenshot or a recording) or
  `review` (a human reads it). Use `review` only when no runnable proof exists, and say why.
- An edge case decided `Out of scope` has no row. The pull request lists it as deferred.

## 5. The pull request shows the proof

The pull request body holds `## Evidence by requirement`, one row per evidence-map id:

| id | claim | proof | result |
|---|---|---|---|
| R-001 | <claim> | `<test node id>` | pass at `abc1234` |
| EC-003 | <claim> | <QA screenshot link> | pass at `abc1234` |
| EC-005 | <claim> | — | deferred: Out of scope in the plan |

- Run each proof against the commit that the pull request ships. Write the short SHA in the
  result column.
- A row with no proof blocks the pull request. Add the proof, or mark the row deferred with the
  plan's reason. Never write `pass` for a proof that did not run.
- When the branch moves after the proofs ran, run them again and update the SHA.
- Add the deviations from the plan under `## Deviations from the plan`, or write `None`.

## 6. Continuous integration is a suggestion

When a repository has no check that a pull request matches its plan, and the user owns that
repository's CI, suggest a job that runs `plan-stamp.sh check` and fails on a missing evidence
row. Say it once, in the handoff. Do not add the job unless the user asks.
