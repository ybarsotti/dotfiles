---
description: Multi-agent deep-planning pipeline — Opus+Codex draft, 5-persona review loop (incl. ticket-matcher), plannotator, then hands off to the superpowers execution workflow
---

# /deep-plan

Drive a non-trivial task through a hardened **deep-planning** pipeline and stop at an
approved plan — deep-plan does NOT build, review, or open the PR itself. It hands off to the
superpowers execution workflow (which you run next, or which `jira-workflow` runs for you).

1. **Clarify + grill** — `AskUserQuestion` sweep, then `grill-with-docs` (relentless
   interview + ADRs/glossary).
2. **Brainstorm** — `superpowers:brainstorming`.
3. **Draft** — two parallel planners (Opus + Codex) → one merged plan.
4. **Review** — 5 parallel personas (architect, project-developer, ticket-matcher on
   Sonnet; flow-mapper, qa on Codex) until unanimous approval (≤ 3 iterations, then tiebreak).
5. **Present** — validate gate, annotate with `plannotator`, then `ExitPlanMode`.
6. **Handoff** — suggest the ordered superpowers + command steps to build, review, QA, and
   open the PR.

**Arguments:** `$ARGUMENTS`

## Argument grammar

```
/deep-plan <task-or-ticket-description> [flags]

FLAGS
  --ticket KEY-123      explicit ticket key (else auto-detected from branch/commit)
  --max-plan-iter N     cap plan review iterations (default 3)
  --no-codex            skip codex planner + codex reviewers (Claude/Sonnet only)
  --skip-grill          skip the grill-with-docs interview (recorded as skipped)
  --dry-run             print the plan of phases without spawning anything
```

## What you must do

You are the **orchestrator**. Invoke the `deep-plan` skill — do NOT plan or implement inline.
The skill lives at `~/.claude/skills/deep-plan/SKILL.md`. Follow its phases exactly. deep-plan
**stops at the approved plan**; the build/review/PR happen in the execution phase it hands off to.

## Handoff (what runs after the plan is approved)

deep-plan prints these as suggested next steps — it does not run them itself:

1. `superpowers:using-git-worktrees` → isolate.
2. `superpowers:subagent-driven-development` (or `executing-plans`) → build with strict TDD
   (mock only outermost boundaries; inner services/repos run real).
3. `/simplify` ×2.
4. `/qa-test-plan` — if the plan flags flow/screen changes.
5. `/deep-review` → then `superpowers:verification-before-completion`.
6. `/pr-description` — Conventional-Commit title + Mermaid + rationale + ticket, assigned to you.
7. CI + Copilot watch → `superpowers:finishing-a-development-branch`.

### Quick examples

```bash
/deep-plan "add a dark-mode toggle to the settings page"
/deep-plan "FBIT-2982"
/deep-plan "refactor notification layer behind an adapter" --max-plan-iter 5
/deep-plan "small refactor" --no-codex
/deep-plan --dry-run "rewrite the auth middleware"
```
