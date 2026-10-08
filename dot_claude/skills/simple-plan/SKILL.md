---
name: simple-plan
description: Lean planning pipeline for a small or medium change. Use when invoked via /simple-plan, or when the user wants a short reviewed plan that writes the least code possible, follows the project's own patterns, types everything strictly, and validates API input. Produces one plan with a problem statement, an approach, conditional diagrams, an edge-case decision table, a TDD test list, and QA validation steps. Stops at the approved plan and does not implement.
---

# simple-plan

Plan a change so that the implementation writes the **least code that solves the problem**,
and still respects the project's patterns, its frameworks, and strict typing.

`simple-plan` stops at an approved plan. It does not write production code.

`simple-plan` runs one drafter, two reviewers, and at most two review rounds. It plans **one
task**, never a programme of work.

When the task arrives too big for that, do not hand it to another command and do not plan it
anyway. Split it first, in Phase 1.5: an agent turns the epic into deliverable tasks ordered
from the foundation up, you pick one, and this run plans that one. The rest waits, written
down, for its own run.

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

Read `~/.claude/skills/simple-plan/references/constraints.md` now. It holds the rules that the plan and both reviewers
enforce. Quote its rule numbers in the plan and in every review verdict.

## Phase 0 — Project context brief

**First, look for an existing breakdown.** List
`docs/superpowers/plans/*-breakdown.md`. When one matches this work, read it, and treat the
first task whose dependencies are met and which has no plan file yet as the task for this run.
Say which task you picked and which breakdown it came from. This is how a split survives
across runs — skip Phase 1.5 when a breakdown already answers it.

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

**Ask at most 3 questions.** Batch them into one `AskUserQuestion` call. When 3 questions do
not settle the design, the task is bigger than one task. Go to Phase 1.5 and split it.

## Phase 1.5 — Split the work, when it is more than one task

Enter this phase when any of these holds:

- The work has two or more outcomes that could ship separately.
- Phase 0 found more than about six files it must change, or two or more directories that
  each need their own change.
- Three brainstorm questions did not settle the design.
- It needs a requirements matrix, a user journey, or parallel lanes.

Dispatch **one** agent to split it. That agent does not plan and does not write code. Give it
`$RUN_DIR/context.md` and `~/.claude/skills/simple-plan/references/constraints.md`, and require an
ordered list where:

- **Each task ships on its own.** A person can exercise it and say whether it works. A task
  that cannot be validated alone is merged into the one that makes it validatable.
- **Each names the observable outcome** that proves it is done — what a reviewer sees, not
  what the code does.
- **The first task is the foundation** the rest build on: the schema, the type, the contract,
  the seam. Later tasks depend only on earlier ones.
- **The list holds 2 to 6 tasks.** More than six means the split is still too coarse; tell the
  agent to group them.

The agent writes the list to `$RUN_DIR/breakdown.md` in exactly this shape, so the next step
can parse it:

```markdown
## Task 1 — <short title>
- **Delivers:** <the observable outcome a person can check>
- **Validated by:** <what someone does to confirm it, in one sentence>
- **Touches:** <paths or directories>
- **Depends on:** none

## Task 2 — <short title>
- **Delivers:** ...
- **Validated by:** ...
- **Touches:** ...
- **Depends on:** Task 1
```

Task 1 depends on nothing. Every later task depends only on earlier ones.

Copy the list to `docs/superpowers/plans/<YYYY-MM-DD>-<slug>-breakdown.md` inside the project,
beside where the plans live. `$RUN_DIR` is keyed to this invocation's arguments, so a file left
only there is unreachable from the next run.

Present the list with `AskUserQuestion` and let the user pick **one** task to plan now. Then
run Phase 2 for that task alone. In the plan's `## Non-goals`, list the tasks not chosen and
link the breakdown file by its project path.

Never plan two tasks in one run. One plan, one task.

## Phase 2 — Draft the plan

### UI/UX consultation, when the change touches an interface

Before drafting, when the task adds or changes a user-facing screen, component, page or
layout, consult the design intelligence and dispatch one UI/UX agent:

1. `Skill(skill="ui-ux-pro-max:ui-ux-pro-max")` for this project's stack — styles, palettes,
   font pairings, UX guidelines, motion presets and component guidance.
2. One `Agent` with the reviewer persona at
   `~/.claude/skills/deep-review/personas/ui-ux.md`, pointed at the **existing** UI rather
   than at a diff. Give it `$RUN_DIR/context.md`, `~/.claude/skills/simple-plan/references/constraints.md` and the task description, and ask for: the
   components and design tokens this change should reuse, with `path:line`; the screen the new
   one should follow as a pattern; the states it must design for; where the component
   boundaries fall and where the logic goes; the feedback the user needs for each action; the
   breakpoints this project supports and how the layout reflows at the narrowest one; and the
   accessibility this screen owes — keyboard path, focus handling on anything that opens, the
   accessible name of every icon-only control, and how errors get announced.

The plan states the breakpoints and the keyboard path as acceptance criteria, not as good
intentions. A screen whose plan is silent about them gets built without them.

Fold the answer into the plan's `Project fit`, `Affected files` and `Edge cases` sections. The
plan names the existing component it reuses instead of leaving the implementer to invent one.
`Skill(skill="frontend-design")` applies when the change needs visual direction rather than
pattern-matching.

Skip this when the change touches no interface, and record that you skipped it.

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

Run the reviewers in parallel, in a single message with one `Agent` call each.

| Reviewer | How | Lens | When |
|---|---|---|---|
| Over-engineering | `Skill(skill="ponytail:ponytail-review")` against `$PLAN_PATH` | What can be deleted from the plan | always |
| Project fit | `Agent` with the persona at `~/.claude/skills/deep-plan/personas/project-developer.md` | Does the plan match this codebase | always |
| Data | `Agent` with the persona at `~/.claude/skills/deep-review/personas/senior-backend.md` | Does the schema make sense, and will the queries hold | the plan touches a table, a column, a migration or a query |

### The data reviewer

Run it whenever the plan adds or changes a table, a column, an index, a migration, or a query
— including an ORM call or a serializer that loads a relation. Skip it otherwise and record
that you skipped it.

Point it at the plan, not at a diff, and tell it to answer two questions:

1. **Does the structure make sense?** Not "is it valid" — whether the shape matches what the
   data is. Judge the column types, the nullability, the keys and constraints, whether a JSON
   column holds fields the code will query by, whether the normalisation fits how the data is
   written and read, and whether the table has a growth and retention story. Its schema pass
   lists what to look for; constraint rule 13 governs the migration count.
2. **Will the queries hold at real size?** The plan's new reads, judged against the indexes
   that will exist after the migration: a query with no supporting index, an N+1 the plan sets
   up, an unbounded result set, `OFFSET` pagination on a table that grows. When a dev database
   is reachable, it reconstructs the SQL and runs `EXPLAIN (ANALYZE)` on a seeded table rather
   than guessing; when it is not, it says so and gives the exact `EXPLAIN` to run.

A finding here is cheap now and expensive later: a wrong column type ships as a migration, and
a missing index ships as an outage. The plan states the final schema, the indexes and the
migration count before implementation starts.

Give the project-fit reviewer `$PLAN_PATH`, `$RUN_DIR/context.md`, and
`~/.claude/skills/simple-plan/references/constraints.md`. Tell it to reject the plan when any constraint rule is broken,
and to quote the rule number.

Both reviewers check test coverage against constraint rule 10. For every row of the TDD
plan, the reviewer confirms that the mock target is the outermost call to an external
service. The reviewer rejects a row that mocks a service, repository, dispatcher, client, or
model method of this project, and names the outermost call to mock instead. Example finding:
"TDD row 3 mocks `SupplyBuyInvoiceLinkDispatcher` (rule 10). Use the real dispatcher and mock
`deliver_b2b_invoice_link_task.delay`."

Apply the findings. Re-run the reviewers. **Stop after two rounds.** Record any finding you
did not apply, with the reason, in a `## Open findings` section at the end of the plan.

## Phase 4 — Present the plan

1. `Skill(skill="plannotator-annotate")`, then `plannotator annotate "$PLAN_PATH" --gate`.
2. Apply the annotations that come back.
3. `ExitPlanMode` for the final approval.

## Phase 5 — Recommend the next commands, in order

The plan is approved. Print `$PLAN_PATH`, then recommend the commands that come next **in the
order they must run**. The user runs them; this session does not start the implementation.

**1. `/qa-plan` — when the change alters a user-facing flow or screen.** This runs *before*
implementation, not after it. It maps the plan's requirements into a reviewed `qa-plan.yaml`,
which the Validation section of `$PLAN_PATH` then references, so the implementer knows what
QA will check before writing the first line. Say plainly that skipping it means QA writes its
own criteria later, from the finished code. When the change touches no flow and no screen, say
why you are not recommending it.

**2. Then implementation.** Offer the two options exactly as the "Execution Handoff" section
of `superpowers:writing-plans` words them: **1. Subagent-Driven (recommended)** and
**2. Inline Execution**.

- `Skill(skill="superpowers:executing-plans")` against `$PLAN_PATH` in this session.
- Or `/deep-execute "$PLAN_PATH"` when the user wants parallel lanes.

**3. Review and QA, which are not optional.** State this chain as the default that runs
after implementation, in this order, and say that each step **fixes what it finds** rather
than reporting it for later:

1. `/deep-review` on the implemented change. Its `/simplify` pass is part of the default.
2. **Fix every CRITICAL and HIGH finding, then re-run the review** on the fix. A finding
   left in the report is not a reviewed change. Record a finding you deliberately do not
   fix, with the reason, under `## Open findings`.
3. QA: `/qa-execute` against the approved `qa-plan.yaml` when step 1 produced one, otherwise
   `/qa-testing` in EXECUTE mode.
4. **Fix every QA failure, then re-run QA** on the fix. A separate agent fixes what QA found;
   the agent that tested does not grade its own repair.
5. Return one summary covering: what was tested, what passed, what failed, what was fixed,
   and what is still open. The summary names the commit the result applies to. "Tests pass"
   is not a summary.

**4. `/pr-description`** to open the PR once the chain above is clean.

**5. The next task from `$RUN_DIR/breakdown.md`**, when Phase 1.5 produced one. Name the task
that comes next so the user does not have to reopen the file.

Then stop. Do not start the implementation yourself.

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
