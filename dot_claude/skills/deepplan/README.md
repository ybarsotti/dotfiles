# deepplan

A global Claude Code skill + slash command that runs a hardened **plan-then-build** pipeline for any non-trivial task.

## What it does

```
                  ┌─────────────────────────────────────────────┐
   /deepplan ──▶  │ Phase 1: Draft (Opus + Codex in parallel)    │
                  │ Phase 2: Review loop (4 personas, ≤ 3 iter)  │
                  │ Phase 3: Present + ExitPlanMode              │
                  │ Phase 4: Build via agent-teams (Sonnet × N)  │
                  │ Phase 5: /review-panel (full + plan-aware)   │
                  │ Phase 6: Open PR (title + body + diagram)    │
                  │ Phase 7: Watch CI + Copilot until green      │
                  └─────────────────────────────────────────────┘
```

## Personas

| Persona            | Model | Role                                                                 |
|--------------------|-------|----------------------------------------------------------------------|
| planner-opus       | Opus  | Architecture-first plan draft                                        |
| planner-codex      | Codex | Codebase-grounded plan draft                                         |
| architect          | Opus  | Reviews scalability, abstractions, seam boundaries                   |
| project-developer  | Opus  | Reviews against project conventions (reads CLAUDE.md + source)       |
| flow-mapper        | Codex | Traces entry → service → repo; demands Mermaid sequence diagram      |
| qa                 | Codex | Edge cases, failure modes, TDD test list, blast radius               |

## Requirements

- `claude` CLI ≥ 2.1.32 (agent-teams)
- `codex` CLI (unless `--no-codex`)
- `gh` authenticated
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` enabled in `~/.claude/settings.json` (handled by this dotfiles repo)
- `jq`, `git`

## Invocation

See `~/.claude/commands/deepplan.md` for full arg grammar. Common:

```bash
/deepplan "<task or ticket key>"
/deepplan "FBIT-2982" --max-plan-iter 5
/deepplan "small thing" --no-codex --no-team
/deepplan --dry-run "rewrite the auth middleware"
```

## Artifacts

Each run writes to `~/.claude/deepplan-runs/<RUN_ID>/`:

- `plan.md` — final approved plan
- `draft-opus.md`, `draft-codex.md` — initial drafts
- `verdict-<persona>-iter<N>.json` — reviewer verdicts per iteration
- `pr-body.md` — generated PR description
