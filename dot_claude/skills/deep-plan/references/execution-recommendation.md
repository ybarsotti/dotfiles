# Execution recommendation details

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
section of `~/.claude/skills/_shared/plan-routing.md`. Show it to the user as that section
says, then run it without a question. Option C is the exception: ask its ultracode question
here, before Phase 4, as `plan-routing.md` says.

The options depend on the harness: Claude Code offers all four, Codex offers A and B only
(`plan-routing.md`). State each option this harness offers with what it costs:

- **A — `/deep-execute "$PLAN"`.** Parallel lane workers in Orca terminals, one shared
  worktree, round gating, contract drift handling, one full `/deep-review`, QA, run report,
  PR. Most machinery, most parallelism; needs disjoint lanes and a real contract.
- **B — serial** via the `implement` skill: one implementer worker per task, in order, strict
  TDD per task. Each worker runs in its own Orca pane (`_shared/orca-workers.md`); outside Orca
  it is a subagent. This session reviews each task.
- **C — Claude `Workflow` (ultracode), Claude Code only.** Parallel worktrees with adversarial review and no
  lane terminals, but no human input during a run. Needs the user's opt-in; test in `plan-routing.md`.
- **D — Codex-only implementer, Claude Code only.** `codex exec -m gpt-6.1-terra` writes the code; this session orchestrates,
  gates, reviews and commits. Use when the change is one coherent slice and you want a
  second model's hands on the implementation.

Record the chosen option in `$RUN_DIR/execution-recommendation.md` under `## Chosen`.
