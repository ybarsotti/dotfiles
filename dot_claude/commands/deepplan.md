---
description: Multi-agent plan-then-build pipeline — Opus+Codex draft, 4-persona review loop, agent-team execution, /review-panel, PR, CI+Copilot watch
---

# /deepplan

Drive a non-trivial task end-to-end through a hardened plan-then-build pipeline:

1. **Draft** a candidate plan with two parallel planner agents (Opus + Codex).
2. **Review** it with four parallel personas (2 Opus + 2 Codex: architect, project-developer, flow-mapper, QA) until unanimous approval (≤ 3 iterations, then user tiebreak).
3. **Present** the final plan (Mermaid flow diagrams, edge cases, TDD scenarios, abstraction decisions) and exit plan mode.
4. **Build** via Claude Code agent-teams (Sonnet teammates orchestrated by the main session; one optional codex worker for a parallel slice).
5. **Review the result** with `/review-panel` — full pass + plan-aware pass (≤ 2 iterations).
6. **Open PR** with descriptive title, ticket link, flow diagram, and a "start review here" pointer.
7. **Watch CI + Copilot** until green; address feedback automatically.

**Arguments:** `$ARGUMENTS`

## Argument grammar

```
/deepplan <task-or-ticket-description> [flags]

FLAGS
  --ticket KEY-123      explicit ticket key (else auto-detected from branch/commit)
  --max-plan-iter N     cap plan review iterations (default 3)
  --no-codex            skip codex planner + codex reviewers (Claude-only)
  --no-team             skip agent-teams execution; use plain subagents instead
  --skip-review-panel   skip post-build /review-panel
  --skip-pr             stop after build; do not open PR
  --dry-run             print the plan of phases without spawning anything
```

## What you must do

You are the **orchestrator**. Invoke the `deepplan` skill — do NOT plan or implement inline.

The skill lives at `~/.claude/skills/deepplan/SKILL.md`. Follow its phases exactly.

### Quick examples

```bash
/deepplan "add a dark-mode toggle to the settings page"
/deepplan "FBIT-2982"
/deepplan "refactor notification layer behind an adapter" --max-plan-iter 5
/deepplan "small refactor" --no-codex --no-team
/deepplan --dry-run "rewrite the auth middleware"
```
