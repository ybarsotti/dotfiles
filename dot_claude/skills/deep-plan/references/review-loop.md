# Review loop, QA plan and subplan details

## Phase 2 — Review loop (≤ `--max-plan-iter`)

Loop, starting at iteration 1:

1. Run `~/.claude/skills/deep-plan/scripts/dispatch-reviewers.sh "$RUN_DIR" "$ITER"`. It launches in parallel:
   - Claude **Sonnet** reviewers: `personas/architect.md`, `personas/project-developer.md`, `personas/ticket-matcher.md`
   - Codex reviewers: `personas/flow-mapper.md`, `personas/qa.md` *(use Claude/Sonnet when `--no-codex`)*
   - When the plan has a `## Query cost` table or a schema change, also run the data reviewer of
     `simple-plan` Phase 3 as an `Agent`. Treat its findings as `proposed_edits`.

   Reviewers are always **Sonnet** on the Claude side; the Codex side runs `gpt-6.1-sol` at
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
