---
name: deep-plan
description: Multi-agent deep-planning pipeline. Use when invoked via /deep-plan, or when the user explicitly wants a deeply reviewed plan before any code is written for a non-trivial task (new feature, refactor, architectural change). Drafts a plan with parallel Opus + Codex planners, hardens it with reviewer personas (architect, project-developer, flow-mapper, qa, ticket-matcher) until unanimous approval, presents it via plannotator, then hands off to the superpowers execution workflow. deep-plan STOPS at the approved plan — it does not build, review, or open the PR itself.
---

# deep-plan

You are the **orchestrator** of a multi-agent **deep-planning** pipeline. Your job is to
coordinate planning and review, then present an approved plan and hand off. You do **not**
draft the plan yourself, and you do **not** build, review the code, or open the PR — those
happen in the **execution phase** the user runs after approval (via superpowers + the
`/deep-review`, `/qa-test-plan`, `/pr-description` commands). deep-plan parses args,
dispatches agents, aggregates verdicts, presents checkpoints, and suggests next steps.

## Superpowers workflow mapping

This pipeline implements the **planning half** of the canonical
[obra/superpowers](https://github.com/obra/superpowers) workflow, then hands off the
execution half. Invoke each planning-phase skill via the Skill tool at its mapped phase —
**mandatory workflows, not suggestions.**

| # | superpowers / skill | deep-plan phase | run by |
|---|---------------------|----------------|--------|
| ✳ | `EnterPlanMode` (plan mode on) | Phase 0.1 | deep-plan |
| 0 | `grill-with-docs` | Phase 0.7 | deep-plan |
| 1 | `brainstorming` | Phase 1 | deep-plan |
| 2 | `writing-plans` | Phase 1.5 | deep-plan |
| 3 | `humanizing-plans` | Phase 3 (present) | deep-plan |
| 4 | `plannotator-annotate` | Phase 3 (annotate) | deep-plan |
| ✳ | `continuity-ledger` | any long session (save/resume) | deep-plan |
| — | — | **handoff** ↓ | **user** |
| 4 | `using-git-worktrees` | execution | superpowers |
| 5 | `subagent-driven-development` / `executing-plans` | execution | superpowers |
| 6 | `test-driven-development` | execution (per task) | superpowers |
| 6b| `systematic-debugging` | execution (bug/regression tasks) | superpowers |
| 6c| `dispatching-parallel-agents` | execution (fallback for parallel slices) | superpowers |
| 7 | `/deep-review` + `receiving-code-review` + `/qa-test-plan` | execution | commands / superpowers |
| 8 | `/pr-description` + `finishing-a-development-branch` | execution | command / superpowers |

Plus deep-plan adds: multi-model planner/reviewer fan-out, the `ticket-matcher` reviewer,
code-intel bootstrap, and the machine-validated checklist gate.

## Phase 0 — Parse args & sanity checks

Read `$ARGUMENTS`. Extract:

- **task description or ticket key** (positional, required)
- `--ticket KEY-123` (else auto-detect: branch name, last commit body, current Jira/Linear context)
- `--max-plan-iter N` (default 3)
- `--no-codex` (default off — codex reviewers/planners enabled)
- `--skip-grill` (default off)
- `--dry-run` (default off)

Refuse to proceed when the task is trivially small (typo, single one-line change, rename of a single symbol). Tell the user to just do it inline.

Set `RUN_DIR=~/.claude/deep-plan-runs/$(date +%Y%m%d-%H%M%S)-$(echo "$ARGUMENTS" | sha1sum | cut -c1-6)`. Create it with `mkdir -p`. All artifacts (plan drafts, verdicts, final plan) live there.

Verify binaries: `git`, `claude`, `jq`. Verify `codex` if codex paths are enabled.

If `--dry-run`: print the list of phases below with the spawned-agent counts and exit. Do not spawn anything.

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

## Phase 0.5 — Clarifying questions (mandatory)

Before any grill or draft, surface every ambiguity in the task description to the user. Use `AskUserQuestion` with focused options (no open-ended prose questions when a multiple-choice will do).

Examples of things to clarify: scope boundaries, personas/targets, trade-off preferences (speed vs correctness, minimal-diff vs refactor), acceptance criteria.

Record every Q/A pair in `## Clarifying questions` using `### Q:` / `### A:` headers. The validator requires ≥1 matched pair.

If — and only if — the task is genuinely unambiguous after a careful re-read, write exactly `_no ambiguity_` in the section and skip questions. This must be rare; the default is to ask.

## Phase 0.7 — Grill-with-docs deep interview (mandatory unless `--skip-grill`)

After the multiple-choice clarifications resolve the obvious gaps, drill harder and capture the reasoning as docs.

**Step 1 — invoke the skill via Skill tool:**
```
Skill(skill="grill-with-docs")
```

`grill-with-docs` runs a relentless `/grilling` interview (one question at a time, down each branch of the decision tree) **and** produces ADRs + a glossary via `/domain-modeling` as decisions are reached. Where Phase 0.5 is a fast multiple-choice sweep, this is open-ended stress-testing that leaves a documented decision trail — feeding the plan's `## Rationale & key decisions`.

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
`templates/plan.md` only adds deep-plan's extra sections (clarifying Qs, flow diagram,
rationale, QA flag, checklist) around it.

**Step 1 — invoke the skill via the Skill tool:**
```
Skill(skill="superpowers:writing-plans")
```

**Step 2 — record the invocation:**
```
~/.claude/skills/deep-plan/scripts/superpowers-invoke.sh "$RUN_DIR" writing-plans
```

**Step 3 — dispatch:**
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

   Reviewers are always **Sonnet** on the Claude side; the Codex side runs `gpt-5.6-sol` at
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

## Phase 2.5 — Subplan fan-out

After root plan reviewer-approved, split it into chapters:
```
~/.claude/skills/deep-plan/scripts/subplan-fanout.sh "$RUN_DIR" --max-chapters 5
```
This groups `## Affected files` by top-level directory, emits `$RUN_DIR/subplans/<chapter>.md`, and updates the `## Subplans` section in `plan.md` with links.

For each subplan: run a **reduced** review loop — `project-developer` (Sonnet) + `qa` (Codex; or Sonnet if `--no-codex`), 2 iterations max. Failed subplan (still CHANGES_REQUESTED after iter 2) → mark the link with a trailing `[CHANGES_REQUESTED]`, continue, and surface as a warning in Phase 3.

## Phase 3 — Validate gate, annotate & present plan

Before showing the plan, **gate** on `validate-plan.sh`:
```
~/.claude/skills/deep-plan/scripts/validate-plan.sh "$RUN_DIR/plan.md" --root
for sub in "$RUN_DIR"/subplans/*.md; do
  ~/.claude/skills/deep-plan/scripts/validate-plan.sh "$sub" --subplan
done
```

If anything fails, **auto-recover (up to 3 retries)**: collect the failed items, spawn an Opus planner with the explicit list + the current plan and ask it to fix; re-validate. After 3 retries, fall through to `AskUserQuestion` for tiebreak.

Once `validate-plan.sh` returns 0 on root and every subplan, tick the checklist:
```
~/.claude/skills/deep-plan/scripts/tick-checklist.sh "$RUN_DIR/plan.md" --root
for sub in "$RUN_DIR"/subplans/*.md; do
  ~/.claude/skills/deep-plan/scripts/tick-checklist.sh "$sub" --subplan
done
```
The LLM **never** edits `[ ]`/`[x]` directly. The checklist must show all `[x]` before proceeding. The same rule covers `## Superpowers invoked`: never hand-edit its boxes; call `scripts/superpowers-invoke.sh "$RUN_DIR" <skill>` **after** actually invoking the skill via the Skill tool — it records a receipt (chained by hash, anchored to the project repo's HEAD commit) and ticks the box together — `validate-plan.sh`'s `superpowers-ticks-have-receipts` check fails any tick that lacks a chain-valid, ancestor-verified receipt. This is a tamper-evident audit trail, chain-verified by the validator and anchored to a repo commit — not tamper-proof, and it proves the script was invoked, not that the skill itself ran (nothing stops calling the script without calling `Skill()` first; that discipline still depends on following this workflow). See the header comment in `scripts/superpowers-invoke.sh` for the full picture of what it does and doesn't guarantee.

Confirm the plan includes, at minimum:
- The **`superpowers:writing-plans` document header** + an **`## Implementation tasks`** section in that skill's exact task format (`### Task N:` + Files + Interfaces + bite-sized checkbox steps with real code).
- A **Mermaid flow diagram** (sequence or flowchart) — required.
- A **Rationale & key decisions** section (fed by grill-with-docs + brainstorming).
- A **TDD test list** with the outer-boundary-only mocking policy stated.
- An **Abstractions decision log**.
- A **Documentation impact** section (docs/ that go stale must be updated, or `none`).
- A **QA / test-execution** flag ("changes flows or adds screens? yes/no").
- A **Verification** section.

If any are missing, loop back once into Phase 2 with a synthetic CHANGES_REQUESTED verdict naming the missing artifact.

**Humanize for the reader (superpowers-adjacent: `humanizing-plans`):**
```
Skill(skill="humanizing-plans")
```
The raw `plan.md` is written for a worker (file paths, task steps, TDD list). Before asking
the human to approve it, run `humanizing-plans` on `$RUN_DIR/plan.md` to distill it to human
altitude (goal, approach, key decisions + why, risks, sequence) and render the best-fit format
(text / diagram / HTML). This is the artifact the user actually reads to approve. Record:
```
~/.claude/skills/deep-plan/scripts/superpowers-invoke.sh "$RUN_DIR" humanizing-plans
```
If `humanizing-plans` is unavailable, print a short human-altitude distillation inline instead.

**Present the plan through Plannotator (mandatory — never a terminal wall of text):**

The plan is always reviewed in the Plannotator UI, in two passes:

1. **Annotate the full worker plan.** Invoke the skill (it runs the command itself):
   ```
   Skill(skill="plannotator-annotate")
   ```
   Target `$RUN_DIR/plan.md` and gate on the result:
   ```
   plannotator annotate "$RUN_DIR/plan.md" --gate
   ```
   `--gate` blocks until the user approves or returns annotations. Address **every**
   annotation: edit `plan.md`, re-run `validate-plan.sh`, re-run `tick-checklist.sh`, then
   re-open Plannotator on the updated file. Loop until the user approves with no annotations.
   Record it:
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

## Phase 4 — Handoff (deep-plan stops here)

Once the plan is approved, **do not build**. Present the ordered execution handoff and let the
user drive it. The plan already encodes the requirements each step must honor. Print this
checklist verbatim (adapt paths):

**Next steps — superpowers execution workflow:**

1. **Isolate** — `Skill(skill="superpowers:using-git-worktrees")` — fresh worktree/branch, clean test baseline.
2. **Build** — `Skill(skill="superpowers:subagent-driven-development")` (or `executing-plans` when subagents are unavailable), executing `$RUN_DIR/plan.md`. Strict red-green-refactor per `superpowers:test-driven-development`. **Mock only the outermost boundaries; inner services/repos/domain run real.**
   - *Bug/regression task?* Drive it through `superpowers:systematic-debugging` (reproduce → minimise → hypothesise → fix → regression-test) before writing the fix.
   - *Fallback for parallel slices* — if agent-teams/subagent-driven is unavailable, use `superpowers:dispatching-parallel-agents` to fan out the independent build slices, then integrate.
3. **Simplify** — `/simplify` ×2.
4. **QA** — **if** the plan's `## QA / test-execution` flag is "yes" (flow change or new screens), run `/qa-test-plan` to produce + execute the manual test plan (records video).
5. **Review** — `/deep-review` (full panel; reviewers on Sonnet + Codex). Before applying its findings, `Skill(skill="superpowers:receiving-code-review")` — verify each finding technically, push back on the questionable ones, don't blindly apply. Then `superpowers:verification-before-completion`.
6. **PR** — `/pr-description` — opens the PR with a Conventional-Commit title, a Mermaid diagram, rationale, decisions, ticket link (**no file list / no counts**), assigned to you. It reuses `$RUN_DIR/plan.md`.
7. **Ship** — watch CI + Copilot (`~/.claude/skills/deep-plan/scripts/ci-and-copilot-watch.sh <PR_URL>`), then `Skill(skill="superpowers:finishing-a-development-branch")`.

> Tip: for a Jira ticket, `/deep-plan` is invoked **inside** the `jira-workflow` skill, which then drives steps 1–7 automatically.

## Reuse

- Patterns for `claude -p` / `codex exec` flags: `~/.claude/skills/deep-review/scripts/reviewer.sh`.
- Post-approval build/review/PR helpers live in this skill's `scripts/` (`feature-branch.sh`, `pr-open.sh`, `ci-and-copilot-watch.sh`, `handle-findings.sh`) and are consumed by `/pr-description` and `jira-workflow` — not by deep-plan itself.
- TDD enforcement: `superpowers:test-driven-development`.

## Failure modes

- A spawned agent times out → mark its verdict CHANGES_REQUESTED with note "timeout", continue.
- Plan iter cap reached with disagreements → `AskUserQuestion` tiebreak; never silently force-approve.
- `plannotator` CLI missing → say so, print the humanized summary inline (never the whole `plan.md`), point at the file path, and proceed to `ExitPlanMode`. Install: `curl -fsSL https://plannotator.ai/install.sh | bash`.
- `plannotator annotate --gate` exits without feedback → treat as approved, note it, continue.
- Not in plan mode at Phase 3 (session started outside it) → still run the `annotate --gate` pass; skip `ExitPlanMode`.

## Continuity ledger (long / multi-day planning)

Deep planning can span a long session or several days. Use the **`continuity-ledger`** skill so
the work survives `/clear` and compaction:

- **Start / bind** — for a multi-day task or ticket, at Phase 0 create or bind a ledger:
  `Skill(skill="continuity-ledger")` with `new deep-plan-<slug>` (or `save` to bind an existing
  one). It writes `thoughts/ledgers/CONTINUITY_CLAUDE-<name>.md` and binds this pane/window.
- **Save at boundaries** — after the Phase 2 review loop converges, and again right before the
  Phase 4 handoff, run `continuity-ledger` **save**. Capture Goal, Constraints, Key Decisions,
  State (Done/Now/Next), Open Questions, and the `$RUN_DIR` path in the ledger.
- **Resume** — the ledger's `SessionStart` hook auto-loads it after `/clear`, so a fresh session
  picks up the plan, the run dir, and the decisions without re-deriving them. No manual load
  needed when the hooks are installed.

Only for genuinely long work — skip the ledger for a quick, single-session plan. If
`continuity-ledger` is not installed, this degrades to a no-op; do not fabricate a ledger file.
