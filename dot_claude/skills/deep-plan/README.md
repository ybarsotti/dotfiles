# deep-plan

A global Claude Code skill + slash command that runs a hardened **deep-planning** pipeline
for any non-trivial task, then hands off to the superpowers execution workflow. deep-plan
**stops at the approved plan** — it does not build, review the code, or open the PR.

## What it does

```
                  ┌─────────────────────────────────────────────┐
   /deep-plan ──▶  │ Phase 0.1: EnterPlanMode (plan mode on)      │
                  │ Phase 0.7: grill-with-docs (interview+ADRs)  │
                  │ Phase 1:   brainstorming                     │
                  │ Phase 1.5: Draft (Opus + Codex in parallel)  │
                  │ Phase 2:   Review loop (5 personas, ≤ 3 iter)│
                  │ Phase 2.5: Subplan fan-out                   │
                  │ Phase 3:   Validate + Plannotator gate      │
                  │ Phase 4:   Handoff → superpowers execution   │
                  └─────────────────────────────────────────────┘
```

## Personas

| Persona            | Model  | Role                                                            |
|--------------------|--------|-----------------------------------------------------------------|
| planner-opus       | Opus   | Architecture-first plan draft                                   |
| planner-codex      | Codex  | Codebase-grounded plan draft                                    |
| architect          | Sonnet | Reviews scalability, abstractions, seam boundaries              |
| project-developer  | Sonnet | Reviews against project conventions (reads CLAUDE.md + source)  |
| ticket-matcher     | Sonnet | Matches the plan point-by-point to the ticket; flags vagueness  |
| flow-mapper        | Codex  | Traces entry → service → repo; demands Mermaid sequence diagram  |
| qa                 | Codex  | Edge cases, failure modes, TDD test list, blast radius          |

Reviewers always run on **Sonnet** (Claude side) or **Codex** — never Opus (Opus is for planners).

Codex-side agents (planner-codex, flow-mapper, qa) are pinned to **`gpt-5.6-sol` @
`model_reasoning_effort=high`** in `scripts/runner.sh` — not the `~/.codex/config.toml`
default. Override with `DEEP_PLAN_CODEX_MODEL` / `DEEP_PLAN_CODEX_EFFORT`
(`none|minimal|low|medium|high|xhigh|max`).

## Handoff (execution phase — you run this after approval)

`superpowers:using-git-worktrees` → `subagent-driven-development` (TDD, mock only outer
boundaries) → `/simplify` ×2 → `/qa-test-plan` (if flows/screens change) → `/deep-review` →
`verification-before-completion` → `/pr-description` (Conventional-Commit title + Mermaid +
rationale + ticket, no file list, assigned to you) → CI/Copilot watch →
`finishing-a-development-branch`. For a Jira ticket, `jira-workflow` drives all of this.

## Plan format

The plan document always follows **`superpowers:writing-plans`** — deep-plan *invokes* that
skill (orchestrator + both planners) instead of restating its rules, so the header,
File Structure and `### Task N:` blocks stay in sync with upstream. `templates/plan.md` only
wraps it with deep-plan's extra sections (clarifying Qs, Mermaid flow, rationale, QA flag,
machine-validated checklist). `scripts/validate-plan.sh` enforces conformance
(`writing-plans-header`, `global-constraints-present`, `tasks-≥1`,
`tasks-have-files-and-interfaces`, `tasks-have-tdd-steps`).

## Plan presentation

Always through **Plannotator**, never a terminal dump: `plannotator annotate <plan> --gate`
for the full worker plan (loop until no annotations), then `ExitPlanMode` with the humanized
summary — the plannotator plugin's `PermissionRequest` hook re-opens the UI for final
approve / request-changes with a plan diff between submissions.

## Requirements

- `claude` CLI, `codex` CLI (unless `--no-codex`), `jq`, `git`
- `plannotator` CLI (`curl -fsSL https://plannotator.ai/install.sh | bash`) + the
  `plannotator@plannotator` plugin enabled (for the ExitPlanMode hook)
- Runtime deps for the pipeline: `grill-with-docs`, `superpowers:*`, `plannotator-annotate`
  (installed skills/plugins, not vendored here)

## Invocation

See `~/.claude/commands/deep-plan.md` for full arg grammar. Common:

```bash
/deep-plan "<task or ticket key>"
/deep-plan "FBIT-2982" --max-plan-iter 5
/deep-plan "small thing" --no-codex
/deep-plan --dry-run "rewrite the auth middleware"
```

## Artifacts

Each run writes to `~/.claude/deep-plan-runs/<RUN_ID>/`:

- `plan.md` — final approved plan (consumed by `/pr-description` and `jira-workflow`)
- `draft-opus.md`, `draft-codex.md` — initial drafts
- `verdict-<persona>-iter<N>.json` — reviewer verdicts per iteration
