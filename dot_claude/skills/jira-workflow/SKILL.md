---
name: jira-workflow
description: |
  MANDATORY skill whenever a message contains a Jira ticket code — even if that is the
  ENTIRE message. If the user sends only "PROJ-2982" (or any `[A-Z]{2,}-\d+` pattern —
  PROJ-123, ABC-456, PLAT-789, XY-42, etc.), treat it as an implicit "start work on
  this ticket" and invoke this skill immediately. Do NOT fall back to answering without
  the skill just because the message is short or feels ambiguous; a bare ticket code is
  always a request to begin the workflow. Also triggers on: pasted Jira URLs
  (`atlassian.net/browse/<CODE>`), phrases like "jira ticket", "this is related to
  jira", "start on this", "let's pick up", "work on the ticket", or any mention of a
  ticket the user wants to work on. The workflow covers: reading + clarifying the
  ticket, naming the Orca terminal tab, creating a branch (main repo or new worktree),
  assigning the ticket to the user and moving it to in progress, then delegating the deep
  planning to /deep-plan (grilling + domain-modeling → brainstorming → writing-plans → 5-persona
  review incl. ticket-matcher → plannotator → approved plan), which then builds it through the
  shared after-approval chain — /deep-execute for an approved `Mode: parallel` plan with 2+
  lanes, the implement skill under strict TDD otherwise, /deep-review, the qa-ui and
  qa-business agents when flows or screens change, the PR via /pr (conventional title,
  Mermaid, no file list, assigned to the user), and the PR watch for review feedback and CI
  until it merges or closes — plus the Jira steps: ticket comment and notifications.
---

# Jira Ticket Workflow

End-to-end, checklist-driven flow from the moment a Jira ticket is mentioned to a merged
PR.

**Trigger on bare ticket codes.** If the user's message is just `PROJ-2982` (or any
`[A-Z]{2,}-\d+`) with no other text, start this workflow at §1.1. That message is an
implicit "work on this ticket" — don't answer with a question or a fallback response.

Every phase has a purpose; don't skip or short-circuit them. Particular hard rules:

- **Always understand the ticket fully before writing anything.** If the description
  is thin, ambiguous, or you can't picture the acceptance criteria, ask.
- **Always confirm where the fix goes before coding.** If the blast radius isn't
  obvious after a quick exploration, ask.
- **Always write failing tests before implementation.** TDD is non-negotiable here —
  the tests are the specification.

---

## 0. Mandatory checklist

Copy this checklist into your TodoList at session start and **tick items off as you
progress**. Mirror the list in your live TodoList so progress is visible. Do not skip
items.

- [ ] **Intake**: parse ticket ID + fetch ticket via Atlassian MCP
- [ ] **Clarity check**: is the ticket self-sufficient? If not, ask targeted questions
- [ ] **Orca tab**: `orca terminal rename --title "<CODE>: <Summary>"` (skip outside Orca)
- [ ] **Location decision**: main repo or new git worktree?
- [ ] **Worktree (if chosen)**: create from `origin/main` at `.claude/worktrees/<slug>`
- [ ] **Branch**: `<type>/<CODE>-<kebab-description>` (see `.claude/rules/branching.md`)
- [ ] **Ticket start**: assign the ticket to you and move it to in progress (§1.6)
- [ ] **Deep planning** — run `/deep-plan "<CODE>" --ticket <CODE>`: grilling + domain-modeling →
      brainstorming → writing-plans → 5-persona review (incl. **ticket-matcher**, which bats
      requirements matrix point-by-point against ticket, preserving linked Slack threads) →
      plannotator → approved plan
- [ ] **Build to PR** — deep-plan runs `~/.claude/skills/_shared/after-approval.md` once;
      add the Jira steps of §3
- [ ] **Jira comment + notifications** (§3)
- [ ] **PR watch** — `/pr` Phase 5 owns it; add the Jira steps of §4

---

## 1. Intake

### 1.1 Parse the ticket code

Accept any of these as Jira signals:
- `PROJ-123` style strings in the user message (`[A-Z]{2,}-\d+`)
- Pasted URLs like `https://<org>.atlassian.net/browse/PROJ-123`
- Explicit phrases: "jira", "ticket", "start on this", "let's pick up", etc.

If the ticket code is ambiguous or missing, ask the user once.

### 1.2 Fetch ticket details

```
mcp__atlassian__getAccessibleAtlassianResources    # first call per session, cache cloudId
mcp__atlassian__getJiraIssue(cloudId, issueIdOrKey=<CODE>)
```

Pull these fields: `summary`, `status`, `assignee`, `issuetype`, `description`, `priority`,
acceptance criteria (often in description), labels, and the `url`.

### 1.3 Clarity check — **the first hard gate**

Read the ticket carefully. You must be able to answer ALL of these **before** moving on:

1. **What problem is being solved?** (current behavior vs expected behavior)
2. **Who is affected?** (which user role / code path / endpoint)
3. **What is the acceptance criteria?** (how will we know it's done)
4. **What is explicitly out of scope?** (prevents over-reach)

If any of these is unclear or unverifiable from the ticket alone, **ask the user**. Keep
the questions focused — list the ambiguities, don't interrogate. Example:

> Before I start on PROJ-2982: two things aren't clear from the ticket.
>
> 1. "Location filter should work correctly" — do you want the filter to **include
>    sub-locations** of the selected node, or only exact matches?
> 2. The ticket mentions the subscriptions list but not the create form — is the fix
>    meant to cover both, or just the list?

Do NOT proceed to the next phase until the ticket is unambiguous to you. A thin ticket
that gets coded on assumptions is the most expensive kind of rework.

If the ticket is clear, summarize what you understood back to the user in 2–3 bullets
and move on. This is an implicit confirmation.

### 1.4 Name the Orca tab

Inside an Orca terminal, name the tab after the ticket, silently:

```bash
orca terminal rename --title "<CODE>: <Summary>"
```

Outside Orca (`orca worktree current` fails), skip this step.

### 1.5 Ask: main repo or worktree?

Use `AskUserQuestion` with two options, both short:

- **Main repo** — work on the current checkout (faster for trivial fixes; OK if nothing
  else is in flight on `main`).
- **New worktree** (recommended for non-trivial work) — create
  `.claude/worktrees/<branch-slug>` from `origin/main`, matching the existing pattern in
  this repo.

If **new worktree**:

```bash
git fetch origin main --quiet
git worktree add -b <type>/<CODE>-<description> .claude/worktrees/<branch-slug> origin/main
cd .claude/worktrees/<branch-slug>
```

If **main repo**, still create the branch from a freshly-pulled `main`:

```bash
git checkout main
git pull --ff-only origin main
git checkout -b <type>/<CODE>-<description>
```

Branch-type prefix follows `.claude/rules/branching.md` (`feat/`, `fix/`, `refactor/`,
`docs/`, `chore/`). Derive it from the ticket's issuetype + description — Bug →
`fix/`, Story → `feat/`, etc.

### 1.6 Ticket start

Run `~/.claude/skills/_shared/ticket-start.md`: assign the ticket to the user, move it to
in progress, and report the transition name chosen. `/deep-plan` then finds it done.

---

## 2. Deep planning — delegate to `/deep-plan`

The heavy engineering (locate → trace → plan → TDD design → plan review) is owned by the
deep-planning pipeline. Once the ticket is understood and the branch/worktree exists, invoke:

```
/deep-plan "<CODE>" --ticket <CODE>
```

`/deep-plan` runs: grilling + domain-modeling → brainstorming → writing-plans → parallel Opus+Codex
drafts → a 5-persona review loop (architect, project-developer, **ticket-matcher**,
flow-mapper, qa) that hardens the plan and bats it **point-by-point** against the ticket's
acceptance criteria → plannotator → an approved plan at
`~/.claude/deep-plan-runs/<RUN_ID>/plan.md`. After approval it builds through to the PR (§3).

Do NOT hand-trace, hand-write tests, or plan inline here — that duplicates deep-plan. If the
ticket-matcher flags the plan as vague or missing an acceptance criterion, resolve it inside
the deep-plan loop before continuing.

## 3. Build to PR — the Jira steps

After approval, deep-plan picks the executor (`~/.claude/skills/_shared/plan-routing.md`) and
runs `~/.claude/skills/_shared/after-approval.md` itself: build, review, QA, `/pr` and the
report. Run that chain once. Do not start a second build, review or QA. Add only these steps:

- **Bug or regression ticket:** the executor drives the fix through
  `superpowers:systematic-debugging` before it writes the fix.
- **Before `/pr`:** run `Skill(skill="superpowers:verification-before-completion")`. Every
  test, new and existing, is green. Do not open the PR on red.
- **Commit message:** a Conventional Commit with `Implements <CODE>.` in the body. Do not skip
  the hooks.
- **`/pr` arguments:** `--ticket <CODE> --plan <plan.md> --evidence <qa-report-index.html>`.
- **After the PR opens:** send `<CODE> PR opened` and the PR URL as the `/pr` Phase 5 rule
  sends its notices: the Inbox thread `<CODE>`, else a `PushNotification`. Add the PR URL to
  the ticket:

  ```
  mcp__atlassian__addCommentToJiraIssue(cloudId, issueIdOrKey=<CODE>, commentBody="PR: <url>")
  ```

---

## 4. Watch the PR

`/pr` Phase 5 owns the watch: CI, every review comment from a human or a bot, the review
state, and merge conflicts, until the PR merges or closes. Do not run a second loop here.
The jira-workflow parts are these:

- When the PR is ready to merge, send `<CODE> ready to merge` the same way.
- When the PR merges, offer to move the ticket to its next Jira status.

The merge is the user's call.

---

## Tips

- **Multi-day ticket**: before each `/clear`, offer `/mattpocock-skills:handoff`. The approved
  plan and its run dir carry the decisions, so the next session resumes from them.
- **Docs, not just code**: Acme repos keep real logic in `docs/`. Confirm the change
  updates the affected docs (the `/deep-plan` plan lists them; `/deep-review` flags stale ones).
- **Worktree cleanup**: after merge, offer to run `git worktree remove .claude/worktrees/<slug>`.
- **Commit size**: if review feedback produces 3+ unrelated fixes, one commit per fix
  makes the review reply history cleaner.
- **When codex is unauthenticated**: `codex login status` exits 0 when authenticated.
  If not, prompt the user to run `codex login` — don't try to auth silently.
- **When Atlassian MCP errors**: most common cause is the cloudId being wrong. Re-fetch
  `getAccessibleAtlassianResources` and retry with the right cloudId.
- **Branch drift**: if `main` has moved during the work, rebase before opening the PR.
  If during CI, rebase and force-push (only if no one else is reviewing yet).
- **If tests don't exist for the area yet**: still write the new tests first. Then, if
  the harness/fixtures need bootstrapping, bootstrap them in a separate preparatory
  commit so the test commit stays focused.
