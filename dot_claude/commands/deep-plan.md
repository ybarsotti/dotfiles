---
description: Deep planning with Opus+Codex, requirement/journey/data/UI-design traceability, 5-persona review, Plannotator, then /deep-execute
---

# /deep-plan

Drive a non-trivial task through a hardened **deep-planning** pipeline and stop at an
approved plan — deep-plan does NOT build, review, or open the PR itself. It hands off to
`/deep-execute` (which you run next, or which `jira-workflow` runs for you).

0. **Plan mode** — `EnterPlanMode` first; every phase up to approval runs inside it, no
   project file is touched.
1. **Clarify + grill** — `AskUserQuestion` sweep, then `grill-with-docs` (relentless
   interview + ADRs/glossary).
2. **Brainstorm** — `superpowers:brainstorming`.
3. **Draft** — `superpowers:writing-plans` defines the plan format (always — the skill is
   invoked, never paraphrased); plan captures ticket/Slack context, requirements matrix,
   applicable user journey, table/column population, and substantial-UI design prompt;
   two parallel planners (Opus + Codex) → one merged plan.
4. **Review** — 5 parallel personas (architect, project-developer, ticket-matcher on
   Sonnet; flow-mapper, qa on Codex) until unanimous approval (≤ 3 iterations, then tiebreak).
5. **QA plan** — when flows/screens change, `/qa-plan` maps requirements and journeys into
   reviewed `qa-plan.yaml` before implementation.
6. **Present** — `finalize-plan.sh` validate/repair/tick gate, then **Plannotator**:
   `plannotator annotate <plan> --gate` for the full plan, then `ExitPlanMode` (its hook
   re-opens the UI for final approval).
7. **Execution recommendation** — recommend one of four ways to build it and let the user
   pick via `AskUserQuestion` (see below).
8. **Handoff** — print the entry point for the chosen option and stop.

**Arguments:** `$ARGUMENTS`

## Argument grammar

```
/deep-plan <task-or-ticket-description> [flags]

FLAGS
  --ticket KEY-123      explicit ticket key (else auto-detected from branch/commit)
  --max-plan-iter N     cap plan review iterations (default 3, range 1-20)
  --no-codex            skip codex planner + codex reviewers (Claude/Sonnet only)
  --skip-grill          skip the grill-with-docs interview (recorded as skipped)
  --dry-run             print the plan of phases without spawning anything
```

## What you must do

You are the **orchestrator**. Invoke the `deep-plan` skill — do NOT plan or implement inline.
The skill lives at `~/.claude/skills/deep-plan/SKILL.md`. Follow its phases exactly. deep-plan
**stops at the approved plan**; the build/review/PR happen in the execution phase it hands off to.

### Evidence discipline

Do not let any planner or reviewer guess. Every claim about current behavior, architecture,
dependencies, constraints, or risk must be proved with repository code or observed data and cite
its evidence (for example, `path/to/file:line`, command output, test result, trace, metric, or ticket
field). If evidence is missing, label the claim **unknown** and add an investigation step; never
present an assumption as fact or approve a plan that depends on an unverified claim.

## Execution recommendation (Phase 7)

deep-plan reads the approved plan's `## Execution shape` and recommends **one** of these,
then asks you to confirm with `AskUserQuestion`:

| | Option | Fits when |
|---|---|---|
| **A** | `/deep-execute "$RUN_DIR/plan.md"` — parallel lane workers, one shared worktree | `Mode: parallel`, ≥ 2 disjoint lanes, a real contract |
| **B** | Sequential in **this** session (`superpowers:executing-plans`) | serial plan, one lane, or lanes too coupled for a contract |
| **C** | Claude `Workflow` — deterministic script fan-out | many uniform mechanical slices (migration, codemod, sweep) |
| **D** | Codex-only implementer, this session orchestrates and reviews | one coherent slice you want a second model to write |

**The planning session orchestrates; it does not implement.** It directs workers, answers
their questions, gates rounds, routes review findings back to the owning agent, and commits.
**Option B is the only opt-out**, and it only counts when *you* pick it — never when the
session decides the change looks small enough to just do.

## What runs after the plan is approved

Same chain regardless of which option you pick — `/deep-execute` runs it itself; for B, C and
D the planning session drives it. It is wrapped in **`/goal`** (built into Claude Code and
Codex) with the objective stated as the finished state, so it runs **end to end without
stopping** and halts only on a blocker no agent can decide alone:

1. `superpowers:using-git-worktrees` → isolate.
2. Build with strict TDD (mock only outermost boundaries; inner services/repos run real).
3. `/simplify` ×2.
4. `/deep-review default --reviewers 6 --ratio 3:3` + fixes → `superpowers:verification-before-completion`.
5. Record what was built and what the review changed.
6. A QA agent drives `agent-browser` against a live env — `/qa-testing` (EXECUTE) when that
   skill is installed, `/qa-execute` for a plan's `qa-plan.yaml`, a plain browser agent otherwise.
7. A **separate, non-tester** agent fixes every gap QA found; QA re-runs on the fix.
8. Freeze final commit SHA; `/qa-execute` for the approved QA plan when one exists.
9. `/pr-description` — title + ticket/Slack + requirements + Mermaid + decisions + **evidence**
   (screenshots/GIF when UI changed), assigned to you.
10. HTML run report: what was built, decisions, trade-offs, assumptions, tests, screenshots,
    recordings, PR link.
11. CI + Copilot watch → `superpowers:finishing-a-development-branch`.

### Quick examples

```bash
/deep-plan "add a dark-mode toggle to the settings page"
/deep-plan "PROJ-2982"
/deep-plan "refactor notification layer behind an adapter" --max-plan-iter 5
/deep-plan "small refactor" --no-codex
/deep-plan --dry-run "rewrite the auth middleware"
```
