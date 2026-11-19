# Required plan sections

This file belongs to `simple-plan`. `SKILL.md` names the step that needs it.

**0. Front matter — the pipeline decision.** The record from Phase 0.5, as YAML at the top of
the plan. One entry per decision, appended in order:

```yaml
---
pipeline_decisions:
  - recommended: simple-plan
    reason: One module, a pattern src/api/orders.py:42 already uses, no new contract
    user_response: "go with simple"
    selected: simple-plan
---
```

`user_response` holds what the user actually said. An empty `user_response` means the run
never got an answer, and the plan is not ready to present.

**1. Problem** — What is wrong or missing today, in 3 sentences or fewer. Cite the evidence.

**1b. Ticket requirements** — *Only when the plan comes from a ticket.* Give the ticket key and
link. Then write one row per acceptance criterion or stated requirement, quoted from the ticket:

| ID | Requirement (from the ticket) | Coverage | Where |
|---|---|---|---|
| R1 | "Admins can export orders as CSV" | Covered | Approach step 2, test `test_export_csv` |
| R2 | "The export includes refunds" | Partial | Approach step 2; the refund reason is a non-goal |
| R3 | "Email the file when it is ready" | Not covered | Task 2 of the breakdown |

A `Covered` row names the approach step and the test that proves it. A `Partial` or
`Not covered` row says why, and where the rest goes: a non-goal, a breakdown task, or a
question for the user. End with one line, such as `Coverage: 1 of 3 covered, 1 partial, 1 not
covered.` An approach step that serves no requirement is scope creep. Remove it, or ask the user.

**2. Non-goals** — What this change does not do. This section blocks scope creep during
implementation. It is mandatory and it is never empty.

**3. Approach** — How we solve it, in the fewest steps. For each step, name the rung of
constraint rule 1 that you stopped at. Example: "reuse `src/shared/result.ts` (rule 1.2)".
When a step removes or renames a route, an exported symbol, an event, a queue name, a
configuration key or a response field, list its callers. Search the latest base branch
(`git fetch origin` first), by path and by name, and count a test mock of the removed path as a
caller. Give the search command, and say how each caller moves.

**4. Project fit** — The conventions this change follows, each with the path that proves it.
Name the existing helpers and types it reuses. Name the library idiom it follows. Then the
rules: the rule sources you read in Phase 0, and each rule that applies, with its path and how
the plan honors it. When none applies, say so and name the sources you read.

**5. Types and contracts** — The concrete type declarations the implementation will add or
change. Show the real fields and the real field types, as code. Show the API request and
response models, and the validator that guards each endpoint. Constraint rules 3 and 4 apply.
A reviewer reads this section to prove that the typing is real, because a type checker cannot.

**6. Data structure changes** — *Only when the change alters a persisted structure*, such as a
table, a column, a stored document, or an on-disk format. Show the new structure as a Mermaid
`erDiagram` or `classDiagram`. Show the migration step, and the deploy order that keeps the
previous release working while the migration runs.

**6b. Query cost** — *Only when the change adds or changes a query*, including an ORM call or a
serializer that loads a relation. Fill the query cost table of
`~/.claude/skills/_shared/query-check.md`: where each query runs, the queries per request, the
rows it reads at production size, the index it uses, and the optimization. Write the
optimization now. When the cost depends on production volume, ask the user for the
read-only production check of that file before you present the plan.

**7. Flow** — *Only when the flow has three or more actors, or an asynchronous step, or a
retry.* Show a Mermaid `sequenceDiagram` or `flowchart`. Otherwise omit this section. Do not
draw a diagram for a straight-line call.

**7b. UI design pass** — *Only when the change touches an interface.* Fill the same fields as
the `## UI design pass` section of `~/.claude/skills/deep-plan/templates/plan.md`: who uses
the screen and for which task, the reference screen, reuse, hierarchy, layout and mobile,
actions, feedback and motion, content, accessibility, shortcuts, and a states table. The
states table holds loading, error and success at minimum, plus every other state the screen
has. Each row names the effect, the copy and the action.

**8. Affected files** — A table of path, action (add, edit, delete), and one line of reason.
Constraint rule 9 applies: the table holds only files the task needs. It lists no refactor,
no rename, and no reformat that the task does not require. When the plan wants to change
nearby logic, it asks the user first and records the answer.

**8b. Work size** — How big the work is, piece by piece. First name the piece of the larger
work that this plan covers, such as `Task 2 of 4 in <breakdown path>`, or `the whole ticket`.
Then write one row per piece of this plan, such as a migration, an endpoint, a component, or
the tests:

| Piece | What it is | Files | Estimated lines |
|---|---|---|---|
| Model and migration | `refund_total` column on `Order` | 2 | ~40 |
| Export endpoint | CSV stream for admins | 2 | ~80 |
| Tests | TDD plan rows 1 to 4 | 2 | ~120 |
| **Total** | | **6** | **~240 (production ~120, tests ~120)** |

Base each estimate on a similar change in this repository. Name its commit and the line count
from `git show --stat <sha>`. Mark an estimate without a precedent as `guess`. Then give the size:
**S** under 100 changed lines, **M** 100 to 400, **L** over 400. An L plan returns to Phase 1.5
for a split.

**9. Edge cases** — A table. Constraint rule 7 defines the decisions.

| ID | Case | Criticality | Decision |
|---|---|---|---|
| EC-001 | Two requests update the same order at once | High | Cover now |
| EC-002 | The upstream API returns a 500 | Medium | Fail loudly |
| EC-003 | The user has no locale set | Low | Out of scope |

The ID stays with the case from the plan to the PR. The PR lists every `Out of scope` row under
`## Deferred edge cases`.

Raise race conditions and failure modes here. Do not implement them here. If every row says
`Cover now`, the plan is not simple. Re-read constraint rule 7 and reduce it.

**10. TDD plan** — The test list, written before the code. One test per `Cover now` row, plus
one test for the success path. For each test, give the name, the file, the assertion, and the mock
target. Constraint rule 10 applies: each test mocks only the outermost call to an external
service (HTTP request, broker enqueue, SDK call, or clock), and runs this project's services,
repositories, dispatchers, and clients for real. Name the exact mock target, for example
`httpx.AsyncClient.post` or `apps.billing.tasks.deliver_invoice_link_task.delay`. A row
whose mock target is a class or method of this project is a plan defect. The
implementation follows `superpowers:test-driven-development`: write the failing test, watch it
fail, then write the code.

**11. Validation** — Two parts.

- *Commands*: the exact checks the implementer runs, such as `mypy --strict src/`,
  `ruff check`, `tsc --noEmit`, and the test command. Name the real commands for this project.
- *QA steps*: what the QA agent verifies in a live environment. Write one numbered step per
  observable behavior. When the change touches a user-facing flow or screen, run `/qa-plan`
  in Phase 4 and reference the generated `qa-plan.yaml` here instead of writing the steps by
  hand.

**12. Evidence map** — One row per requirement (`R-001` onward), per applicable rule and per
`Cover now` or `Fail loudly` edge case, with the test, command or QA step that proves it. The
format is in section 4 of `~/.claude/skills/_shared/spec-evidence.md`. The PR turns each row
into a line of evidence, so a row with no runnable proof says why.
