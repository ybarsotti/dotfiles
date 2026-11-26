---
name: deep-plan
description: Use when invoked via /deep-plan, or for a large or risky change (business rules, permissions, migrations, integrations) that needs a deeply reviewed plan before code. Builds and opens the PR after approval. Small or medium change, use simple-plan. Run an approved parallel plan, use deep-execute.
---

# deep-plan

You are the **orchestrator** of a multi-agent **deep-planning** pipeline. Your job is to
coordinate planning and review, then present an approved plan and hand off. You do **not**
draft the plan yourself, and you do **not** build, review the code, or open the PR — those
happen in the **execution phase**, driven by `/deep-execute` after approval. deep-plan parses
args, dispatches agents, aggregates verdicts, presents checkpoints, and hands off.


## Superpowers workflow mapping

This pipeline implements the **planning half** of the canonical superpowers workflow, then
hands off the execution half. Invoke each planning-phase skill via the Skill tool at its mapped
phase. These are **mandatory workflows, not suggestions.** Read `references/superpowers-mapping.md`
for the full table of skills, phases and owners.

Order: `grilling` + `domain-modeling` (0.7), `brainstorming` (1),
the plan format `_shared/plan-format.md` (1.5), `/qa-plan` (2.4, when user flows or screens change), the plan page and
`plannotator annotate --gate` (3). Then handoff to `/deep-execute` or `implement`.

## Phase 0 — Parse args & sanity checks

Run `~/.claude/skills/deep-plan/scripts/parse-args.sh "$ARGUMENTS"` and follow the returned
fields: `task_description`, `ticket` (from `--ticket KEY-123`, else auto-detect: branch name,
last commit body, current Jira/Linear context), `max_plan_iter` (from `--max-plan-iter N`,
default 3, must be 1-20), `no_codex` (`--no-codex`), `skip_grill` (`--skip-grill`), `dry_run`
(`--dry-run`), `roadmap` (`--roadmap PLAN`: plan the next stage of that plan's `## Stages`, per
`~/.claude/skills/_shared/stages.md`; Phase 0.3 copies that section into `related-context.md`). An unknown `--flag`, or `--max-plan-iter` outside 1-20, exits 2 with a message —
surface it to the user verbatim.

Refuse to proceed when the task is trivially small (typo, single one-line change, rename of a single symbol). Tell the user to just do it inline.

Set `RUN_DIR=~/.claude/deep-plan-runs/$(date +%Y%m%d-%H%M%S)-$(echo "$ARGUMENTS" | sha1sum | cut -c1-6)`. Create it with `mkdir -p`. All artifacts (plan drafts, verdicts, final plan) live there.

Create the step file of the run:
`~/.claude/skills/_shared/workflow.sh init "$RUN_DIR/chain.md" deep-plan --project "$PWD"`.
It lists every phase and every step of the build chain. Mark each step when it ends, as
section 0 of `~/.claude/skills/_shared/after-approval.md` says. After each phase, run
`workflow.sh status` and tell the user what is done, what is next and what is left. The Stop
hook `~/.claude/hooks/workflow-gate.sh` blocks the end of a turn while a step is open. Write
the step file path in the `**Step file:**` line of the plan header.

When the user says not to
build ("only plan", "do not implement", "não implementa"), run
`workflow.sh close "$RUN_DIR/chain.md" "plan only"` after the approval. "Stop at the plan for
my approval" is not that: it asks for the gate, and the build starts when the gate approves.

A new change request in the same session, after `close` or after the PR, is a new run of this
skill. Reopen the step file (`workflow.sh reopen <file> "<the close reason>"`), or start a new
run folder, and begin at the first open step. Never write the plan for it outside the skill:
the plan review and the gate run for each change. A hook refuses a plan file in
`docs/superpowers/plans/` when the step file of the session is closed.

Verify binaries: `git`, `claude`, `jq`. Verify `codex` unless `no_codex` is true.

If `dry_run` is true: print the list of phases below with the spawned-agent counts and exit. Do not spawn anything.

## Phase 0.1 — No project edits before approval (mandatory)

Do not use plan mode. Phase 0.2 through Phase 3 touch **no project file**; artifacts go under
`$RUN_DIR`. If a phase seems to need a project edit, it belongs in the plan. The Phase 3
Plannotator gate is the only approval.

## Phase 0.2 — Bootstrap code intelligence (mandatory)

Run `~/.claude/skills/deep-plan/scripts/bootstrap-codeintel.sh "$RUN_DIR"`. Serena needs no
activation call. Read `graphify-out/GRAPH_REPORT.md` when it exists. Surface the index status
to the user in one line. Read `references/phase-0-details.md` before you run this phase.

## Phase 0.3 — Resolve ticket + Slack context

Create `$RUN_DIR/related-context.md` before drafting. Record `Ticket:` and `Slack threads:`.
Use connected ticket and Slack tools when available; inspect the ticket description, comments
and linked threads. Preserve URLs plus one-line relevance. If none exist or access is
unavailable, record where you checked; never fabricate context. With a Jira key, run
`_shared/ticket-start.md` first. `dispatch-planners.sh` and `dispatch-reviewers.sh` include
this artifact when present.

## Phase 0.4 — Is this the right pipeline?

When the change meets the lean criteria of `~/.claude/skills/_shared/plan-routing.md`, recommend
`/simple-plan` and follow the question rules there. When it is large but splits into slices that
ship in one PR, recommend stages (`_shared/stages.md`) in the same question. Say nothing when the
change is genuinely large with no such slices. Read `references/phase-0-details.md` before you ask.

## Phase 0.5 — Clarifying questions (mandatory)

Before any grill or draft, surface every ambiguity with `AskUserQuestion` and focused options.
Record every Q/A pair in `## Clarifying questions` with `### Q:` / `### A:` headers. The
validator requires at least 1 matched pair. Write exactly `_no ambiguity_` and skip the
questions only when the task is genuinely unambiguous. This must be rare. Read
`references/phase-0-details.md` before you ask.

## Phase 0.7 — Grill-with-docs deep interview (mandatory unless `--skip-grill`)

1. Run `Skill(skill="mattpocock-skills:grilling")`, then
   `Skill(skill="mattpocock-skills:domain-modeling")`. Never call `grill-with-docs`: the Skill
   tool refuses it.
2. Record the transcript under `## Grill-with-docs transcript` with `### Q:` / `### A:` headers.
   Fold the resolved decisions into `## Rationale & key decisions`.
3. Run `~/.claude/skills/deep-plan/scripts/superpowers-invoke.sh "$RUN_DIR" grill-with-docs`.

With `--skip-grill`, still record `grill-with-docs` in the Superpowers section as `[ ]`. Read
`references/phase-0-details.md` before this phase.

## Phase 1 — Brainstorm intake (superpowers:brainstorming)

Before any draft, invoke `superpowers:brainstorming` via the Skill tool against the task
description. Its output seeds `Context` and `Rationale & key decisions`, and goes verbatim to both
planners. Then run `~/.claude/skills/deep-plan/scripts/superpowers-invoke.sh "$RUN_DIR" brainstorming`.

## Phase 1.5 — Two-track planner drafting (plan format)

`~/.claude/skills/_shared/plan-format.md` is the **single source of truth** for the plan's shape. Do not invoke
`superpowers:writing-plans`: its header and its execution handoff stop the build chain. Read the
plan format on every run, then record it with `superpowers-invoke.sh "$RUN_DIR" writing-plans`
(the receipt keeps its old name). `templates/plan.md` only adds deep-plan's extra sections.

1. Read `~/.claude/skills/_shared/plan-format.md`.
2. Record the receipt.
3. Start the `ui-designer` agent as an Orca worker with `--keep-open` when the change touches an
   interface. When it hands over `copy.tsv`, run the `copy-reviewer` agent on that file only,
   and send its table back to the worker.
4. Run `~/.claude/skills/deep-plan/scripts/dispatch-planners.sh "$RUN_DIR" "$TASK_DESC"`. It runs
   the Opus planner and the Codex planner (skipped with `--no-codex`) headless, in parallel.
5. Synthesize **one** merged plan into `$RUN_DIR/plan.md`. Resolve disagreements by keeping the
   stricter requirement.
6. Check the size: `wc -c "$RUN_DIR/plan.md"`. Above 100 KB, split the change into stages
   (`_shared/stages.md`), one PR each. Plan only the first stage now, and move the other stages
   to `## Stages`. Each review round reads the whole plan, and the user must read it at the gate.

**TDD & mocking policy the plan MUST encode** (into `## TDD test list`): the build follows strict
red-green-refactor, and mocks **only the outermost boundaries** (network, 3rd-party APIs,
clock/random). Inner services, repositories, and domain logic run **real** code in tests.

Read `references/planner-drafting.md` before you start step 3.

## Phase 2 — Review loop (≤ `--max-plan-iter`)

When the repository workflow has a plan review stage (`_shared/repo-workflow.md`), run that
stage instead of this loop.

1. Run `dispatch-reviewers.sh "$RUN_DIR" "$ITER"`. It starts the Sonnet and Codex reviewers in
   parallel. Each writes `verdict-<persona>-iter<N>.json`.
2. Run `aggregate-verdicts.sh "$RUN_DIR" "$ITER"`. Exit 0 means all APPROVED: go to Phase 3.
   Exit 1 means continue.
3. Apply the consolidated `proposed_edits` to `plan.md`. Replace the text that an edit
   changes; do not append a second version. Record the plan size of the round in the step
   note: `workflow.sh wait "$RUN_DIR/chain.md" plan-review "round $ITER, $(wc -c < "$RUN_DIR/plan.md") bytes"`.
   Increment ITER. Loop.
4. If ITER > `--max-plan-iter`: use `AskUserQuestion` to present the remaining disagreements per
   persona. Apply the user decisions to `plan.md`. Treat as approved.

Read `references/review-loop.md` before you run step 1.

## Phase 2.4 — QA plan artifact

After reviewer convergence, when the QA flag is yes, invoke `qa-test-plan` with `--phase plan`.
Write the validated `qa-plan.yaml` path into the plan's `- QA plan:` line. For QA flag no, write
`- QA plan: not applicable — <reason>`. Details: `references/review-loop.md`.

## Phase 2.5 — Subplan fan-out

After the root plan is reviewer-approved, run
`~/.claude/skills/deep-plan/scripts/subplan-fanout.sh "$RUN_DIR" --max-chapters 5`. Run a reduced
review loop per subplan (2 iterations max). Mark a failed subplan `[CHANGES_REQUESTED]`, continue,
and surface it as a warning in Phase 3. Details: `references/review-loop.md`.

## Phase 3 — Validate gate, annotate & present plan

Run `~/.claude/skills/deep-plan/scripts/finalize-plan.sh "$RUN_DIR"`. It gates the root plan and
every subplan on `validate-plan.sh`, repairs up to 3 rounds, and ticks the checklist only once every
file passes. **`RUN_DIR/finalize-failures.json` is a hard gate: read it, fix, rerun
`finalize-plan.sh` — never advance on a `status: fail`.** If it still fails after its own 3 rounds,
use `AskUserQuestion` for a tiebreak on the named failures.

`finalize-plan.sh` (via `tick-checklist.sh`) is the only thing permitted to tick a `## Checklist`
box. `scripts/superpowers-invoke.sh "$RUN_DIR" <skill>` — called **after** you invoke the skill via
the Skill tool — is the only thing permitted to tick a `## Superpowers invoked` box. **Never
hand-edit either.** The tick is a tamper-evident receipt: it
proves the script ran, not that the skill itself ran.

The plan must contain every required section, including a **Product design handoff prompt** for
substantial UI and the `related-context.md` links. Read
`references/plan-gate-and-presentation.md` for the exact list, the diagram rules and the
Plannotator steps. If a section is missing, loop back once into Phase 2 with a synthetic
CHANGES_REQUESTED verdict that names it.

Render the plan page per `~/.claude/skills/_shared/plan-page.md`. Present the plan through
Plannotator, never as a terminal wall of text:

1. `plannotator annotate "$RUN_DIR/plan.html" --gate`. Address **every** annotation in `plan.md`,
   rerun `finalize-plan.sh`, re-render, reopen. Loop until approved with no annotations. Record it
   with `superpowers-invoke.sh "$RUN_DIR" plannotator-annotate`. That pass is the approval.
2. Print the humanized summary in the chat: goal, approach, key decisions, risks, sequence, and
   the link to `$RUN_DIR/plan.md`.

When the user delegated the approval ("deliver it", "do not wait for me") and you pass the gate
for them, record it in `decisions.md`. Then send one Inbox thread with every row of
`decisions.md` as a `:::question` block (`_shared/inbox.md`, "Decisions during a build chain"),
and put the thread link in the evidence of the `gate` step. A gate passed for the user with no
Inbox thread is not done.

Do **not** paste the full `plan.md` into the chat.

## Phase 3.5 — Execution recommendation (mandatory)

The approval is the go. Pick **how** to build, then build.

1. **Re-gate:** `(cd "$PROJECT_ROOT" && validate-plan.sh "$RUN_DIR/plan.md" --root --json)`. Any
   `fail` goes back to `finalize-plan.sh`. Never offer option A on a plan that `init-run.sh` rejects.
2. **Publish and stamp:** `PLAN=$(publish-plan.sh "$RUN_DIR" "$PROJECT_ROOT/docs/superpowers/plans/YYYY-MM-DD-<slug>")`,
   per `_shared/spec-evidence.md` sections 1-2. Commit the folder. `$PLAN` is the plan from here on.
3. Write `$RUN_DIR/execution-recommendation.md`: recommendation first, then the options this
   harness offers. Pick with the executor section of `_shared/plan-routing.md`. Show it, then run
   it without a question. Option C asks its ultracode question here, before Phase 4.
4. Record the choice under `## Chosen`.

Options (Claude Code offers all four, Codex offers A and B only):
- **A — `/deep-execute "$PLAN"`:** parallel lane workers in Orca terminals.
- **B — serial** via `implement`: one implementer worker per task, in order, strict TDD.
- **C — Claude `Workflow` (ultracode), Claude Code only:** needs the user's opt-in.
- **D — Codex-only implementer, Claude Code only:** `codex exec -m gpt-6.1-terra` writes the code.

Read `references/execution-recommendation.md` before you write the recommendation.

### The planning session is an orchestrator, not an implementer

Default and non-negotiable: the session that ran `/deep-plan` **directs and reviews**; it does not
write feature code. It dispatches lanes, workers and Codex, answers their questions, gates their
rounds, routes review findings back to the agent that owns the code, and commits. If you are about
to edit a project file that no worker owns, stop: that edit belongs to a lane. The session writes
feature code only when the user asks for that in so many words.

## Phase 4 — Build, review, QA, PR

Follow `~/.claude/skills/_shared/after-approval.md`. Option A runs `/deep-execute "$PLAN"`, which
runs the chain itself. Stop at the plan only when the user said so. When `.workflow/config.json`
exists, first run `Skill(skill="workflow-post-plan")` with the last Phase 2 verdicts as evidence.

## Reuse

Flag patterns for `claude -p` / `codex exec`: `~/.claude/skills/deep-review/scripts/reviewer.sh`.
TDD enforcement: `superpowers:test-driven-development`.

## Failure modes

- A spawned agent times out: mark its verdict CHANGES_REQUESTED with note "timeout", continue.
- Plan iter cap reached with disagreements: `AskUserQuestion` tiebreak; never silently force-approve.
- `plannotator` CLI missing: say so, print the humanized summary inline (never the whole `plan.md`),
  point at the file path, and ask for approval with `AskUserQuestion` (in Codex, ask in the chat
  and wait). Install: `curl -fsSL https://plannotator.ai/install.sh | bash`.
- `plannotator annotate --gate` exits without feedback: treat as approved, note it, continue.

## Long or multi-day planning

`$RUN_DIR` holds every draft, verdict and the plan, so a fresh session resumes from it. Before
`/clear` on multi-day work, offer the user `/mattpocock-skills:handoff` and name `$RUN_DIR` in it.
