---
name: workflow-finish
description: Write the finish artifact of a workflow task in a repository that has `.workflow/config.json`, and mark the task ready to review. Use before `/pr` in such a repository, after a fast task is implemented and tested, or after `workflow-post-implementation`. In fast mode it records the rules, tests, correctness and simplicity checks in `workflow.md`; in standard mode it writes `finish.md`. Resolves pending decisions and loops on the verifier until it passes.
---

# workflow-finish

This stage closes the workflow of one task. It does not open the PR.

## 1. Check the repository

If `.workflow/config.json` does not exist, say "This repository has no workflow:
`.workflow/config.json` is missing." and stop.

Run the shared commands of `~/.claude/skills/_shared/workflow-artifacts.md`. Read only its
sections "Shared commands", "Run the verifier", "Field rules", and the example of the mode in
`$TASK_DIR/workflow.md`. A fast task also reads "The three reviewer roles".

- `$TASK_DIR/workflow.md` is missing: run `Skill(skill="workflow-mode")` first, then continue.
- Commit the change first. `DIFF_HASH` covers commits only. Run the shared commands again
  after the commit.

## 2a. Fast mode — complete `workflow.md`

1. Run the project's test command, for example `just test`. Record the command and the counts
   as the `tests` check.
2. Review the diff with the three reviewer roles (correctness, simplicity, repo-rules), as the
   reference says. Reuse a current `deep-review` run when one exists. Otherwise start one
   `Agent` for each role, in one message, with the diff
   `git diff "$(git merge-base "$BASE" HEAD)"..HEAD` and its persona.
3. Split the repo-rules result by rule kind. Write the `technical-rules` and
   `implementation-rules` checks, and `business-rules` when `business_rules` is `review`.
   Each check lists the selected rules of its kind in `rules[]`. A check with no selected rule
   has `rules: []` and an anchor that says so.
4. Write the correctness and simplicity results as extra checks. Write each problem as a
   finding. Fix each defect, commit the fix, and start this step again.
5. Set `diff_hash` to `DIFF_HASH`, `verdict`, `ran_at`, and `ready_to_review: true`.

## 2b. Standard mode — write `finish.md`

1. Run the verifier with `--through post-implementation`. A violation in an earlier artifact
   goes back to its stage: `Skill(skill="workflow-post-plan")` or
   `Skill(skill="workflow-post-implementation")`. A new commit after the review makes
   `post-implementation.md` stale. Run that stage again. Do not review in this stage.
2. Read `$TASK_DIR/decisions.md`. Ask the user about each `pending` decision with
   `AskUserQuestion`. Write the answer in `summary` and set `status: "decided"`.
3. Write `$TASK_DIR/finish.md` like the example, with `diff_hash` set to `DIFF_HASH` and
   `ready_to_review: true`.

## 3. Verify

```bash
node .workflow/scripts/verify.mjs --base-ref "$BASE" --through finish --enforcement blocking
```

Fix each violation with the table in the reference, and run it again. Stop after 3 rounds
with violations left, and ask the user. Commit the artifacts when the verifier passes. The
hash excludes `.workflow/`, so this commit keeps it current.

Next: run `/pr`.
