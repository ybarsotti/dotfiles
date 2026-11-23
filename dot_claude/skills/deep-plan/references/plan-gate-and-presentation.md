# Plan gate and presentation details

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

The plan is always reviewed in the Plannotator UI:

1. **Gate the plan page.** `plannotator annotate "$RUN_DIR/plan.html" --gate` blocks until the
   user approves or returns annotations. Address **every** annotation in `plan.md`, re-run
   `finalize-plan.sh` (validate + tick together), re-render the page, then re-open it. Loop
   until the user approves with no annotations. Record it:
   ```
   ~/.claude/skills/deep-plan/scripts/superpowers-invoke.sh "$RUN_DIR" plannotator-annotate
   ```

   The gate pass that returns no annotations is the approval.

2. **Print the summary.** Print the humanized distillation in the chat: goal, approach, key
   decisions, risks, sequence, and the link to `$RUN_DIR/plan.md`. Do not call
   `ExitPlanMode`.

Do **not** paste the full `plan.md` into the chat — the file path plus the humanized summary
is what the user reads; Plannotator carries the detail.
