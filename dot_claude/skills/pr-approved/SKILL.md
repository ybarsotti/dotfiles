---
name: pr-approved
description: Use when invoked via /pr-approved, or when the user says a PR is approved and asks to merge and clean up. Resolves every open review thread, waits for green CI, squash-merges, then removes the Orca worktree and the remote branch when no task is left in it.
---

# pr-approved

The user approved the PR. Close it out: no open feedback, green CI, a squash merge, and a
clean workspace. The command of the user is the authorization to merge. Do not ask again,
unless a check below fails.

## Setup

```bash
S=~/.claude/skills/pr-approved/scripts/pr-approved.sh
W=~/.claude/skills/_shared/workflow.sh
PR=<the PR number or URL from the arguments, else empty for the PR of the current branch>
RUN_DIR=~/.claude/pr-approved-runs/$(date +%Y%m%d-%H%M%S)
$W init "$RUN_DIR/chain.md" pr-approved --project "$(git rev-parse --show-toplevel)"
$S state $PR
```

Mark each step of `$RUN_DIR/chain.md` when it ends: `done` with its evidence, `skip` with the
reason, `block` before you ask the user.

## 1. threads — no open feedback

1. Read `open_threads` from `$S state`.
2. When a thread is open, run `Skill(skill="address-pr-comments")`. It fixes each valid
   comment in scope, replies in each thread, and resolves it. A comment that is not
   actionable (a question, a nit you decline, a note) still gets a reply with the answer or
   the reason, then a resolve.
3. Read the PR conversation too: `gh pr view $PR --json comments,reviews`. Answer each
   unanswered review or comment that asks for something.
4. Run `$S state` again. `open_threads` must be empty. A thread that waits on a decision of
   the user stays open: mark the step `block` and ask. Do not merge.

## 2. ci — green checks

1. When `checks.pending` is not empty, wait: `gh pr checks $PR --watch --fail-fast`, in the
   background. Do not poll in a loop.
2. When `checks.failing` is not empty, run `superpowers:systematic-debugging` on the failure.
   Fix it, push, and go back to step 1 (threads), because a push can bring new comments.
3. Run `$S state` again. Go on only when `ready` is `true`. When `mergeable` is `CONFLICTING`,
   rebase on the base branch, run the tests, push, and start again at step 1.

## 3. merge — squash

```bash
gh pr merge $PR --squash
gh pr view $PR --json state,mergeCommit -q '.state + " " + .mergeCommit.oid'
```

The state must be `MERGED`. When branch protection refuses the merge, report the reason and
stop. Do not use `--admin`.

When the run uses `jira-workflow`, do its "PR merged" step: move the ticket to Done and
comment. When this session runs the PR watch of `/pr`, stop it (`ScheduleWakeup` with
`stop: true`, or `CronDelete`).

## 4. tasks — is work left in this worktree?

```bash
ROOT=$(git rev-parse --show-toplevel)
$S pending "$ROOT"
```

`keep: true` means the worktree stays. The reasons name what is left: uncommitted changes,
commits not pushed, open steps of another run, or a breakdown with more tasks. For a
breakdown, read it and check which tasks have a plan file; a task with no plan is still to do.
When tasks are left, name the next one and stop here: skip the `cleanup` step with that
reason.

## 5. cleanup — remote branch and worktree

Run this only when `keep` is `false`.

1. Delete the remote branch: `git push origin --delete <head>`. A branch that GitHub already
   deleted on merge is fine.
2. Check Orca: `orca worktree current --json`. When it fails, this is not an Orca worktree:
   stop after step 1 and report.
3. Write the final report first (section 6). Removing the worktree can end this session.
4. Remove the worktree with its local branch. `current` is refused, so pass its id:
   ```bash
   WT="id:$(orca worktree current --json | jq -r '.result.worktree.id')"
   orca worktree rm --worktree "$WT" --delete-branch --json
   ```
   Orca keeps a local branch it cannot prove merged, and a squash merge is not provable. When
   the result shows the branch kept, delete it from the main checkout after the merge check of
   step 3: `git -C <main checkout> branch -D <head>`.

## 6. report

Tell the user, in a short block: the merge commit, the threads you answered and resolved,
the CI result, and what you cleaned up or why the worktree stays. Name the next task when one
is left.
