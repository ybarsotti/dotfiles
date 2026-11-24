---
name: jira-workflow
description: Use when a message contains a Jira ticket key such as PROJ-123 (even alone) or a pasted Jira URL (atlassian.net/browse/KEY), which means start work on the ticket. Also for start on this, let's pick up. Assigns it to you, moves it In Progress, plans with simple-plan or deep-plan (you confirm), builds, opens the PR, and keeps Jira in step to Done. Not for watching a fixed ticket (use follow-up-jira).
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
- [ ] **Pick the planner** (§2): read `~/.claude/skills/_shared/plan-routing.md`, recommend
      `/simple-plan` or `/deep-plan` with a one-sentence reason, and wait for the user to confirm
- [ ] **Plan**: run the chosen planner with `--ticket <CODE>` until the plan is approved
- [ ] **Build to PR**: the planner runs `~/.claude/skills/_shared/after-approval.md` once. Add
      the Jira steps of §3
- [ ] **PR opened** (after-approval section 7): move the ticket to the review status, report the
      transition name chosen, and comment the PR link (§3)
- [ ] **PR merged** (after-approval section 7, the watch of `/ship-it`): move the ticket to Done or the
      project equivalent, and comment (§4)

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
in progress, and report the transition name chosen. The planner then finds it done.

---

## 2. Plan — pick the planner

Once the ticket is clear and the branch exists, choose the planner. Read
`~/.claude/skills/_shared/plan-routing.md`. Apply its criteria to the ticket:

- `/simple-plan` for a small or medium change: one module, an existing pattern, no new contract.
- `/deep-plan` for a large or risky change: business behavior, permissions, a migration, a
  third-party integration, or scope with more than one reasonable reading.

Recommend one planner. Give the reason in one sentence. Stop and wait. The user confirms or
overrides, and an override needs no reason. Then run the chosen planner:

```
/simple-plan "<CODE>" --ticket <CODE>
/deep-plan "<CODE>" --ticket <CODE>
```

Each planner owns the engineering work: locate, trace, plan, TDD design and plan review. Both
end in an approved plan, and then build through to the PR (§3). `/simple-plan` asks the same
routing question in its Phase 0.5. When the user has already confirmed the planner here, tell
it so. It does not ask again.

Do NOT hand-trace, hand-write tests, or plan inline here. That duplicates the planner. If the
plan reviewer flags the plan as vague or missing an acceptance criterion, resolve it inside the
planner loop before you continue. If the scope grows during planning, recommend again.

## 3. Build to PR — the Jira steps

After approval, the planner picks the executor (`~/.claude/skills/_shared/plan-routing.md`) and
runs `~/.claude/skills/_shared/after-approval.md` itself: build, review, QA, `/ship-it` and the
report. Run that chain once. Do not start a second build, review or QA. Add only these steps:

- **Bug or regression ticket:** the executor drives the fix through
  `superpowers:systematic-debugging` before it writes the fix.
- **Before `/ship-it`:** run `Skill(skill="superpowers:verification-before-completion")`. Every
  test, new and existing, is green. Do not open the PR on red.
- **Commit message:** a Conventional Commit with `Implements <CODE>.` in the body. Do not skip
  the hooks.
- **`/ship-it` arguments:** `--ticket <CODE> --plan <plan.md> --evidence <qa-report-index.html>`.
- **After the PR opens** (after-approval section 7): do these steps in order.
  1. Send `<CODE> PR opened` and the PR URL as the `/ship-it` Phase 5 rule sends its notices: the
     Inbox thread `<CODE>`, else a `PushNotification`.
  2. Move the ticket to the review status. List the transitions with
     `mcp__atlassian__getTransitionsForJiraIssue`. Choose the one named like "In Review" or
     "Code Review" (case-insensitive). If none matches, choose the transition whose target
     name reads as review. If still none, ask the user. Apply it with
     `mcp__atlassian__transitionJiraIssue`. Skip it when the ticket is already in that status.
     Report the transition name chosen in one line.
  3. Comment the PR link:

     ```
     mcp__atlassian__addCommentToJiraIssue(cloudId, issueIdOrKey=<CODE>, commentBody="PR: <url>")
     ```

---

## 4. Watch the PR

`/ship-it` Phase 5 owns the watch: CI, every review comment from a human or a bot, the review
state, and merge conflicts, until the PR merges or closes. Do not run a second loop here.
The jira-workflow parts are these:

- When the PR is ready to merge, send `<CODE> ready to merge` the same way.
- When the PR merges, do these steps:
  1. List the transitions with `mcp__atlassian__getTransitionsForJiraIssue`. Choose the one
     named "Done", or the project's equivalent (a transition whose target status category key
     is `done`, such as "Closed" or "Resolved"). If more than one fits, or none, ask the user.
  2. Apply it with `mcp__atlassian__transitionJiraIssue`. Report the transition name chosen.
  3. Comment on the ticket with `mcp__atlassian__addCommentToJiraIssue`: the PR link and
     "Merged".

The merge is the user's call. Move the ticket only after the merge happens.

---

## Tips

- **Multi-day ticket**: before each `/clear`, offer `/mattpocock-skills:handoff`. The approved
  plan and its run dir carry the decisions, so the next session resumes from them.
- **Docs, not just code**: Acme repos keep real logic in `docs/`. Confirm the change
  updates the affected docs (the plan lists them; `/deep-review` flags stale ones).
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
