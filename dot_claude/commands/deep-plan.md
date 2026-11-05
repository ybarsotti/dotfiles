---
description: Deep planning with Opus+Codex, requirement/journey/data/UI-design traceability, 5-persona review, Plannotator, then /deep-execute
---

# /deep-plan

Drive a non-trivial task through a hardened **deep-planning** pipeline. When you approve the
plan, the same session builds it, reviews it, runs QA, opens the PR and delivers an HTML
report, without waiting for you (`~/.claude/skills/_shared/after-approval.md`). Say "only
plan" to stop at the approved plan.

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
7. **Execution recommendation** — pick one of four ways to build it from the plan (see below).
8. **Build to PR** — run the after-approval chain end to end.

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

deep-plan reads the approved plan's `## Execution shape`, picks **one** of these, and starts:

| | Option | Fits when |
|---|---|---|
| **A** | `/deep-execute "$RUN_DIR/plan.md"` — parallel lane workers, one shared worktree | `Mode: parallel`, ≥ 2 disjoint lanes, a real contract |
| **B** | Serial, one implementer agent per task (`superpowers:subagent-driven-development`) | serial plan, one lane, or lanes too coupled for a contract |
| **C** | Claude `Workflow` — deterministic script fan-out | many uniform mechanical slices (migration, codemod, sweep) |
| **D** | Codex-only implementer, this session orchestrates and reviews | one coherent slice you want a second model to write |

**The planning session orchestrates; it does not implement.** It directs workers, answers
their questions, gates rounds, routes review findings back to the owning agent, and commits.
It writes feature code only when you ask for that in so many words.

## What runs after the plan is approved

`~/.claude/skills/_shared/after-approval.md` is the chain. It runs end to end under `/goal` and
stops only on a decision that changes a requirement, a rule, a contract or the scope:

1. Build with strict TDD through the chosen option.
2. `/deep-review default`, with the CRITICAL and HIGH findings fixed and re-reviewed.
3. When the app URL answers: the `qa-ui` agent compares each new element with the plan and
   the Design canvas at desktop width and at 390 px, and the `qa-business` agent runs the
   requirements and edge cases end to end with video.
4. A separate agent fixes what QA found. QA re-runs, for 3 rounds at most.
5. `/pr` with the evidence attached, then the PR watch.
6. An HTML report with the decisions, the tests, the screenshots and the videos.

### Quick examples

```bash
/deep-plan "add a dark-mode toggle to the settings page"
/deep-plan "PROJ-2982"
/deep-plan "refactor notification layer behind an adapter" --max-plan-iter 5
/deep-plan "small refactor" --no-codex
/deep-plan --dry-run "rewrite the auth middleware"
```
