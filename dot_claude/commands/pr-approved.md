---
description: The PR is approved. Resolve every open thread, wait for green CI, squash-merge, then remove the remote branch and the Orca worktree when no task is left in it.
---

# /pr-approved

**Arguments:** `$ARGUMENTS` (optional PR number or URL; default: the PR of the current branch)

Invoke the `pr-approved` skill. Do not run the steps inline. The skill lives at
`~/.claude/skills/pr-approved/SKILL.md`. Follow its sections in order:

1. **threads** — reply to and resolve every open review thread, with `address-pr-comments`.
2. **ci** — wait for the checks; fix a red one and start again.
3. **merge** — `gh pr merge --squash`, only when nothing is open and CI is green.
4. **tasks** — check whether work is left in this worktree.
5. **cleanup** — when nothing is left: delete the remote branch, then remove the Orca worktree
   and its local branch.
6. **report** — merge commit, threads, CI, cleanup.
