---
name: pr-description
description: Use for /ship-it, or when the user asks to write, open or update a pull request, or on handoff from deep-plan, simple-plan or jira-workflow. Writes a Conventional Commit title and a body with ticket, requirements matrix, Mermaid and verification, then opens the PR assigned to the user.
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
  rationale/key decisions, verification, **`## Evidence by requirement`** (see Phase 0.5),
  `## Deviations from the plan`, `## How to review` (reading order, 3 to 5 risk links, what
  to skim), and — whenever the change touches UI — an
  **`## Evidence`** section (see Phase 2.5), and — whenever it touches who may do what — an
  **`## Permissions`** section (see Phase 2.6).
- **Body must NOT contain**: a changed-file list, file paths as an inventory, or file/line
  counts. The 3 to 5 risk links of `## How to review` are the only file paths allowed. Objective about *what we solve*, not *what moved*.
- **Writer is claude Sonnet. Reviewer is codex.** Any additional reviewers on the claude side are Sonnet; the codex reviewer stays codex.
- **PR is assigned to the user**: `--assignee @me` on create, `--add-assignee @me` on update.

## Phase 0 — Parse args & sanity checks

Read `$ARGUMENTS`. Extract:

- `--plan <path>` — deep-plan `plan.md` to source sections + ticket from (else none)
- `--ticket KEY-123` — explicit ticket (else auto-detect)
- `--update <pr-number>` — update this PR instead of creating (else create)
- `--draft` — open as draft (create only)
- `--no-codex` — skip the codex reviewer, Sonnet self-review only
- `--no-watch` — open the PR and stop; skip Phase 5
- `--evidence <path>` — a QA evidence dir or `index.html` (screenshots, recordings) to source
  the `## Evidence` section from. Repeatable. When omitted, look for the newest
  `.qa-reports/*/execute/*/index.html` and the calling run's `--qa` artifact before concluding
  there is none.
- `--dry-run` — print the drafted title + body, do not open/update

Set `RUN_DIR=~/.claude/pr-runs/$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD 2>/dev/null)`. Create it with `mkdir -p`. Drafts, the review, and the final body live there.

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

## Phase 0.5 — Spec check and proofs

Follow sections 2, 4 and 5 of `~/.claude/skills/_shared/spec-evidence.md`.

1. **The plan is still the approved one.** With `--plan`, run
   `~/.claude/skills/_shared/plan-stamp.sh check <plan>`. Exit 1 stops here: report the changed
   plan to the user and open nothing. Exit 2 continues, and `## Verification` says the plan
   carries no approval stamp.
2. **Run each proof at HEAD.** Run every `test` and `command` proof, link every `qa` proof to
   the `--evidence` artifact, and write one line per row to `$RUN_DIR/evidence.tsv`. Read
   `references/proofs.md` before you build the rows. It holds the row sources and the line format.
3. **A failed or missing proof blocks the PR.** Fix it, or ask the user to defer the row with a
   reason. Never write `pass` for a proof that did not run.
4. **Deviations.** Copy the plan's `## Deviations` rows, or `None`.

## Phase 0.6 — Chain gate (before you write anything)

A PR opens only after the build chain ran (`~/.claude/skills/_shared/after-approval.md`). This
gate applies to every caller: a planning skill, `implement`, `deep-execute`, an orchestrator
that starts its own agents, or a direct `/ship-it`. Run the three checks against HEAD.

1. **Code review.** One of these covers HEAD:
   - a `/deep-review` run: `~/.claude/skills/deep-review/scripts/check-stale.sh <run-dir>`
     exits 0, and its report has no open CRITICAL or HIGH finding;
   - the review that the project requires (for example the review receipts of `.fbworkflow`
     or `.workflow`), recorded for HEAD with no open blocking finding.
2. **QA.** When the change alters a flow or a screen that a person uses: a `qa-business`
   report (`~/.claude/agents/qa-business.md`) that names HEAD, with `GO` and no `FAIL`. A
   report that names an older commit counts only when no product code changed after it. When
   the environment did not answer, the recorded line `QA skipped: <url> did not answer`
   counts instead.
3. **UI parity.** When the change alters UI and a design canvas exists for it: a `qa-ui`
   report with `Verdict: MATCH at <sha>`, where `<sha>` is HEAD or a commit after which no UI
   file changed. Look for the canvas in the `Canvas:` line of the plan, in the run's
   `decisions.md`, in the arguments, and in the conversation (a `claude.ai/artifact/` link
   named as the design of this change). The screenshots and the visual pass of the agent that
   built the UI are not parity evidence.

When a check fails, do not open or update the PR. Print `Chain gate: <check> not done` and
the reason. Then run the missing step as `after-approval.md` describes: sections 2, 4 or 5,
in an Orca worker when the session runs in Orca. Run `/ship-it` again after it passes.

Skip a check only when the user says so for this PR. Then write `<check> not done: <reason>`
under `## Evidence`. A fix to the PR body or the PR title alone does not re-run the gate.

## Phase 1 — WRITE (claude Sonnet)

Read `references/writer-dispatch.md` before you assemble the writer input. It holds the input
layout, the `claude -p` command and the parse rules. The writer input never carries file names
or counts into the body. **Reject inline** a draft body that contains an "Affected files",
"Files changed" or "Changes" section or a `+/-` stat block: re-dispatch the writer once with a
note to remove it, then continue.

## Phase 2 — REVIEW (codex)

Unless `--no-codex`, dispatch a codex reviewer to validate the draft.

Read `references/review-dispatch.md` and `references/reviewer-checklist.md` before you assemble
`$RUN_DIR/review-input.md`. The first holds the input list and the `codex exec` command. The second
holds the checklist that goes into the input.

Read `$RUN_DIR/review.md` and **apply every concrete fix** to the title / `pr-body.md`.
If the reviewer flags the file-list or ticket rules, those are blocking — re-run Phase 1
targeting the specific fix, then re-review once. Cap: 2 review iterations.

## Phase 2.5 — EVIDENCE (UI changes)

**A UI change without a picture is not reviewable.** Decide first whether this diff changes
anything a user sees. When it is ambiguous, assume it does. With no UI change, write exactly
`_no UI change — no visual evidence_` under `## Evidence`. Never leave the section out and never
invent a screenshot. Never commit media to the repository, on any branch.

Read `references/evidence.md` before you write the `## Evidence` section. It holds the content
order, the sources and the `gh --attach` embedding steps.

## Phase 2.6 — PERMISSIONS (access changes)

**A reviewer cannot approve an access change they have to infer.** Decide whether this diff
changes who may do what (a role, permission, scope, guard, policy or row-level rule). When it is
ambiguous, assume it does. With no access change, leave the section out.

Read `references/permissions.md` before you write the `## Permissions` section. It holds the
table template and its five rules. Derive every cell from the code in the diff, not from the
ticket's intention.

## Phase 2.7 — BLINDSPOT (every PR)

The body makes claims about code, about tests, about CI, and about systems this PR does not
touch. Phase 2 reviewed those claims against the files that were opened. Run the pass that
covers the rest:

```
Skill(skill="blindspot")
```

The artifact is the PR body. Label every claim READ or INFERRED, then open the surface behind
each INFERRED claim or rewrite the claim to what was observed. The claims this catches most
often are "the existing tests cover this", "CI runs it", "no consumer reads that field" and a
`file:line` nobody opened. Rewrite the body before Phase 3. A PR body that overstates its
evidence costs a reviewer more than a short one.

If `--dry-run`: print the final title + body and **stop here**. Do not open/update.

## Phase 3 — OPEN / UPDATE PR

Mirror the opener logic in
`~/.claude/skills/deep-plan/scripts/pr-open.sh`
(read it): conventional-type inference from recent commits + changed paths, ticket
auto-detect, and CODEOWNERS reviewer detection. Reuse those, but the **title + body come
from Phases 1-2** — do not regenerate them from a template.

0. **The proofs still match HEAD.** When HEAD moved after Phase 0.5, run the proofs again and
   update `## Evidence by requirement` before you open or update the PR.
1. Ensure the title already carries a conventional-commit type. If somehow it doesn't,
   infer the type from recent commits / changed paths (as pr-open.sh does) and prefix it.
2. Compute `--reviewer` flags from `.github/CODEOWNERS` (or `CODEOWNERS`) matching the
   changed paths, exactly as pr-open.sh does.
3. Derive the label from the conventional-commit type (`--label <type>`).
4. The body is already at `$RUN_DIR/pr-body.md` — pass it with `--body-file` (HEREDOC not
   needed; the file already exists).

Read `references/open-pr.md` before you run `gh`. It holds the create and update commands.

## Phase 4 — Report

Read `references/report.md` before you print the report. It holds the demo rule, the report line and the CI suggestion.

## Phase 5 — Watch and address feedback (default; skip with `--no-watch`)

An open PR is not done. Watch it until it merges or closes. Skip this phase for
`--draft`, `--dry-run` and `--no-watch`.

Read `references/watch.md` before you start the watch. It holds the six watch steps, the two
stages and the notification rules. Stop the loop when the PR merges or closes.

## Checklist (orchestrator ticks after Phase 3)

Read `references/checklist.md` and verify each box. Report the state to the user. If any box
other than `codex-review-applied` (when `--no-codex`) is unchecked, loop back to the relevant phase
before declaring done.

## Reuse

- Headless `claude -p` / `codex exec` flag patterns: `~/.claude/skills/deep-review/scripts/reviewer.sh`.
- Conventional-type inference, ticket auto-detect, CODEOWNERS reviewers: `~/.claude/skills/deep-plan/scripts/pr-open.sh`.
- This skill is a runtime dependency of `deep-plan` (Phase 6 handoff) and `jira-workflow` (PR step).

## Failure modes

- Writer times out → re-dispatch once; if it fails again, surface the raw diff summary and ask the user to draft the "What this solves" paragraph.
- Codex unavailable → fall back to a Sonnet self-review (headless `claude -p --model sonnet`) applying the same checklist; note the substitution.
- `gh` not authenticated → halt at Phase 3, ask the user to `gh auth login`.
- Empty diff vs base → print "nothing to describe" and stop.
