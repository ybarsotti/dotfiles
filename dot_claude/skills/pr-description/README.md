# pr-description

Generate **and** review a pull-request title + description, then open (or update) the PR
assigned to you. A **claude Sonnet** agent writes the title/body; a **codex** agent reviews
it. Used standalone via `/pr-description`, and as a runtime dependency of `deep-plan`
(Phase 6 handoff) and `jira-workflow` (PR step).

## What it produces

- **Title** — a Conventional Commit (`feat`/`fix`/`refactor`/`perf`/`docs`/`test`/`chore` + optional scope), ≤ 70 chars.
- **Body** — objective, ticket, relevant Slack threads, requirement-by-requirement
  implementation status/evidence, **Mermaid**, rationale, key decisions, and verification.
- **Never** a changed-file list or file/line counts — the body is about *what we solve*, not *what moved*.
- The PR is **assigned to you** (`gh pr create --assignee @me`, or `gh pr edit --add-assignee @me` on update).

## Invocation

```bash
/pr-description                                        # draft from git diff main...HEAD, auto-detect ticket
/pr-description --plan <deep-plan plan.md> --ticket FBIT-2982
/pr-description --update 1421 --draft                  # update an existing PR
/pr-description --dry-run                              # print title + body, don't touch the PR
/pr-description --no-codex                             # Sonnet self-review instead of codex
```

## Reviewers

- The **writer** is always **claude Sonnet** (headless `claude -p --model sonnet`).
- The **reviewer** is **codex** (headless `codex exec`) — it checks: title is conventional,
  Mermaid matches changed domains, no file list exists, ticket/Slack sources are explicit,
  requirements are reconciled against diff/tests, and key decisions survive.
  `--no-codex` falls back to a Sonnet self-review with same checklist.

## Layout

```
~/.claude/skills/pr-description/
├── README.md                # this file
├── SKILL.md                 # protocol the orchestrator follows when /pr-description runs
└── personas/
    └── pr-writer.md         # fixed Sonnet writer prompt
```

Run artifacts (writer input, draft, codex review, final body) persist at
`~/.claude/pr-description-runs/<RUN_ID>/`.

## Depends on

- `gh` (authenticated), `git`, and `codex` (unless `--no-codex`).
- Mirrors flag patterns from `deep-review/scripts/executable_reviewer.sh` and opener logic
  from `deep-plan/scripts/executable_pr-open.sh`.
