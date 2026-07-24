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
5. **Present** — `finalize-plan.sh` validate/repair/tick gate, then **Plannotator**:
   `plannotator annotate <plan> --gate` for the full plan, then `ExitPlanMode` (its hook
   re-opens the UI for final approval).
6. **Handoff** — print `/deep-execute "$RUN_DIR/plan.md"` and stop.

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

## Handoff (what runs after the plan is approved)

deep-plan prints `/deep-execute "$RUN_DIR/plan.md"` and stops — it does not run any of this
itself. `/deep-execute` drives the full superpowers execution workflow from the approved plan:

1. `superpowers:using-git-worktrees` → isolate.
2. `superpowers:subagent-driven-development` (or `executing-plans`) → build with strict TDD
   (mock only outermost boundaries; inner services/repos run real).
3. `/simplify` ×2.
4. `/qa-test-plan` — if the plan flags flow/screen changes.
5. `/deep-review` → then `superpowers:verification-before-completion`.
6. `/pr-description` — title + ticket/Slack + requirements + Mermaid + decisions, assigned to you.
7. CI + Copilot watch → `superpowers:finishing-a-development-branch`.

### Quick examples

```bash
/deep-plan "add a dark-mode toggle to the settings page"
/deep-plan "FBIT-2982"
/deep-plan "refactor notification layer behind an adapter" --max-plan-iter 5
/deep-plan "small refactor" --no-codex
/deep-plan --dry-run "rewrite the auth middleware"
```
