---
name: jira-workflow
description: |
  MANDATORY skill whenever a message contains a Jira ticket code — even if that is the
  ENTIRE message. If the user sends only "FBIT-2982" (or any `[A-Z]{2,}-\d+` pattern —
  FBB-123, FBIT-456, PROJ-789, AFB-42, etc.), treat it as an implicit "start work on
  this ticket" and invoke this skill immediately. Do NOT fall back to answering without
  the skill just because the message is short or feels ambiguous; a bare ticket code is
  always a request to begin the workflow. Also triggers on: pasted Jira URLs
  (`atlassian.net/browse/<CODE>`), phrases like "jira ticket", "this is related to
  jira", "start on this", "let's pick up", "work on the ticket", or any mention of a
  ticket the user wants to work on. The workflow covers: reading + clarifying the
  ticket, renaming the cmux tab, creating a branch (main repo or new worktree),
  transitioning the Jira status to "Under investigation", then delegating the deep
  planning to /deep-plan (grill-with-docs → brainstorming → writing-plans → 5-persona
  review incl. ticket-matcher → plannotator → approved plan), then executing it — via
  /deep-execute for an approved `Mode: parallel` plan with 2+ lanes (lane fanout, round
  tests, run-state validation, orchestrator commits, one final /deep-review), or the
  superpowers execution workflow under strict TDD otherwise — running /qa-test-plan when
  flows or screens change, opening the PR via /pr-description (conventional title,
  Mermaid, no file list, assigned to the user), and looping on CI + Copilot feedback
  until both are clean.
---

# Jira Ticket Workflow

End-to-end, checklist-driven flow from the moment a Jira ticket is mentioned to a merged
PR.

**Trigger on bare ticket codes.** If the user's message is just `FBIT-2982` (or any
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
- [ ] **cmux tab**: `cmux rename-tab "<CODE>: <Summary>"` + `cmux set-status jira <CODE>`
- [ ] **cmux notify (start)**: `cmux notify --title "Starting <CODE>" --body "<summary>"`
- [ ] **Location decision**: main repo or new git worktree?
- [ ] **Worktree (if chosen)**: create from `origin/main` at `.claude/worktrees/<slug>`
- [ ] **Branch**: `<type>/<CODE>-<kebab-description>` (see `.claude/rules/branching.md`)
- [ ] **Jira transition**: move ticket to the "Under investigation" transition
- [ ] **Continuity ledger** (multi-day ticket): bind/create via `continuity-ledger`
      (`new <CODE>`), then **save** at each progress boundary below — it auto-loads on resume
      after `/clear`. Skip for a quick single-session fix.
- [ ] **Deep planning** — run `/deep-plan "<CODE>" --ticket <CODE>`: grill-with-docs →
      brainstorming → writing-plans → 5-persona review (incl. **ticket-matcher**, which bats
      requirements matrix point-by-point against ticket, preserving linked Slack threads) →
      plannotator → approved plan
- [ ] **Execute approved plan** — the plan's `## Execution shape` decides the path:
      `Mode: parallel` + 2+ lanes → `/deep-execute ~/.claude/deep-plan-runs/<RUN_ID>/plan.md`
      (lane fanout, round tests, run-state validation, orchestrator commits, one final
      `/deep-review`). Anything else → superpowers execution (`subagent-driven-development` /
      `executing-plans`) under strict TDD, then `/simplify` ×2 and `/deep-review`.
- [ ] **`/qa-test-plan`** (if the plan's QA flag is "yes" — flow change or new screens):
      manual test doc + codex review + agent-browser execution with video
- [ ] **Re-run tests**: every test (new + existing) must be green
- [ ] **`/pr-description`**: title + ticket/Slack + reconciled requirements + Mermaid +
      decisions, **no file list**, assigned to me
- [ ] **cmux notify (PR opened)**
- [ ] **Wait for CI green** (in parallel with Copilot loop)
- [ ] **Copilot review loop** — keep checking until **zero new comments**; address every
      actionable one and reply in-thread
- [ ] **cmux notify (ready to merge)** + `cmux clear-status jira`

Use `cmux set-progress` at natural boundaries:

| Phase complete | Progress |
|---|---|
| Intake + clarity | 0.10 |
| Branch created | 0.15 |
| Plan approved (`/deep-plan`) | 0.30 |
| Plan executed (`/deep-execute`, or superpowers build + `/simplify` + `/deep-review`) | 0.75 |
| PR opened (`/pr-description`) | 0.85 |
| CI + Copilot clean | 1.00 |

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

> Before I start on FBIT-2982: two things aren't clear from the ticket.
>
> 1. "Location filter should work correctly" — do you want the filter to **include
>    sub-locations** of the selected node, or only exact matches?
> 2. The ticket mentions the subscriptions list but not the create form — is the fix
>    meant to cover both, or just the list?

Do NOT proceed to the next phase until the ticket is unambiguous to you. A thin ticket
that gets coded on assumptions is the most expensive kind of rework.

If the ticket is clear, summarize what you understood back to the user in 2–3 bullets
and move on. This is an implicit confirmation.

### 1.4 Update cmux chrome

Run these in order (silently — don't narrate each one):

```bash
cmux rename-tab "<CODE>: <Summary>"
cmux set-status jira "<CODE>" --icon "briefcase" --color "#0052CC"
cmux notify --title "Starting <CODE>" --body "<Summary>"
cmux set-progress 0.10 --label "Intake"
```

The `CMUX_WORKSPACE_ID` / `CMUX_TAB_ID` env vars are auto-set in cmux terminals, so no
explicit targeting is needed. Use `set-status` with key `jira` so multiple workflows
don't clobber each other.

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
`fix/`, Story → `feat/`, etc. Set `cmux set-progress 0.15 --label "Branch ready"`.

### 1.6 Transition Jira to "Under investigation"

Jira transition names vary per project. Don't guess — enumerate first:

```
mcp__atlassian__getTransitionsForJiraIssue(cloudId, issueIdOrKey=<CODE>)
```

Find the transition whose `name` matches "Under investigation" (case-insensitive,
trimmed). If there's no exact match, fall back to the closest of:
`In Progress`, `In Review`, `Investigating`, or — if truly nothing fits — ask the user
which transition to apply.

```
mcp__atlassian__transitionJiraIssue(cloudId, issueIdOrKey=<CODE>, transition={id: <id>})
```

Confirm in a single short line: `"TICKET-1234 → Under investigation"`.

---

## 2. Deep planning — delegate to `/deep-plan`

The heavy engineering (locate → trace → plan → TDD design → plan review) is owned by the
deep-planning pipeline. Once the ticket is understood and the branch/worktree exists, invoke:

```
/deep-plan "<CODE>" --ticket <CODE>
```

`/deep-plan` runs: grill-with-docs → brainstorming → writing-plans → parallel Opus+Codex
drafts → a 5-persona review loop (architect, project-developer, **ticket-matcher**,
flow-mapper, qa) that hardens the plan and bats it **point-by-point** against the ticket's
acceptance criteria → plannotator → an approved plan at
`~/.claude/deep-plan-runs/<RUN_ID>/plan.md`. It **stops at the approved plan**.

Do NOT hand-trace, hand-write tests, or plan inline here — that duplicates deep-plan. If the
ticket-matcher flags the plan as vague or missing an acceptance criterion, resolve it inside
the deep-plan loop before continuing. Set `cmux set-progress 0.30 --label "Plan approved"`.

## 3. Execute approved plan

Check the approved plan's `## Execution shape` section — its `Mode:` line (plus lane count)
decides which path applies. `/deep-execute` itself refuses to start on anything but
`Mode: parallel`, so don't hand it a serial plan.

**`Mode: parallel` with 2+ lanes → delegate to `/deep-execute`:**

```
/deep-execute ~/.claude/deep-plan-runs/<RUN_ID>/plan.md
```

`/deep-execute` owns lane fanout, round tests, run-state validation, orchestrator commits,
and one final `/deep-review` — do NOT hand-run the superpowers execution workflow, `/simplify`,
or `/deep-review` separately here; that duplicates what `/deep-execute` already does at the
end of its last round. See `dot_claude/skills/deep-execute/SKILL.md` (and
`ARCHITECTURE.md` §9) for the fan-out, round-gate, and contract-drift protocol.

**`Mode: serial`, or no declared shape → build it yourself:**

- `Skill(skill="superpowers:using-git-worktrees")` if not already isolated (you usually made
  a worktree in §1.5 — reuse it).
- `Skill(skill="superpowers:subagent-driven-development")` (or `executing-plans` when
  subagents are unavailable) against `~/.claude/deep-plan-runs/<RUN_ID>/plan.md`.
- Strict red-green-refactor per `superpowers:test-driven-development`. **Mock only the
  outermost boundaries** (network, 3rd-party APIs, clock/random) — inner services,
  repositories, and domain logic run REAL code in tests.
- **Bug/regression ticket?** Drive the fix through `superpowers:systematic-debugging`
  (reproduce → minimise → hypothesise → instrument → fix → regression-test) before writing
  the fix.
- Then `/simplify` ×2 (re-run tests after each pass) and `/deep-review` (the fixed-roster
  panel); `Skill(skill="superpowers:receiving-code-review")` before applying its findings,
  then address every actionable one with a small TDD cycle.

**Either path:** `Skill(skill="superpowers:verification-before-completion")` once execution
reports complete, before any PR work. Set `cmux set-progress 0.75 --label "Plan executed"`
when tests are green and (for the parallel path) `/deep-review` came back clean.

## 4. QA test plan (only if flows/screens changed)

If the deep-plan `plan.md` `## QA / test-execution` flag is **yes** (a user-facing flow
changed or a screen was added), run:

```
/qa-test-plan --ticket <CODE>
```

It writes a manual test plan to the project's `./tmp/`, has a codex agent review it, then
drives `agent-browser` (codex worker via cmux) to execute the steps and record a video,
returning a pass/fail report. Reference the report + video path on the PR/ticket.

## 5. Verification

Confirm every test (new + existing) is green and `verification-before-completion` passed.
Do not open the PR on red.

## 6. PR creation

### 6.1 Commit

Conventional commit message. Mention the ticket in the body:

```
<type>(<scope>): <short summary>

Implements <CODE>.

<optional longer description>
```

Don't skip hooks. Don't `--no-verify`.

### 6.2 Push + open PR — `/pr-description`

Push the branch, then let `/pr-description` build the title + body and open the PR — do NOT
hand-write the PR body here:

```bash
git push -u origin HEAD
```
```
/pr-description --ticket <CODE> --plan ~/.claude/deep-plan-runs/<RUN_ID>/plan.md
```

`/pr-description` produces a Conventional-Commit title `<type>(<scope>): <summary> (<CODE>)`
and an **objective** body — what it solves + ticket/Slack links + reconciled requirements
matrix + Mermaid + rationale/key decisions. It contains **no file list and no counts**.
A codex agent reviews the draft,
the PR is opened **assigned to you** (`--assignee @me`), and CODEOWNERS reviewers are added.

`cmux notify --title "<CODE> PR opened" --body "<PR URL>"` + `set-progress 0.85`.

### 6.3 Jira comment (optional but nice)

Add the PR URL to the ticket:

```
mcp__atlassian__addCommentToJiraIssue(cloudId, issueIdOrKey=<CODE>, commentBody="PR: <url>")
```

---

## 7. CI + Copilot loop

Both run concurrently. Keep looping until **both** converge.

### 7.1 CI watcher

```bash
gh pr view <pr-number> --json statusCheckRollup \
  --jq '.statusCheckRollup[] | {name, status, conclusion}'
```

Wait for all checks to be `COMPLETED`. If anything fails, don't hot-patch blindly — drive it
through `superpowers:systematic-debugging` (reproduce the failure locally, minimise,
hypothesise, fix, add a regression test), then push and the loop resumes. Don't close the loop
while anything is `IN_PROGRESS`.

### 7.2 Copilot review loop

Copilot's PR review arrives within ~5 min of the PR being opened (sometimes sooner).
Fetch inline comments with:

```bash
gh api repos/<owner>/<repo>/pulls/<pr-number>/comments
```

For every new comment (compare `commit_id` against what's already been addressed):

1. Read the comment carefully. Classify as valid / invalid / stylistic.
2. If valid, make the fix. If stylistic and the project doesn't enforce it, skip with a
   short thread reply explaining.
3. Reply to the comment via:
   ```bash
   gh api repos/<owner>/<repo>/pulls/<pr-number>/comments/<comment-id>/replies \
     -F body='Fixed in <commit-sha>. <one-line rationale>.'
   ```
4. Push the fix.

After every push, Copilot may post a *new* review on the new commit. **Keep looping** —
wait 3–5 min, re-fetch comments, address anything new. The loop ends when a fetch
returns no unaddressed comments.

### 7.3 Wrap-up

When CI is green AND Copilot has no new comments for at least one full iteration after
the last fix:

```bash
cmux notify --title "<CODE> ready to merge" --body "All checks green, Copilot clean"
cmux set-progress 1.0 --label "Ready to merge"
cmux clear-status jira
```

Then hand control back to the user — the actual merge is their call.

---

## Tips

- **Continuity ledger**: on a multi-day ticket, `save the continuity ledger` before each
  `/clear` (after plan approval, after build, before PR). It auto-loads next session so you
  resume with the plan, decisions, and run dir intact — no re-derivation.
- **Docs, not just code**: FilterBuy repos keep real logic in `docs/`. Confirm the change
  updates the affected docs (the `/deep-plan` plan lists them; `/deep-review` flags stale ones).
- **Scheduling**: for the CI + Copilot loop, use `ScheduleWakeup` with ~240s delays
  (stays inside the 5-minute prompt cache TTL). Don't poll tighter than that.
- **Worktree cleanup**: after merge, offer to run `git worktree remove .claude/worktrees/<slug>`.
- **Commit size**: if review feedback produces 3+ unrelated fixes, one commit per fix
  makes the Copilot reply history cleaner.
- **When codex is unauthenticated**: `codex login status` exits 0 when authenticated.
  If not, prompt the user to run `codex login` — don't try to auth silently.
- **When Atlassian MCP errors**: most common cause is the cloudId being wrong. Re-fetch
  `getAccessibleAtlassianResources` and retry with the right cloudId.
- **Branch drift**: if `main` has moved during the work, rebase before opening the PR.
  If during CI, rebase and force-push (only if no one else is reviewing yet).
- **If tests don't exist for the area yet**: still write the new tests first. Then, if
  the harness/fixtures need bootstrapping, bootstrap them in a separate preparatory
  commit so the test commit stays focused.
