---
name: workflow-post-implementation
description: Write the post-implementation artifact of a standard workflow task in a repository that has `.workflow/config.json`. Use after the build of an approved plan, when the build chain hands over its deep-review and QA results, or when the user asks to record the implementation review. Records the tests, runtime, correctness, simplicity and repo-rules checks (reusing earlier review results), writes `post-implementation.md`, and loops on the verifier until it passes.
---

# workflow-post-implementation

This stage records the review of the implemented change. It does not plan or open a PR.

## 1. Check the repository

If `.workflow/config.json` does not exist, say "This repository has no workflow:
`.workflow/config.json` is missing." and stop.

Run the shared commands of `~/.claude/skills/_shared/workflow-artifacts.md`. Read only its
sections "Shared commands", "Run the verifier", "Field rules", "The three reviewer roles" and
the example of `post-implementation.md`.

- `$TASK_DIR/workflow.md` is missing: run `Skill(skill="workflow-mode")` first, then continue.
- The mode is `fast`: this stage has no artifact. Go to Next.
- Commit the change first. `DIFF_HASH` covers commits only. Run the shared commands again
  after the commit.

## 2. Collect the evidence

| Check | Evidence |
|---|---|
| `tests` | Run the project's test command, for example `just test`. Record the command and the counts. |
| `runtime` | Run the changed code for real. Reuse the `qa-business` and `qa-ui` results of the build chain when they ran on this commit. Otherwise run the app, the command or the endpoint yourself. A change with no runtime surface, such as documentation, records that reason. |
| `correctness`, `simplicity`, `repo-rules` | The three reviewer roles of the reference. |

For the three reviewer roles (correctness, simplicity, repo-rules):

- Reuse the `deep-review` run that the caller passed in, or the last run on this branch. Check
  that it is current with `check-stale.sh`, as the reference says. Do not review a second time.
- Start one `Agent` for each role with no results. Send them in one message. Give each agent
  the diff `git diff "$(git merge-base "$BASE" HEAD)"..HEAD` and its persona.
- The `repo-rules` check lists each rule that the diff selects, with an anchor for its evidence.

A check that cannot run is not `blocked` by default. Do the work that it needs. Use `blocked`
only when you cannot do that work, and tell the user why.

## 3. Write the artifact

Write `$TASK_DIR/post-implementation.md` like the example. Use `DIFF_HASH` for `diff_hash`.
Write the five checks, the findings, and one anchor with evidence for each `details_ref`.

Fix each open defect, commit the fix, and run the stage again from step 2. A fix changes the
diff, so the old hash is stale.

## 4. Verify

```bash
node .workflow/scripts/verify.mjs --base-ref "$BASE" --through post-implementation --enforcement blocking
```

Fix each violation with the table in the reference, and run it again. Stop after 3 rounds
with violations left, and ask the user. Commit the artifact when the verifier passes.

## Next

`Next: Skill(skill="workflow-finish")`
