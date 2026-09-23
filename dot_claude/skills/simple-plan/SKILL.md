---
name: simple-plan
description: Lean planning pipeline for a small or medium change. Use when invoked via /simple-plan, or when the user wants a short reviewed plan that writes the least code possible, follows the project's own patterns, types everything strictly, and validates API input. Produces one plan with a problem statement, an approach, conditional diagrams, an edge-case decision table, a TDD test list, and QA validation steps. Stops at the approved plan and does not implement.
---

# simple-plan

Plan a change so that the implementation writes the **least code that solves the problem**,
and still respects the project's patterns, its frameworks, and strict typing.

`simple-plan` stops at an approved plan. It does not write production code.

`simple-plan` is not `deep-plan`. It runs one drafter, two reviewers, and at most two review
rounds. When the task turns out to need a requirements matrix, a user journey, or parallel
lanes, say so and let the user run `/deep-plan` themselves. Do not escalate on your own.

## Setup

Run every phase inside plan mode. Call `EnterPlanMode` before Phase 0.

Set the run directory:

```bash
RUN_DIR=~/.claude/simple-plan-runs/$(date +%Y%m%d-%H%M%S)-$(printf '%s' "$ARGUMENTS" | shasum | cut -c1-6)
mkdir -p "$RUN_DIR"
```

`$RUN_DIR` holds `context.md`, the review notes, and the `qa/` bundle. The plan is not stored
there. The plan lives where `superpowers:writing-plans` saves it:
`docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md` inside the project. `$RUN_DIR/plan.md`
is a one-line pointer file that contains that path.

Read `references/constraints.md` now. It holds the rules that the plan and both reviewers
enforce. Quote its rule numbers in the plan and in every review verdict.

## Phase 0 — Project context brief

Gather evidence before you draft. Write the result to `$RUN_DIR/context.md`.

1. Find the affected directories from the task description.
2. Read the root `CLAUDE.md`, and every `CLAUDE.md` inside an affected directory.
3. Read `.claude/rules/` when the directory exists. Read every rule file that applies.
4. Read two or three existing files of the same kind as the files the change touches.
   Record the naming convention, the error style, the dependency-injection style, and the
   test layout.
5. Read the dependency manifest. List the libraries that the change will use.
6. Read the documentation of each of those libraries for the parts the change touches. Use
   the Context7 MCP server when it is available. Record the idiom the library expects.
7. Use Serena and GitNexus for symbol lookup and blast radius when the project is indexed.

Every line of the brief carries a path, such as `src/api/orders.py:42`. A line without a
path is an assumption, and you must mark it **unknown**.

## Phase 1 — Brainstorm, only when the task is unclear

Skip this phase when the task is small and unambiguous. Record that you skipped it.

Run `Skill(skill="superpowers:brainstorming")` when any of these is true:

- The task description allows two or more reasonable designs.
- The scope is unclear.
- The change touches a flow you could not map in Phase 0.

**Ask at most 3 questions.** Batch them into one `AskUserQuestion` call. If 3 questions do
not settle the design, stop and tell the user that the task needs `/deep-plan`.

## Phase 2 — Draft the plan

Invoke `Skill(skill="superpowers:writing-plans")` and follow it completely. Never paraphrase
it from memory. That skill owns the document header, the task structure (Files, Interfaces,
and checkbox steps), the no-placeholder rule, the self-review, the save location, and the
execution handoff. `simple-plan` never replaces or relocates anything that
`superpowers:writing-plans` prescribes.

`simple-plan` only adds the sections below. Insert them between the writing-plans header and
the first task, in this order.

After the plan is saved, record its path:

```bash
PLAN_PATH=docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md
printf '%s\n' "$PLAN_PATH" > "$RUN_DIR/plan.md"
```

Every later phase reads the plan from `$PLAN_PATH`.

### Required sections

**1. Problem** — What is wrong or missing today, in 3 sentences or fewer. Cite the evidence.

**2. Non-goals** — What this change does not do. This section blocks scope creep during
implementation. It is mandatory and it is never empty.

**3. Approach** — How we solve it, in the fewest steps. For each step, name the rung of
constraint rule 1 that you stopped at. Example: "reuse `src/shared/result.ts` (rule 1.2)".

**4. Project fit** — The conventions this change follows, each with the path that proves it.
Name the existing helpers and types it reuses. Name the library idiom it follows.

**5. Types and contracts** — The concrete type declarations the implementation will add or
change. Show the real fields and the real field types, as code. Show the API request and
response models, and the validator that guards each endpoint. Constraint rules 3 and 4 apply.
A reviewer reads this section to prove that the typing is real, because a type checker cannot.

**6. Data structure changes** — *Only when the change alters a persisted structure*, such as a
table, a column, a stored document, or an on-disk format. Show the new structure as a Mermaid
`erDiagram` or `classDiagram`. Show the migration step.

**7. Flow** — *Only when the flow has three or more actors, or an asynchronous step, or a
retry.* Show a Mermaid `sequenceDiagram` or `flowchart`. Otherwise omit this section. Do not
draw a diagram for a straight-line call.

**8. Affected files** — A table of path, action (add, edit, delete), and one line of reason.
Constraint rule 9 applies: the table holds only files the task needs. It lists no refactor,
no rename, and no reformat that the task does not require. When the plan wants to change
nearby logic, it asks the user first and records the answer.

**9. Edge cases** — A table. Constraint rule 7 defines the decisions.

| Case | Criticality | Decision |
|---|---|---|
| Two requests update the same order at once | High | Cover now |
| The upstream API returns a 500 | Medium | Fail loudly |
| The user has no locale set | Low | Out of scope |

Raise race conditions and failure modes here. Do not implement them here. If every row says
`Cover now`, the plan is not simple. Re-read constraint rule 7 and reduce it.

**10. TDD plan** — The test list, written before the code. One test per `Cover now` row, plus
one test for the success path. For each test, give the name, the file, the assertion, and the mock
target. Constraint rule 10 applies: each test mocks only the outermost call to an external
service (HTTP request, broker enqueue, SDK call, or clock), and runs this project's services,
repositories, dispatchers, and clients for real. Name the exact mock target, for example
`httpx.AsyncClient.post` or `apps.billing.tasks.deliver_b2b_invoice_link_task.delay`. A row
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

## Phase 3 — Review

Run both reviewers in parallel, in a single message with two `Agent` calls.

| Reviewer | How | Lens |
|---|---|---|
| Over-engineering | `Skill(skill="ponytail:ponytail-review")` against `$PLAN_PATH` | What can be deleted from the plan |
| Project fit | `Agent` with the persona at `~/.claude/skills/deep-plan/personas/project-developer.md` | Does the plan match this codebase |

Give the project-fit reviewer `$PLAN_PATH`, `$RUN_DIR/context.md`, and
`references/constraints.md`. Tell it to reject the plan when any constraint rule is broken,
and to quote the rule number.

Both reviewers check test coverage against constraint rule 10. For every row of the TDD
plan, the reviewer confirms that the mock target is the outermost call to an external
service. The reviewer rejects a row that mocks a service, repository, dispatcher, client, or
model method of this project, and names the outermost call to mock instead. Example finding:
"TDD row 3 mocks `SupplyBuyInvoiceLinkDispatcher` (rule 10). Use the real dispatcher and mock
`deliver_b2b_invoice_link_task.delay`."

Apply the findings. Re-run the reviewers. **Stop after two rounds.** Record any finding you
did not apply, with the reason, in a `## Open findings` section at the end of the plan.

## Phase 4 — QA plan, only when a flow or a screen changes

Run `/qa-plan` when the change alters a user-facing flow or screen. Reference the generated
`qa-plan.yaml` from the Validation section of `$PLAN_PATH`. Skip this phase otherwise, and record that
you skipped it.

## Phase 5 — Present

1. `Skill(skill="plannotator-annotate")`, then `plannotator annotate "$PLAN_PATH" --gate`.
2. Apply the annotations that come back.
3. `ExitPlanMode` for the final approval.

Then stop. Print `$PLAN_PATH`. After approval, offer the two execution options exactly as the
"Execution Handoff" section of `superpowers:writing-plans` words them: **1. Subagent-Driven
(recommended)** and **2. Inline Execution**. Then stop.

- `Skill(skill="superpowers:executing-plans")` against `$PLAN_PATH` in this session.
- Or `/deep-execute "$PLAN_PATH"` when the user wants parallel lanes.

Do not start the implementation yourself.

## Failure handling

- `plannotator` CLI is missing → print a short summary of the plan inline, print
  `$PLAN_PATH`, and continue to `ExitPlanMode`. Install it with
  `curl -fsSL https://plannotator.ai/install.sh | bash`.
- `plannotator annotate --gate` exits with no feedback → treat the plan as approved, record
  that, and continue.
- A reviewer agent fails → record the failure in the plan, continue with the other reviewer,
  and tell the user which lens did not run.
- The project has no `CLAUDE.md` and no `.claude/rules/` → derive the conventions from the
  neighbor files in Phase 0, and mark the Project fit section as **derived, unverified**.
