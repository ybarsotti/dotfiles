---
name: deep-plan
description: Multi-agent deep-planning pipeline with ticket/Slack context, requirements traceability, user journey, data model and product-design handoff. Use when invoked via /deep-plan, or when the user wants a deeply reviewed plan before code for a non-trivial feature, refactor or architecture change. Parallel Opus + Codex planners and five reviewers converge before Plannotator approval. After approval it builds, reviews, runs QA, opens the PR and delivers an HTML report unless the user said to stop at the plan.
---

# deep-plan

You are the **orchestrator** of a multi-agent **deep-planning** pipeline. Your job is to
coordinate planning and review, then present an approved plan and hand off. You do **not**
draft the plan yourself, and you do **not** build, review the code, or open the PR — those
happen in the **execution phase**, driven by `/deep-execute` after approval. deep-plan parses
args, dispatches agents, aggregates verdicts, presents checkpoints, and hands off.

## Superpowers workflow mapping

This pipeline implements the **planning half** of the canonical
[obra/superpowers](https://github.com/obra/superpowers) workflow, then hands off the
execution half. Invoke each planning-phase skill via the Skill tool at its mapped phase —
**mandatory workflows, not suggestions.**

| # | superpowers / skill | deep-plan phase | run by |
|---|---------------------|----------------|--------|
| ✳ | `EnterPlanMode` (plan mode on) | Phase 0.1 | deep-plan |
| 0 | `grilling` + `domain-modeling` | Phase 0.7 | deep-plan |
| 1 | `brainstorming` | Phase 1 | deep-plan |
| 2 | `writing-plans` | Phase 1.5 | deep-plan |
| 2b| `/qa-plan` | Phase 2.4 when user flows/screens change | deep-plan |
| 3 | `_shared/plan-page.md` (plan page) | Phase 3 (present) | deep-plan |
| 4 | `plannotator annotate --gate` | Phase 3 (annotate) | deep-plan |
| — | — | **handoff** ↓ | **`/deep-execute` or `implement`** |
| 4 | `using-git-worktrees` | execution | executor |
| 5 | `subagent-driven-development` / `executing-plans` | execution | executor |
| 6 | `test-driven-development` | execution (per task) | executor |
| 6b| `systematic-debugging` | execution (bug/regression tasks) | executor |
| 6c| `dispatching-parallel-agents` | execution (fallback for parallel slices) | executor |
| 7 | `/deep-review` + `receiving-code-review` + `qa-ui`/`qa-business` agents | execution | after-approval |
| 8 | `/pr` + `finishing-a-development-branch` | execution | after-approval |

Plus deep-plan adds: multi-model planner/reviewer fan-out, the `ticket-matcher` reviewer,
code-intel bootstrap, and the machine-validated checklist gate.

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

Verify binaries: `git`, `claude`, `jq`. Verify `codex` unless `no_codex` is true.

If `dry_run` is true: print the list of phases below with the spawned-agent counts and exit. Do not spawn anything.

## Phase 0.1 — Enter plan mode (mandatory)

**Before any exploration, bootstrap, question, or draft**, switch the session into plan mode:

```
EnterPlanMode()
```

Everything from Phase 0.2 through Phase 3 runs **inside plan mode** — deep-plan reads, indexes,
interviews and writes plan artifacts under `$RUN_DIR`, and touches **no project file**. Plan
mode is also what makes the Plannotator `ExitPlanMode` hook fire at Phase 3, so the user
approves the plan in the Plannotator UI instead of a terminal wall of text.

If the session is already in plan mode, skip the call. Never leave plan mode before the Phase 3
`ExitPlanMode` — if a phase seems to need a project edit, it belongs in the plan, not in this run.

## Phase 0.2 — Bootstrap code intelligence (mandatory)

Refresh local code-intel indexes so planners + reviewers use semantic tools instead of grepping raw files.

1. Run:
   ```
   ~/.claude/skills/deep-plan/scripts/bootstrap-codeintel.sh "$RUN_DIR"
   ```
   This re-runs `gitnexus analyze` if `.gitnexus/` exists, `graphify update .` if `graphify-out/graph.json` exists, and writes `$RUN_DIR/codeintel-status.json`.

2. Activate Serena for the current project via the MCP tool (the script can't issue MCP calls):
   ```
   mcp__plugin_serena_serena__activate_project(path=<repo root>)
   ```

3. If `graphify-out/GRAPH_REPORT.md` exists, read it for the "god nodes" + community summary before drafting — saves a planner pass.

4. Surface index status to the user in one line, e.g. `code-intel: gitnexus=fresh graphify=fresh serena=activated`.

The persona prompts (planner-opus, planner-codex, architect, project-developer, qa, ticket-matcher) all prefer these tools over raw `grep`/`find`:
- `mcp__plugin_serena_serena__find_symbol`, `find_referencing_symbols`, `replace_symbol_body`
- `gitnexus_query`, `gitnexus_context`, `gitnexus_impact`, `gitnexus_rename`, `gitnexus_detect_changes`
- `graphify path/explain` for cross-symbol reasoning

## Phase 0.3 — Resolve ticket + Slack context

Create `$RUN_DIR/related-context.md` before drafting. Record `Ticket:` and `Slack threads:`.
Use connected ticket/Slack tools when available; inspect ticket description/comments and linked
threads. Preserve URLs plus one-line relevance. If none exist or access is unavailable, record
where you checked; never fabricate context. With a Jira key, run `_shared/ticket-start.md` first. `dispatch-planners.sh` and
`dispatch-reviewers.sh` include this artifact when present.

## Phase 0.4 — Is this the right pipeline?

The code intelligence from Phase 0.2 says how large the change really is. When it meets the
lean criteria of `~/.claude/skills/_shared/plan-routing.md`, recommend `/simple-plan` instead
and follow the question rules there. Continue or stop on the user's answer.

When it is large but splits into working slices that ship in one PR, recommend stages
(`_shared/stages.md`) in the same question. Say nothing here when the change is genuinely large
and has no such slices. `deep-plan` is the default for this
command, and a recommendation that always fires teaches the user to skip it.

## Phase 0.5 — Clarifying questions (mandatory)

Before any grill or draft, surface every ambiguity in the task description to the user. Use `AskUserQuestion` with focused options (no open-ended prose questions when a multiple-choice will do).

Examples of things to clarify: scope boundaries, personas/targets, trade-off preferences (speed vs correctness, minimal-diff vs refactor), acceptance criteria.

Record every Q/A pair in `## Clarifying questions` using `### Q:` / `### A:` headers. The validator requires ≥1 matched pair.

If — and only if — the task is genuinely unambiguous after a careful re-read, write exactly `_no ambiguity_` in the section and skip questions. This must be rare; the default is to ask.

## Phase 0.7 — Grill-with-docs deep interview (mandatory unless `--skip-grill`)

After the multiple-choice clarifications resolve the obvious gaps, drill harder and capture the reasoning as docs.

**Step 1 — run its two halves:** `Skill(skill="mattpocock-skills:grilling")`, then
`Skill(skill="mattpocock-skills:domain-modeling")`. Not `grill-with-docs` — it is
`disable-model-invocation` and the Skill tool refuses it; these two are the halves it composes,
both model-invokable by their author's own frontmatter. Offer the user
`/mattpocock-skills:grill-with-docs` when they would rather drive it. Phase 0.5 was the
multiple-choice sweep; this is the open-ended stress test feeding `## Rationale & key decisions`.

**Step 2 — record the transcript** in the plan under `## Grill-with-docs transcript` using `### Q:` / `### A:` headers (same format as clarifying questions, so the validator counts them too). Fold the resolved decisions into `## Rationale & key decisions`.

**Step 3 — mark invocation:**
```
~/.claude/skills/deep-plan/scripts/superpowers-invoke.sh "$RUN_DIR" grill-with-docs
```

If the user passes `--skip-grill`, still record `grill-with-docs` in the Superpowers section as `[ ]` so the checklist surfaces the skip.

## Phase 1 — Brainstorm intake (superpowers:brainstorming)

Before any draft, invoke `superpowers:brainstorming` via the Skill tool against the task description. The brainstorming output (intent, alternatives, key constraints) becomes the seed for the `Context` + `Rationale & key decisions` sections and is passed verbatim to both planners in Phase 1.5.

After it returns, run:
```
~/.claude/skills/deep-plan/scripts/superpowers-invoke.sh "$RUN_DIR" brainstorming
```

## Phase 1.5 — Two-track planner drafting (superpowers:writing-plans)

`superpowers:writing-plans` is the **single source of truth** for the plan's shape — the
document header, the File Structure step, task right-sizing, the `### Task N:` blocks with
their bite-sized checkbox steps, and the no-placeholder rules. deep-plan never restates or
paraphrases those rules: it **invokes the skill** and follows what it returns, on every run.
`templates/plan.md` only adds deep-plan's extra sections (requirements, journey, data model,
design handoff, context links, clarifying Qs, flow, rationale, QA flag, checklist) around it.

**Step 1 — invoke the skill via the Skill tool:**
```
Skill(skill="superpowers:writing-plans")
```

**Step 2 — record the invocation:**
```
~/.claude/skills/deep-plan/scripts/superpowers-invoke.sh "$RUN_DIR" writing-plans
```

**Step 3 — start the designer, when the change touches an interface.** Start the
`ui-designer` agent as an Orca worker with `--keep-open` (`_shared/after-approval.md`, "Parallel
agents run in Orca"). Give it the ticket, the task and `$RUN_DIR/design/`. It draws while the
planners draft. Put its `Canvas:` and `Design system:` URLs in the UI design pass before Phase 3.

**Step 4 — dispatch:**
```
~/.claude/skills/deep-plan/scripts/dispatch-planners.sh "$RUN_DIR" "$TASK_DESC"
```

The dispatcher spawns in parallel:
- `claude -p` (Opus) loaded with `personas/planner-opus.md`
- `codex exec` (latest) loaded with `personas/planner-codex.md` *(skipped if `--no-codex`)*

Both are told to **load `writing-plans` themselves** before drafting (the Claude planner via
the Skill tool, the codex planner by reading the resolved skill path) — the dispatcher passes
a pointer, never a copy of the skill body. Both receive the task description +
`templates/plan.md` as their skeleton. Each writes its draft to `$RUN_DIR/draft-opus.md` and `$RUN_DIR/draft-codex.md`.

When both return, synthesize **one** merged candidate plan into `$RUN_DIR/plan.md` using the template. Prefer the Opus draft's architecture framing, the Codex draft's codebase-grounded specifics. Resolve disagreements by keeping the stricter requirement.

**TDD & mocking policy the plan MUST encode** (into `## TDD test list`): the build follows strict red-green-refactor, and mocks **only the outermost boundaries** (network, 3rd-party APIs, clock/random). Inner services, repositories, and domain logic run **real** code in tests — do not mock every service.

## Phase 2 — Review loop (≤ `--max-plan-iter`)

Loop, starting at iteration 1:

1. Run `~/.claude/skills/deep-plan/scripts/dispatch-reviewers.sh "$RUN_DIR" "$ITER"`. It launches in parallel:
   - Claude **Sonnet** reviewers: `personas/architect.md`, `personas/project-developer.md`, `personas/ticket-matcher.md`
   - Codex reviewers: `personas/flow-mapper.md`, `personas/qa.md` *(use Claude/Sonnet when `--no-codex`)*
   - When the plan has a `## Query cost` table or a schema change, also run the data reviewer of
     `simple-plan` Phase 3 as an `Agent`. Treat its findings as `proposed_edits`.

   Reviewers are always **Sonnet** on the Claude side; the Codex side runs `gpt-6-sol` at
   `model_reasoning_effort=high` (pinned in `scripts/runner.sh`, overridable with
   `DEEP_PLAN_CODEX_MODEL` / `DEEP_PLAN_CODEX_EFFORT`). Each persona gets `plan.md`, the project's `CLAUDE.md`, the ticket body (when a ticket is set), and a short context snapshot. Each writes a verdict JSON to `$RUN_DIR/verdict-<persona>-iter<N>.json`:

   ```json
   {
     "persona": "architect",
     "verdict": "APPROVED" | "CHANGES_REQUESTED",
     "notes": "...",
     "proposed_edits": [{"section": "...", "change": "..."}]
   }
   ```

   The **ticket-matcher** reviewer reads the linked ticket and matches the plan **point-by-point** against every acceptance criterion; it requests changes when the plan is **vague**, misses a criterion, or over-reaches beyond the ticket.

2. Run `~/.claude/skills/deep-plan/scripts/aggregate-verdicts.sh "$RUN_DIR" "$ITER"`.
   - Exit 0 → all reviewers APPROVED → break loop, advance to Phase 3.
   - Exit 1 → at least one CHANGES_REQUESTED → continue.

3. If continuing: apply the consolidated `proposed_edits` to `plan.md`. Increment ITER. Loop.

4. If ITER > `--max-plan-iter`: stop the loop. Use `AskUserQuestion` to present the **remaining disagreements** (per persona) and ask the user to tiebreak each one. Apply user decisions to `plan.md`. Treat as approved.

## Phase 2.4 — QA plan artifact
After reviewer convergence, when QA flag is yes invoke `qa-test-plan` with
`--phase plan --plan $RUN_DIR/plan.md --ticket $TICKET --output-dir $RUN_DIR/qa`.
Require validated `$RUN_DIR/qa/qa-plan.yaml`, derived Markdown, and Codex review; write that YAML path into plan's `- QA plan:` line. For QA flag no, write
`- QA plan: not applicable — <reason>`. `/deep-execute` consumes approved contract later.
## Phase 2.5 — Subplan fan-out

After root plan reviewer-approved, split it into chapters:
```
~/.claude/skills/deep-plan/scripts/subplan-fanout.sh "$RUN_DIR" --max-chapters 5
```
This groups `## Affected files` by top-level directory, emits `$RUN_DIR/subplans/<chapter>.md`, and updates the `## Subplans` section in `plan.md` with links.

For each subplan: run a **reduced** review loop — `project-developer` (Sonnet) + `qa` (Codex; or Sonnet if `--no-codex`), 2 iterations max. Failed subplan (still CHANGES_REQUESTED after iter 2) → mark the link with a trailing `[CHANGES_REQUESTED]`, continue, and surface as a warning in Phase 3.

## Phase 3 — Validate gate, annotate & present plan

Run `~/.claude/skills/deep-plan/scripts/finalize-plan.sh "$RUN_DIR"`. It gates the root plan
and every `subplans/*.md` on `validate-plan.sh`, auto-recovers up to 3 repair rounds through an
Opus planner, and — only once every file fully passes — ticks the checklist via
`tick-checklist.sh`. **Failing JSON (`RUN_DIR/finalize-failures.json`) is a hard gate: read it,
fix, rerun `finalize-plan.sh` — never advance on a `status: fail`.** If it still fails after its
own 3 rounds, fall through to `AskUserQuestion` for tiebreak on the named failures.

The checklist and `## Superpowers invoked` boxes are machine-ticked only — `finalize-plan.sh`
(via `tick-checklist.sh`) is the only thing permitted to tick a `## Checklist` box, and
`scripts/superpowers-invoke.sh "$RUN_DIR" <skill>` — called **after** actually invoking the
skill via the Skill tool — is the only thing permitted to tick a `## Superpowers invoked` box.
**Never hand-edit either.** The tick is a tamper-evident receipt (hash-chained, anchored to the
repo's HEAD commit): it proves the script ran, not that the skill itself ran — see the header
of `scripts/superpowers-invoke.sh` for the full guarantee.

Confirm the plan includes, at minimum:
- The **`superpowers:writing-plans` document header** + an **`## Implementation tasks`** section in that skill's exact task format (`### Task N:` + Files + Interfaces + bite-sized checkbox steps with real code).
- A **Mermaid flow diagram** (sequence or flowchart) under `## Flow diagram` — required. It
  shows the runtime path.
- An **`## Architecture diagram`** (`classDiagram` or `C4Component`) whenever the change adds
  or reshapes a type, module, service or boundary — the structure the flow diagram cannot
  show. `Applies: no` + a reason when the change stays inside existing functions.
- An **`erDiagram`** under `## Data model` whenever `Schema changes: yes`. The column table
  says where each value comes from, row by row; the diagram is the shape. Every table in the
  table's `action` column needs an attribute block listing its columns, each new or altered
  one marked `"new"` / `"altered"`, plus the untouched tables it points at so the cardinality
  reads. No separate flag — the schema answer is the flag.
- A **`## State diagram`** when the change introduces or alters a state machine; `Applies: no`
  + a reason otherwise.

> Every diagram check above is a regex — it proves a diagram is present and roughly shaped
> right, never that it renders. `validate-plan.sh` adds `mermaid-parses`, which runs the real
> parser, but only when `mermaid-validate` is on PATH; without it the item records **skip**,
> never pass. Install it once so broken syntax fails here instead of reaching Plannotator and
> the PR as a blank box: `npm i -g @zabaca/mermaid-validate`.
- A **Rationale & key decisions** section (fed by grill-with-docs + brainstorming).
- **Ticket + Slack context**, a point-by-point **Requirements matrix** with its ticket coverage line, and a **Work size** table.
- A sequenced **User journey** when applicable; otherwise an explicit reason.
- A **Data model** mapping every affected table/column to its value source and the deploy order, or explicit `no`, and a **Query cost** table per `_shared/query-check.md`, or `no`.
- **Rules**, **Removed contracts** and **Stages** filled or `no` with a reason; edge cases carry `EC-NNN` IDs.
- A **UI design pass** held to `~/.claude/skills/_shared/ui-quality.md` for any UI change, and a copyable **Product design handoff prompt** for substantial UI; explicit `no` for each otherwise.
- A **TDD test list** with the outer-boundary-only mocking policy stated.
- An **Abstractions decision log**.
- An **Evidence map**: one proof per requirement, rule and Cover now/Fail loudly edge case.
- A **Documentation impact** section (docs/ that go stale must be updated, or `none`).
- A **QA / test-execution** flag ("changes flows or adds screens? yes/no").
- A **Verification** section.

If any are missing, loop back once into Phase 2 with a synthetic CHANGES_REQUESTED verdict naming the missing artifact.

**Plan page:** render the humanized `$RUN_DIR/plan.html`, gate it and decide where it lives per `~/.claude/skills/_shared/plan-page.md`.

**Present the plan through Plannotator (mandatory — never a terminal wall of text):**

The plan is always reviewed in the Plannotator UI, in two passes:

1. **Gate the plan page.** `plannotator annotate "$RUN_DIR/plan.html" --gate` blocks until the
   user approves or returns annotations. Address **every** annotation in `plan.md`, re-run
   `finalize-plan.sh` (validate + tick together), re-render the page, then re-open it. Loop
   until the user approves with no annotations. Record it:
   ```
   ~/.claude/skills/deep-plan/scripts/superpowers-invoke.sh "$RUN_DIR" plannotator-annotate
   ```

2. **Approve the plan-mode summary.** Call `ExitPlanMode` with the humanized distillation
   (goal, approach, key decisions, risks, sequence, link to `$RUN_DIR/plan.md`). With the
   `plannotator` plugin enabled, its `PermissionRequest` hook intercepts `ExitPlanMode` and
   opens the same UI for the final approve / request-changes; on request-changes the
   annotations come back — apply them and call `ExitPlanMode` again (Plannotator shows the
   plan diff between submissions). If the plugin is not installed, `ExitPlanMode` just
   behaves normally and pass 1 was the annotation gate.

Do **not** paste the full `plan.md` into the chat — the file path plus the humanized summary
is what the user reads; Plannotator carries the detail.

## Phase 3.5 — Execution recommendation (mandatory)

The plan is approved, and the approval is the go. Pick **how** it gets built from the plan, then build.

**Re-gate first.** Plannotator's second pass can edit the plan after the last
`finalize-plan.sh`, and `/deep-execute`'s `init-run.sh` re-runs the same check from the project
root — so run it there, now: `(cd "$PROJECT_ROOT" && validate-plan.sh "$RUN_DIR/plan.md" --root
--json)`. Any `fail` goes back to `finalize-plan.sh`. Never offer option A on a plan that
`init-run.sh` will reject; that failure belongs here, not after the user asks to build.

**Publish and stamp the approved plan** (`~/.claude/skills/_shared/spec-evidence.md` sections 1–2):
`PLAN=$(publish-plan.sh "$RUN_DIR" "$PROJECT_ROOT/docs/superpowers/plans/YYYY-MM-DD-<slug>")`. It
copies the plan with the files `validate-plan.sh --root` reads, stamps and re-validates the copy;
commit the folder. `$PLAN` is the plan from here on: every handoff names it, and execution
appends to its `## Deviations`.

Write `$RUN_DIR/execution-recommendation.md` — recommendation first, then the four options
with the trade-off that decides between them. Pick the recommendation with the executor
section of `~/.claude/skills/_shared/plan-routing.md`. Do not ask the user: it runs. Option C
is the exception: ask its ultracode question here, before Phase 4, as `plan-routing.md` says.

The four options, each stated to the user with what it costs:

- **A — `/deep-execute "$PLAN"`.** Parallel lane workers in Orca terminals, one shared
  worktree, round gating, contract drift handling, one full `/deep-review`, QA, run report,
  PR. Most machinery, most parallelism; needs disjoint lanes and a real contract.
- **B — serial** via the `implement` skill (`superpowers:subagent-driven-development`): one
  implementer agent per task, in order, strict TDD per task. This session reviews each task.
- **C — Claude `Workflow` (ultracode).** Parallel worktrees with adversarial review and no
  lane terminals, but no human input during a run. Needs the user's opt-in; test in `plan-routing.md`.
- **D — Codex-only implementer.** `codex exec` writes the code; this session orchestrates,
  gates, reviews and commits. Use when the change is one coherent slice and you want a
  second model's hands on the implementation.

Record the chosen option in `$RUN_DIR/execution-recommendation.md` under `## Chosen`.

### The planning session is an orchestrator, not an implementer

Default and non-negotiable: the session that ran
`/deep-plan` **directs and reviews**; it does not write feature code. It dispatches lanes /
workers / Codex, answers their questions, gates their rounds, applies review findings by
routing them back to the agent that owns the code, and commits. If you catch yourself about
to edit a project file that no worker owns, stop — that edit belongs to a lane, and taking it
yourself destroys both the ownership boundary `validate-run-state.sh` enforces and the record
of who decided what.

The session writes feature code only when the user asks for that in so many words.

## Phase 4 — Build, review, QA, PR

Follow `~/.claude/skills/_shared/after-approval.md`. Option A runs `/deep-execute "$PLAN"`, which
runs the chain itself. Stop at the plan only when the user said so.
When `.workflow/config.json` exists, first run `Skill(skill="workflow-post-plan")` with the last Phase 2 verdicts as evidence.

## Reuse

- Patterns for `claude -p` / `codex exec` flags: `~/.claude/skills/deep-review/scripts/reviewer.sh`.
- Post-approval build/review/PR helpers live in this skill's `scripts/` (`feature-branch.sh`, `pr-open.sh`, `ci-and-copilot-watch.sh`, `handle-findings.sh`) and are consumed by `/pr` and `jira-workflow` — not by deep-plan itself.
- TDD enforcement: `superpowers:test-driven-development`.

## Failure modes

- A spawned agent times out → mark its verdict CHANGES_REQUESTED with note "timeout", continue.
- Plan iter cap reached with disagreements → `AskUserQuestion` tiebreak; never silently force-approve.
- `plannotator` CLI missing → say so, print the humanized summary inline (never the whole `plan.md`), point at the file path, and proceed to `ExitPlanMode`. Install: `curl -fsSL https://plannotator.ai/install.sh | bash`.
- `plannotator annotate --gate` exits without feedback → treat as approved, note it, continue.
- Not in plan mode at Phase 3 (session started outside it) → still run the `annotate --gate` pass; skip `ExitPlanMode`.

## Long or multi-day planning

`$RUN_DIR` holds every draft, verdict and the plan, so a fresh session resumes from it. Before
`/clear` on multi-day work, offer the user `/mattpocock-skills:handoff` and name `$RUN_DIR` in it.
