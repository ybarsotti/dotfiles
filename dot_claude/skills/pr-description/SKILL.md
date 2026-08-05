---
name: pr-description
description: Generate and review a pull-request title/body, then open or update assigned PR. Use for /pr-description, PR-description/opening requests, or deep-plan/jira-workflow handoff. Produces Conventional Commit title plus objective, ticket, Slack threads, reconciled requirements matrix, Mermaid, key decisions and verification, with no changed-file inventory. Claude Sonnet writes; Codex reviews.
---

# pr-description

You are the **orchestrator** of a write-then-review PR-description pipeline. A **claude
Sonnet** writer drafts the title + body; a **codex** reviewer validates it; you apply the
fixes and open (or update) the PR assigned to the user.

**You do NOT write the PR title/body inline yourself.** The Sonnet writer does that in a
headless process. You parse args, dispatch the writer, dispatch the codex reviewer, apply
its concrete fixes, and open/update the PR.

## Conventions (non-negotiable)

- **Title = Conventional Commit**: `type(scope): summary`, `type` ∈ `feat` `fix` `refactor` `perf` `docs` `test` `chore`, ≤ 70 chars.
- **Body contains**: what it solves, **Mermaid**, ticket, Slack threads, requirements matrix,
  rationale/key decisions, verification, and — whenever the change touches UI — an
  **`## Evidence`** section (see Phase 2.5).
- **Body must NOT contain**: a changed-file list, file paths as an inventory, or file/line counts. Objective about *what we solve*, not *what moved*.
- **Writer is claude Sonnet. Reviewer is codex.** Any additional reviewers on the claude side are Sonnet; the codex reviewer stays codex.
- **PR is assigned to the user**: `--assignee @me` on create, `--add-assignee @me` on update.

## Phase 0 — Parse args & sanity checks

Read `$ARGUMENTS`. Extract:

- `--plan <path>` — deep-plan `plan.md` to source sections + ticket from (else none)
- `--ticket KEY-123` — explicit ticket (else auto-detect)
- `--update <pr-number>` — update this PR instead of creating (else create)
- `--draft` — open as draft (create only)
- `--no-codex` — skip the codex reviewer, Sonnet self-review only
- `--evidence <path>` — a QA evidence dir or `index.html` (screenshots, recordings) to source
  the `## Evidence` section from. Repeatable. When omitted, look for the newest
  `.qa-reports/*/execute/*/index.html` and the calling run's `--qa` artifact before concluding
  there is none.
- `--dry-run` — print the drafted title + body, do not open/update

Set `RUN_DIR=~/.claude/pr-description-runs/$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD 2>/dev/null)`. Create it with `mkdir -p`. Drafts, the review, and the final body live there.

Verify binaries: `git`, `gh`. Verify `codex` unless `--no-codex`. If `gh` is not authenticated, halt and ask the user to `gh auth login`.

**Detect the ticket** (unless `--ticket` given), first match wins:
1. `--plan` file's `## Ticket` section or any `[A-Z]{2,}-\d+` token in it
2. Current branch name: `git rev-parse --abbrev-ref HEAD | grep -oE '[A-Z]{2,}-[0-9]+'`
3. Last commit body: `git log -1 --pretty=%B | grep -oE '[A-Z]{2,}-[0-9]+'`

**Locate the plan**: if `--plan <path>` was passed, verify it exists; read `## Context`,
`## Ticket and Slack context`, `## Requirements matrix`, `## Flow diagram`,
`## Rationale & key decisions`, and ticket. If no `--plan`, derive requirements and source
links from ticket/task context plus diff; never invent missing Slack threads.

If `--dry-run`, note it — you will stop after Phase 2.

## Phase 1 — WRITE (claude Sonnet)

Assemble the writer input into `$RUN_DIR/writer-input.md`:
1. The persona prompt: `~/.claude/skills/pr-description/personas/pr-writer.md`
2. `---`
3. Context: detected ticket, `git diff --stat main...HEAD` **for the writer's private
   understanding only** (remind it: never echo file names/counts into the body), the
   changed-path domains from `git diff --name-only main...HEAD`, the recent commit
   subjects (`git log --pretty=%s main..HEAD`), and — if a plan exists — the extracted
   `## Context`, `## Ticket and Slack context`, `## Requirements matrix`,
   `## Flow diagram`, `## Rationale & key decisions` verbatim. Tell writer to reconcile
   every requirement against finished diff/tests: `✅ Implemented`, `⚠️ Partial`, or
   `❌ Missing`; never carry `✅ Planned` forward blindly.

Dispatch the writer headless (mirror `deep-review/scripts/executable_reviewer.sh` flags):

```bash
claude -p \
  --model sonnet \
  --output-format text \
  --max-turns 4 \
  --dangerously-skip-permissions \
  < "$RUN_DIR/writer-input.md" > "$RUN_DIR/draft.md"
```

The writer returns a single fenced block: `TITLE:` line, then `---`, then the markdown
body. Parse the title from the `TITLE:` line and the body from everything after `---`.
Write the parsed body to `$RUN_DIR/pr-body.md` and store the title.

**Reject inline** if the draft body contains an "Affected files"/"Files changed"/"Changes"
section or a `+/-` stat block — if so, re-dispatch the writer once with an explicit note
to remove it, then continue.

## Phase 2 — REVIEW (codex)

Unless `--no-codex`, dispatch a codex reviewer to validate the draft. Assemble
`$RUN_DIR/review-input.md`:
- The drafted title + body
- The output of `git diff --name-only main...HEAD` (the reviewer needs the real
  changed-path domains to judge the Mermaid diagram)
- The detected ticket (or "none")
- The explicit checklist below

Dispatch (mirror the codex side of `executable_reviewer.sh`):

```bash
codex exec \
  --skip-git-repo-check \
  --dangerously-bypass-approvals-and-sandbox \
  --color never \
  --output-last-message "$RUN_DIR/review.md" \
  - < "$RUN_DIR/review-input.md" >&2
```

The reviewer validates, returning concrete fixes:
- **Title is Conventional Commit?** valid `type`, optional scope, ≤ 70 chars.
- **Mermaid present and consistent** with the domains in `git diff --name-only main...HEAD`? (no phantom components, no missing major area)
- **NO file list / no counts** anywhere in the body?
- **Ticket present** (linked or an explicit `_no ticket_`)?
- **Slack threads present** (linked when supplied, or explicit `_none found_`)?
- **Requirements matrix complete** and statuses supported by diff/test evidence?
- **Key decisions preserved** from plan/ticket context?
- **Evidence present** — when the diff touches UI, an `## Evidence` section with a flow
  GIF/recording (and before/after for changed screens) or an honest local-asset list; when it
  does not, the explicit `_no UI change — no visual evidence_`?
- Body is objective about *what we solve* (not a changelog of the diff)?

Read `$RUN_DIR/review.md` and **apply every concrete fix** to the title / `pr-body.md`.
If the reviewer flags the file-list or ticket rules, those are blocking — re-run Phase 1
targeting the specific fix, then re-review once. Cap: 2 review iterations.

## Phase 2.5 — EVIDENCE (UI changes)

**A UI change without a picture is not reviewable.** Decide first whether this diff changes
anything a user sees — a new screen, an altered layout, new copy, a changed interaction or
state. `git diff --name-only main...HEAD` hitting component/template/style/page paths is the
signal; when it is ambiguous, assume it does.

If it does not, write exactly `_no UI change — no visual evidence_` under `## Evidence` and
move on. Never leave the section out and never invent a screenshot.

If it does, the section carries, in this order:

1. **A GIF or recording of the flow working end to end** — the whole path a user takes, not a
   still of the end state. New screen or changed flow ⇒ this is required.
2. **Before / after screenshots** for anything that changed on an existing screen.
3. **A link to the QA evidence report** (`index.html`) that these came from, plus the commit
   SHA it was captured against.

Source them, in order of preference: the `--evidence` artifacts; the QA run this PR follows
(`/qa-testing` and `/qa-execute` already capture annotated screenshots and WebVTT-captioned
videos); a fresh `agent-browser` pass over the changed flow if neither exists and the app runs
locally.

**Embedding.** Inline the asset with `![alt](url)` when a URL that GitHub can actually fetch
exists — an asset committed on the branch of a public repo, or an already-hosted report. When
one does not (private repo, local-only artifacts), do **not** fake it: list each asset by
filename with a one-line description of what it demonstrates, link the QA report path, and say
plainly that the media is local. Then attach the same list as a `gh pr comment` so the
reviewer sees it on the PR, and tell the user in Phase 4 which files to drag in if they want
them rendered inline.

Evidence is captured against the frozen SHA. If the branch moved after the capture, say so
rather than presenting stale media as current.

If `--dry-run`: print the final title + body and **stop here**. Do not open/update.

## Phase 3 — OPEN / UPDATE PR

Mirror the opener logic in
`/Users/barsotti/.local/share/chezmoi/dot_claude/skills/deep-plan/scripts/executable_pr-open.sh`
(read it): conventional-type inference from recent commits + changed paths, ticket
auto-detect, and CODEOWNERS reviewer detection. Reuse those, but the **title + body come
from Phases 1-2** — do not regenerate them from a template.

1. Ensure the title already carries a conventional-commit type. If somehow it doesn't,
   infer the type from recent commits / changed paths (as pr-open.sh does) and prefix it.
2. Compute `--reviewer` flags from `.github/CODEOWNERS` (or `CODEOWNERS`) matching the
   changed paths, exactly as pr-open.sh does.
3. Derive the label from the conventional-commit type (`--label <type>`).
4. The body is already at `$RUN_DIR/pr-body.md` — pass it with `--body-file` (HEREDOC not
   needed; the file already exists).

**Create** (no `--update`):

```bash
gh pr create \
  [--draft] \
  --title "$TITLE" \
  --body-file "$RUN_DIR/pr-body.md" \
  --assignee @me \
  --label "$PR_TYPE" \
  [--reviewer <owner> ...]
```

Retry without `--label`/`--reviewer` if `gh` errors (remote may lack them), same as pr-open.sh.

**Update** (`--update <n>`):

```bash
gh pr edit <n> \
  --title "$TITLE" \
  --body-file "$RUN_DIR/pr-body.md" \
  --add-assignee @me
```

## Phase 4 — Report

Print the PR URL and a one-line summary, e.g.:
`opened PR #1421 — feat(webhooks): prevent duplicate delivery — assigned to @me, ticket PROJ-2982`.

## Checklist (orchestrator ticks after Phase 3)

Verify each and report the state to the user:

- [ ] `title-conventional` — title matches `^(feat|fix|refactor|perf|docs|test|chore)(\(.+\))?: .+`, ≤ 70 chars
- [ ] `mermaid-present` — body has a ```mermaid block, consistent with the changed domains
- [ ] `no-file-list` — no "Affected files"/"Files changed" section, no path inventory, no `+/-` counts
- [ ] `ticket-linked-or-n/a` — ticket linked, or an explicit `_no ticket_` when none exists
- [ ] `slack-linked-or-n/a` — relevant threads linked, or explicit `_none found_`
- [ ] `requirements-reconciled` — every requirement maps to implementation evidence and status
- [ ] `key-decisions-present` — important decisions and trade-offs are preserved
- [ ] `evidence-attached` — UI change ⇒ `## Evidence` carries a flow GIF/recording, before/after
      screenshots for changed screens, and a link to the QA report + its SHA; no UI change ⇒ the
      explicit `_no UI change — no visual evidence_`
- [ ] `assigned-to-me` — PR assignee includes `@me`
- [ ] `codex-review-applied` — codex reviewer ran and its fixes were applied (or `--no-codex` was set)

If any box other than `codex-review-applied` (when `--no-codex`) is unchecked, loop back to
the relevant phase before declaring done.

## Reuse

- Headless `claude -p` / `codex exec` flag patterns: `~/.claude/skills/deep-review/scripts/executable_reviewer.sh`.
- Conventional-type inference, ticket auto-detect, CODEOWNERS reviewers: `~/.claude/skills/deep-plan/scripts/executable_pr-open.sh`.
- This skill is a runtime dependency of `deep-plan` (Phase 6 handoff) and `jira-workflow` (PR step).

## Failure modes

- Writer times out → re-dispatch once; if it fails again, surface the raw diff summary and ask the user to draft the "What this solves" paragraph.
- Codex unavailable → fall back to a Sonnet self-review (headless `claude -p --model sonnet`) applying the same checklist; note the substitution.
- `gh` not authenticated → halt at Phase 3, ask the user to `gh auth login`.
- Empty diff vs base → print "nothing to describe" and stop.
