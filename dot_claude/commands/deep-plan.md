---
description: Deep planning with Opus+Codex, requirement/journey/data/UI-design traceability, 5-persona review, Plannotator, then build to PR through the after-approval chain
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
7. **Execution recommendation** — pick the executor from the plan's `## Execution shape`
   (`~/.claude/skills/_shared/plan-routing.md`).
8. **Build to PR** — run `~/.claude/skills/_shared/after-approval.md` end to end.

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
The skill lives at `~/.claude/skills/deep-plan/SKILL.md`. Follow its phases exactly. After
approval it builds through to the PR, unless the user said to stop at the plan.

### Evidence discipline

Do not let any planner or reviewer guess. Every claim about current behavior, architecture,
dependencies, constraints, or risk must be proved with repository code or observed data and cite
its evidence (for example, `path/to/file:line`, command output, test result, trace, metric, or ticket
field). If evidence is missing, label the claim **unknown** and add an investigation step; never
present an assumption as fact or approve a plan that depends on an unverified claim.

## After the plan is approved

The planning session orchestrates; it does not implement. It writes feature code only when you
ask for that in so many words. The executor choice is in
`~/.claude/skills/_shared/plan-routing.md`, and the chain is in
`~/.claude/skills/_shared/after-approval.md`.

### Quick examples

```bash
/deep-plan "add a dark-mode toggle to the settings page"
/deep-plan "PROJ-2982"
/deep-plan "refactor notification layer behind an adapter" --max-plan-iter 5
/deep-plan "small refactor" --no-codex
/deep-plan --dry-run "rewrite the auth middleware"
```
