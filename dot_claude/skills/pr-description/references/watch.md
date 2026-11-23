# Watch steps (Phase 5)

1. **Poll every 5 minutes** with the `Monitor` tool while CI runs and bots review. Do not
   poll in a foreground loop. Read:
   ```bash
   gh pr view <n> --json state,reviewDecision,reviews,comments,statusCheckRollup,mergeable
   gh api repos/<owner>/<repo>/pulls/<n>/comments   # inline review comments
   ```
   Keep the ids you already handled in `$RUN_DIR/handled-comments.txt`.
2. **A `CHANGES_REQUESTED` review or any new comment** from a human or a bot: run
   `Skill(skill="address-pr-comments")`. It verifies each claim, fixes only the valid ones in
   scope, reruns the tests, then replies in and resolves each thread. Do not reply here.
   Every feedback you handle ends with a reply and a resolved thread: a fix gets its commit
   SHA, a declined comment gets the reason and the evidence, a question gets the answer. Only
   a thread that waits on a decision of the user stays open. After each round, check that no
   other thread is open:
   `~/.claude/skills/pr-approved/scripts/pr-approved.sh state <n> | jq .open_threads`.
3. **A failing check** goes through `superpowers:systematic-debugging`. Do not patch blindly.
4. **Ask the user first** when a comment changes scope, a requirement or a contract, or when
   two reviewers disagree.
5. After each push, rerun Phase 0.5 proofs and update `## Evidence by requirement` if a
   result changed.
6. **A merge conflict** (`mergeable: CONFLICTING`): rebase on the base branch, rerun the
   tests, and push. Ask the user first when the conflict touches logic that another PR changed.

**Two stages.** Human reviewers answer hours later, so a quiet CI does not end the watch.

- *Active*: the 5-minute `Monitor` poll above. It ends when CI is green and one full poll
  after your last push brings no new comment. Report what you fixed, what you declined and
  why, and what waits on the user.
- *Long*: then run `Skill(skill="loop", args="<the watch prompt>")` with no interval, so the
  loop paces itself with `ScheduleWakeup` at 1200 to 1800 seconds. The watch prompt names the
  PR URL, `handled-comments.txt`, and steps 1 to 6. A new comment, a `CHANGES_REQUESTED`
  review, a red check or a conflict starts the active stage again.

When the PR is approved and green, and when a review needs the user, send it to the Inbox
thread of the ticket or branch, with the PR in `pulls` (`~/.claude/skills/_shared/inbox.md`).
Without the Inbox, send a `PushNotification`. A `CHANGES_REQUESTED` that `address-pr-comments`
cannot resolve alone becomes an Inbox question.
Stop the loop when the PR merges or closes. The loop lives in this session: when the session
ends, the watch ends. Say so in the final report.
