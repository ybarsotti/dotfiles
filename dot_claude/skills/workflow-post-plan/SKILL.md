---
name: workflow-post-plan
description: Write the post-plan artifact of a standard workflow task in a repository that has `.workflow/config.json`. Use after the user approves a plan, when `simple-plan` or `deep-plan` hands over its review results, or when the user asks to record the plan review. Copies the plan, records the correctness, simplicity and repo-rules checks (reusing earlier review results), writes `post-plan.md` and `decisions.md`, and loops on the verifier until it passes.
---

# workflow-post-plan

This stage records the review of an approved plan. It does not implement anything.

## 1. Check the repository

If `.workflow/config.json` does not exist, say "This repository has no workflow:
`.workflow/config.json` is missing." and stop.

Run the shared commands of `~/.claude/skills/_shared/workflow-artifacts.md`. Read only its
sections "Shared commands", "Run the verifier", "Field rules", "The three reviewer roles" and
the examples of `post-plan.md` and `decisions.md`.

- `$TASK_DIR/workflow.md` is missing: run `Skill(skill="workflow-mode")` first, then continue.
- The mode is `fast`: this stage has no artifact. Say so, and go to the fast step of
  `workflow-mode`'s Next section.

## 2. Copy the plan

Copy the approved plan to `$TASK_DIR/plan.md`: `$PLAN_PATH` from `simple-plan`, or
`$RUN_DIR/plan.md` from `deep-plan`. Run the shared commands again to set `PLAN_HASH`. Do not
edit `plan.md` after this step. An edit makes `post-plan.md` stale.

## 3. Review the plan

Use the three reviewer roles: correctness, simplicity, repo-rules. Follow "The three reviewer
roles" in the reference.

- Reuse the review results that the caller passed in, or the last round of the planning
  pipeline. Do not review a role a second time.
- Start one `Agent` for each role with no results. Send them in one message. Give each agent
  `$TASK_DIR/plan.md` and its persona. Tell it to review the plan, not a diff.

## 4. Write the artifacts

1. Write `$TASK_DIR/post-plan.md` like the example. Use `PLAN_HASH` for `plan_hash`. Write the
   three checks, the findings, and one anchor with evidence for each `details_ref`.
2. Write `$TASK_DIR/decisions.md` like the example. List each decision of the plan and each open
   question. An answered item has `status: "decided"`. An open question has
   `status: "pending"`. `workflow-finish` resolves the pending items.
3. A finding that changes the plan: update the plan at its source, get the user's approval
   again, then go back to step 2.

## 5. Verify

```bash
node .workflow/scripts/verify.mjs --base-ref "$BASE" --through post-plan --enforcement blocking
```

Fix each violation with the table in the reference, and run it again. Stop after 3 rounds
with violations left, and ask the user. Commit the artifacts when the verifier passes.

## Next

Implement the plan. After the build and its review:
`Next: Skill(skill="workflow-post-implementation")`
