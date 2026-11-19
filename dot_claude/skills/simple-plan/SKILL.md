---
name: simple-plan
description: Use when invoked via /simple-plan, or for a small or medium change (one module, no new contract) that needs a short reviewed plan with the least code. Builds and opens the PR after approval. For large or risky work use deep-plan.
---

# simple-plan

Plan a change so that the implementation writes the **least code that solves the problem**,
and still respects the project's patterns, its frameworks, and strict typing.

`simple-plan` plans, and after your approval it drives the build to an open PR through
`~/.claude/skills/_shared/after-approval.md`. The planning session does not write production code.

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

Read `~/.claude/skills/simple-plan/references/context-brief.md` before you gather the evidence.
It lists the eight steps: the affected directories, the rule sources, sibling files, the
dependency manifest, library documentation, the code-intelligence tools and the ticket.

Every line of the brief carries a path, such as `src/api/orders.py:42`. A line without a
path is an assumption, and you must mark it **unknown**.

## Phase 0.5 — Recommend the pipeline, and wait for the answer

The brief now says how large the change really is. Recommend `simple-plan` or `/deep-plan`
with the criteria of `~/.claude/skills/_shared/plan-routing.md`, and follow the question rules
there. Record the exchange in the plan's front matter. When the caller already asked it, for
example `jira-workflow`, do not ask again: record the user's answer from that exchange. When the user picks `/deep-plan`, stop
this run and say so; do not plan the task twice.

## Phase 1 — Grill the plan

Run this phase on every task. Skip it only when the user says "skip grill", and record the skip.

Run `Skill(skill="mattpocock-skills:grilling")` against the task and `$RUN_DIR/context.md`.
Do not invoke `grill-with-docs`. The Skill tool refuses it, because it sets
`disable-model-invocation`. Offer `/mattpocock-skills:grill-with-docs` when the user wants to
drive the interview.

The grill has no question cap. Stop when the answers no longer
change the approach. When the grill finds two or more outcomes that ship separately, go to
Phase 1.5.

Write each question and answer to `$RUN_DIR/grill.md` as `### Q:` and `### A:` pairs. Phase 2
copies each decision that the grill resolved into the plan's `Approach` or `Edge cases`.

## Phase 1.2 — Brainstorm, only when the design is still open

The grill ran first. Skip this phase when the grill settled the design. Record that you skipped it.

Run `Skill(skill="superpowers:brainstorming")` when any of these is still true after the grill:

- The task description allows two or more reasonable designs.
- The scope is unclear.
- The change touches a flow you could not map in Phase 0.

**Ask at most 3 questions.** Batch them into one `AskUserQuestion` call. When the grill and 3 questions do
not settle the design, the task is bigger than one task. Go to Phase 1.5 and split it.

## Phase 1.5 — Split the work, when it is more than one task

Enter this phase when any of these holds:

- The work has two or more outcomes that could ship separately.
- Phase 0 found more than about six files it must change, or two or more directories that
  each need their own change.
- The grill and three brainstorm questions did not settle the design.
- It needs a requirements matrix, a user journey, or parallel lanes.

Dispatch **one** agent to split it. That agent does not plan and does not write code. Read
`~/.claude/skills/simple-plan/references/breakdown.md` before you dispatch it. It holds the
requirements for the list and the exact file format. Give the agent `$RUN_DIR/context.md` and
`~/.claude/skills/simple-plan/references/constraints.md`.

Rules for the list:

- **Each task ships on its own** and names the observable outcome that proves it is done.
- **The first task is the foundation.** It depends on nothing. Later tasks depend only on earlier ones.
- **The list holds 2 to 6 tasks.** More than six means the split is too coarse; group them.

The agent writes the list to `$RUN_DIR/breakdown.md`. When the user chooses stages (below), the file also follows
`~/.claude/skills/_shared/stages.md`.

Copy the list to `docs/superpowers/plans/<YYYY-MM-DD>-<slug>-breakdown.md` inside the project,
beside where the plans live. `$RUN_DIR` is keyed to this invocation's arguments, so a file left
only there is unreachable from the next run.

Ask how the tasks ship: one pull request per task, or **stages** of one pull request, with
one commit per stage and the gate of each stage's class (`_shared/stages.md`). Recommend stages
when the tasks only make sense together. Record the answer in the breakdown file.

Present the list with `AskUserQuestion` and let the user pick **one** task to plan now. Then
run Phase 2 for that task alone. In the plan's `## Non-goals`, list the tasks not chosen and
link the breakdown file by its project path.

Never plan two tasks in one run. One plan, one task.

## Phase 2 — Draft the plan

Invoke the `ub-mode` skill and design by its "First Make it Work" rules. The verification of
each task lists the "Then Make it Right" gates on its files: `crapper`, `dryer` and `mutator`.

### UI/UX consultation, when the change touches an interface

Before drafting, when the task adds or changes a user-facing screen, component, page or
layout, read `~/.claude/skills/simple-plan/references/ui-consultation.md` and follow it. It reads
`~/.claude/skills/_shared/ui-quality.md`, runs `ui-ux-pro-max`, dispatches one UI/UX agent and
starts the `ui-designer` worker.

The plan states the breakpoints and the keyboard path as acceptance criteria, not as good
intentions. Fold the answer into the plan's `UI design pass` section, and into `Project fit`,
`Affected files` and `Edge cases`. The plan names the existing component it reuses.
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

Read `~/.claude/skills/simple-plan/references/plan-sections.md` before you write the sections.
It holds the full text of each section. The sections, in order: 0 Front matter (pipeline
decision; an empty `user_response` means the plan is not ready to present), 1 Problem, 1b Ticket
requirements (ticket only), 2 Non-goals (mandatory, never empty), 3 Approach (the fewest steps,
each with its rung of constraint rule 1; list the callers of any removed contract), 4 Project fit,
5 Types and contracts, 6 Data structure changes, 6b Query cost (`_shared/query-check.md`), 7 Flow,
7b UI design pass, 8 Affected files (constraint rule 9), 8b Work size (an L plan returns to
Phase 1.5), 9 Edge cases (if every row says `Cover now`, the plan is not simple), 10 TDD plan
(mock only the outermost external call, constraint rule 10), 11 Validation, 12 Evidence map.

## Phase 3 — Review

Run the reviewers in parallel, in a single message with one `Agent` call each.

| Reviewer | How | Lens | When |
|---|---|---|---|
| Over-engineering | `Skill(skill="ponytail:ponytail-review")` against `$PLAN_PATH` | What can be deleted from the plan | always |
| Project fit | `Agent` with the persona at `~/.claude/skills/deep-plan/personas/project-developer.md` | Does the plan match this codebase | always |
| Data | `Agent` with the persona at `~/.claude/skills/deep-review/personas/senior-backend.md` | Does the schema make sense, and will the queries hold | the plan touches a table, a column, a migration or a query |

Read `~/.claude/skills/simple-plan/references/reviewers.md` before you start the reviewers. It holds
the data reviewer questions and the project-fit and test-coverage instructions. Give the
project-fit reviewer `$PLAN_PATH`, `$RUN_DIR/context.md` and the constraints file. It rejects the
plan when any constraint rule is broken, and it quotes the rule number. Both reviewers check each
TDD row against constraint rule 10.

Run the data reviewer whenever the plan adds or changes a table, a column, an index, a migration
or a query. Skip it otherwise and record that you skipped it.

Apply the findings. Re-run the reviewers. **Stop after two rounds.** Record any finding you
did not apply, with the reason, in a `## Open findings` section at the end of the plan.

## Phase 3.5 — Blindspot pass

The reviewers in Phase 3 read the plan against the files you opened. They cannot see the files
nobody opened. Run the pass that can:

```
Skill(skill="blindspot")
```

The artifact is `$PLAN_PATH`. The pass labels every claim in the plan READ or INFERRED, then
opens the surface behind each INFERRED claim or rewrites the claim to what you observed. A plan
that names a table, an endpoint, a job or a configuration key you never opened states a fact it
did not check.

Apply the rewrites to the plan before Phase 4. Say in the presentation which claims stay
unverified, and why.

## Phase 4 — Present the plan

0. **When the plan adds machinery, run `Skill(skill="shed-light")` over it first.** Machinery
   means a service, a queue, a package, a registry, a configuration key, a migration, a CI
   step or a monitor. The report says what the team will own, the upkeep each piece carries,
   and the work that leaves the team. Put it beside the plan, so the approval covers the cost
   and not only the design. Skip it when the plan only changes code the team already owns.
1. Render the plan page and decide where it lives per `~/.claude/skills/_shared/plan-page.md`.
   Then gate it: `plannotator annotate "${PLAN_PATH%.md}.html" --gate`.
2. Apply the annotations that come back to `$PLAN_PATH`, then render the page again.
3. `ExitPlanMode` for the final approval.
4. Stamp the approved plan: `~/.claude/skills/_shared/plan-stamp.sh approve "$PLAN_PATH"`.
   Commit the plan and its `.approved` stamp together.
5. When `.workflow/config.json` exists, run `Skill(skill="workflow-post-plan")` with the Phase 3 reviewer results as evidence.

## Phase 5 — Build to PR, without waiting

The approval of the plan is the go. Print `$PLAN_PATH`, then run these steps in order. Do not
stop to recommend commands. Stop at the plan only when the user said so, such as "only plan".

1. **`/qa-plan` first, when the change alters a user-facing flow or screen.** It runs before
   the implementation. It maps the plan's requirements into a reviewed `qa-plan.yaml`, and the
   Validation section of `$PLAN_PATH` references it. When the change touches no flow and no
   screen, say why you skip it.
2. **Then the chain in `~/.claude/skills/_shared/after-approval.md`.** Its executor comes from
   `~/.claude/skills/_shared/plan-routing.md`: usually the `implement` skill. Show the
   recommendation as that section says, with the options this harness offers, then run it.
   A simple-plan plan holds one task, so it fails the option C test and never asks the
   ultracode question.

Rules for this pipeline inside that chain:

- Before `/pr`, rebase onto the latest base branch. Repeat the caller search for every removed
  contract in the plan. Run `plan-stamp.sh check "$PLAN_PATH"`; the PR body proves each
  evidence-map row at the shipped SHA.
- For stages, run the build, review and QA once per stage with the gate of its class, commit
  the stage, and open the PR with the stage table (`_shared/stages.md`).
- When Phase 1.5 produced `$RUN_DIR/breakdown.md`, end by naming the next task in it.

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
