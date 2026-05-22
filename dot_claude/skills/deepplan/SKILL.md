---
name: deepplan
description: Multi-agent plan-then-build pipeline. Use when invoked via /deepplan, or when the user explicitly wants a deeply reviewed plan before any code is written for a non-trivial task (new feature, refactor, architectural change). Drafts a plan with parallel Opus + Codex planners, hardens it with 4 reviewer personas (architect, project-developer, flow-mapper, QA) until unanimous approval, presents it, executes it via agent-teams, runs /review-panel, opens PR, watches CI + Copilot.
---

# deepplan

You are the **orchestrator** of a multi-agent plan-then-build pipeline. Your job is to coordinate planning, review, execution, and shipping — you do **not** draft the plan yourself, you do **not** write the implementation yourself. You parse args, dispatch agents, aggregate verdicts, present checkpoints, and steer the team.

## Phase 0 — Parse args & sanity checks

Read `$ARGUMENTS`. Extract:

- **task description or ticket key** (positional, required)
- `--ticket KEY-123` (else auto-detect: branch name, last commit body, current Jira/Linear context)
- `--max-plan-iter N` (default 3)
- `--no-codex` (default off — codex reviewers/planners enabled)
- `--no-team` (default off — agent-teams enabled)
- `--skip-review-panel` (default off)
- `--skip-pr` (default off)
- `--dry-run` (default off)

Refuse to proceed when the task is trivially small (typo, single one-line change, rename of a single symbol). Tell the user to just do it inline.

Set `RUN_DIR=~/.claude/deepplan-runs/$(date +%Y%m%d-%H%M%S)-$(echo "$ARGUMENTS" | sha1sum | cut -c1-6)`. Create it with `mkdir -p`. All artifacts (plan drafts, verdicts, final plan, PR body) live there.

Verify binaries: `git`, `gh`, `claude`, `jq`. Verify `codex` if codex paths are enabled. Verify `claude --version` ≥ 2.1.32 if `--no-team` is **not** set.

If `--dry-run`: print the list of phases below with the spawned-agent counts and exit. Do not spawn anything.

## Phase 1 — Two-track planner drafting

Run `~/.claude/skills/deepplan/scripts/dispatch-planners.sh "$RUN_DIR" "$TASK_DESC"`. It spawns in parallel:

- `claude -p` (Opus) loaded with `personas/planner-opus.md`
- `codex exec` (latest) loaded with `personas/planner-codex.md` *(skipped if `--no-codex`)*

Both receive the task description + the contents of `templates/plan.md` as their target skeleton. Each writes its draft to `$RUN_DIR/draft-opus.md` and `$RUN_DIR/draft-codex.md`.

When both return, you synthesize **one** merged candidate plan into `$RUN_DIR/plan.md` using the template. Prefer the Opus draft's architecture framing, the Codex draft's codebase-grounded specifics. Resolve disagreements by keeping the stricter requirement.

## Phase 2 — Review loop (≤ `--max-plan-iter`)

Loop, starting at iteration 1:

1. Run `~/.claude/skills/deepplan/scripts/dispatch-reviewers.sh "$RUN_DIR" "$ITER"`. It launches in parallel:
   - 2× Opus reviewers (`personas/architect.md`, `personas/project-developer.md`)
   - 2× Codex reviewers (`personas/flow-mapper.md`, `personas/qa.md`) *(use Claude when `--no-codex`)*

   Each persona is given `plan.md`, the project's `CLAUDE.md`, and a short context snapshot (current branch, recent commits, repo tree). Each writes a verdict JSON to `$RUN_DIR/verdict-<persona>-iter<N>.json`:

   ```json
   {
     "persona": "architect",
     "verdict": "APPROVED" | "CHANGES_REQUESTED",
     "notes": "...",
     "proposed_edits": [{"section": "...", "change": "..."}]
   }
   ```

2. Run `~/.claude/skills/deepplan/scripts/aggregate-verdicts.sh "$RUN_DIR" "$ITER"`.
   - Exit 0 → all four APPROVED → break loop, advance to Phase 3.
   - Exit 1 → at least one CHANGES_REQUESTED → continue.

3. If continuing: apply the consolidated `proposed_edits` to `plan.md`. Increment ITER. Loop.

4. If ITER > `--max-plan-iter`: stop the loop. Use `AskUserQuestion` to present the **remaining disagreements** (per persona) and ask the user to tiebreak each one. Apply user decisions to `plan.md`. Treat as approved.

## Phase 3 — Present plan

Print the final `plan.md` to the user. Confirm it includes:

- A **Mermaid flow diagram** (sequence or flowchart) — required.
- An **edge-case list** from QA persona.
- A **TDD test list** (test names + intent, no implementation).
- An **abstractions decision log** (e.g., "notifications behind `NotificationPort` adapter — yes/no, why").
- A **verification section** (how to know the change works end-to-end).

If any are missing, loop back one more time into Phase 2 with a synthetic CHANGES_REQUESTED verdict naming the missing artifact.

Call `ExitPlanMode` once the user is satisfied.

## Phase 4 — Build via agent-teams

After `ExitPlanMode` returns approved:

1. Run `~/.claude/skills/deepplan/scripts/team-launch.sh`. It verifies `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set in the live session (it is, per global `settings.json`) and `claude --version` ≥ 2.1.32. It prints the **natural-language team-spawn prompt** you must issue (agent-teams are created by prompting, not by a CLI flag — per https://code.claude.com/docs/en/agent-teams).

2. Issue the spawn prompt verbatim. Typical shape:
   > Create an agent team with 3 Sonnet teammates to execute the plan at `$RUN_DIR/plan.md`. Split the work along the file-ownership boundaries listed in the plan's "Affected files" section. Each teammate runs strict red-green-refactor TDD per `superpowers:test-driven-development`. Use the project's CLAUDE.md conventions. If a parallelizable slice exists (e.g., scaffolding fixtures or generating test data), spawn one additional teammate using the `codex` model.

3. If `--no-team` is set OR `claude --version` is below 2.1.32, fall back to `cmux-orchestrator` (see `~/.claude/skills/cmux-orchestrator/SKILL.md`) for visible parallel workers; if cmux is unavailable, fall back to plain `Agent` subagents (general-purpose, max 3 in parallel).

4. Supervise: poll the team's task list, redirect stuck teammates, do not implement directly. Use the existing `superpowers:test-driven-development` skill as the per-task contract.

5. When all team tasks are completed and tests are green locally, ask the lead to clean up the team (per docs).

## Phase 5 — /review-panel passes

Unless `--skip-review-panel`:

1. Full review: `/review-panel default --scope main...HEAD`. Address all CRITICAL/HIGH findings. If new commits are needed, run a quick TDD cycle per finding.

2. Plan-aware review: `/review-panel default --reviewers 4 --ratio 2:2`. Inject the plan path into reviewer context by prepending `--scope` with a temporary annotation file: copy `plan.md` to the run dir and pass its content as additional reviewer context.

3. Hard cap: **2 total iterations** across both passes. If reviewers still flag CRITICAL issues after iter 2, stop and surface them to the user.

## Phase 6 — Open PR

Unless `--skip-pr`:

1. Run `~/.claude/skills/deepplan/scripts/pr-open.sh "$RUN_DIR"`. It:
   - Builds title from plan's "Goals" line (`<verb> <object>` shape, ≤ 70 chars).
   - Builds body from `templates/pr-body.md` populated with: what-it-solves, ticket link, Mermaid diagram pulled from `plan.md`, file list, "start review here" pointer (the first file/function in the plan's call-flow), test plan, risk notes.
   - Calls `gh pr create --title ... --body ...` using HEREDOC.
   - Returns PR URL.

2. Print the PR URL to the user.

## Phase 7 — CI + Copilot watch

Run `~/.claude/skills/deepplan/scripts/ci-and-copilot-watch.sh "$PR_URL"`. It:

- Polls `gh pr checks` every 30s until no check is `pending`.
- On failure: prints failing job logs (`gh run view --log-failed`).
- On Copilot comments: fetches via `gh api /repos/{owner}/{repo}/pulls/{N}/comments` and emits actionable items as JSON.

For each actionable failure or Copilot suggestion: run a small TDD cycle (red → green → commit → push). Re-poll. Cap: 5 iterations before bailing to user.

When all checks are green and no unresolved Copilot threads remain: print "✅ ship-ready" with the PR URL.

## Reuse

- Patterns for `claude -p` / `codex exec` flags: `~/.claude/skills/review-panel/scripts/reviewer.sh`.
- Visible parallel workers fallback: `~/.claude/skills/cmux-orchestrator/SKILL.md`.
- TDD enforcement: `superpowers:test-driven-development`.
- PR + commit conventions: `commit-commands:commit-push-pr`.

## Failure modes

- A spawned agent times out → mark its verdict CHANGES_REQUESTED with note "timeout", continue.
- `claude --version` < 2.1.32 → log and fall back to cmux/subagents automatically.
- `gh` not authenticated → halt at Phase 6, ask user to `gh auth login`.
- Plan iter cap reached with disagreements → `AskUserQuestion` tiebreak; never silently force-approve.
