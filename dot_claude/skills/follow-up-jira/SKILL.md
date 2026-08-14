---
name: follow-up-jira
description: >
  Use when the user hands off a Jira ticket that is fixed and deployed, and now
  wants the reporter's verdict handled without watching it themselves. Covers any
  standing watch on a ticket's comments — poll it, background-monitor it, follow
  up until validated, check whether the reporter replied — and any reaction to
  the verdict that arrives: close/resolve the ticket on approval, or on rejection
  investigate the reported symptom, fix the root cause, test, update the pull
  request, and move the ticket back to investigation. Trigger on requests to
  follow up, watch, monitor, poll, check back on, or track a ticket key until the
  reporter approves or rejects, on reports that the reporter says it is still
  broken, and right after the user tells a reporter something is ready to
  validate. Do not use to read, summarize, or draft replies on a ticket, or to
  start fresh work on one.
---

# Follow up a Jira ticket until the reporter confirms it

This skill starts **after** the work is done. The change is implemented,
deployed, and the user has already told the reporter to validate it. The ticket
sits in the review status. Nothing is left except the reporter's answer, which
arrives as a comment on the ticket, at an unknown hour.

The skill exists so that answer never sits unread, and so a rejection starts an
investigation immediately instead of at the next standup.

## The one hard rule

**The user is the only audience.** Write every message into this session and
nowhere else.

Do not post a Jira comment. Do not send a Slack message. Do not email. Do not
reply to the reporter in any channel, not even to say "we are on it". The user
owns all outward communication on this ticket and sends it by hand.

The only write this skill makes outside the session is a **status transition**
on the ticket, plus the code and pull request changes that a rejection triggers.

Never call `addCommentToJiraIssue`, `editJiraIssue`, or any Slack send tool.

## Step 1 — Resolve the ticket and the baseline

Find the ticket key in this order. Stop at the first hit.

1. The argument passed to the skill.
2. The ticket already under discussion in this session.
3. The current git branch name, when it carries a `[A-Z]{2,}-\d+` pattern.

Ask the user when none of these resolves, and stop until they answer. Watching
the wrong ticket is silent and wastes hours.

Then read the ticket once with `getJiraIssue` and record the baseline:

- The **reporter** account id. Only this person's comments count as feedback.
- The **current status**. It should be the review status. Warn the user in one
  line when it is not, and ask whether to continue — a ticket that is not in
  review usually means the validation message was never sent.
- The **watermark**: the timestamp of the newest existing comment. Everything at
  or before it is history, not feedback.
- The **pull request** and branch, when the session or the ticket links one.
- The **acceptance check**: the command or manual step that proves the ticket's
  central behaviour still works. A rejection fix has to re-run this.

Save all of it to `~/.claude/follow-up-jira/<TICKET>.json`. Context gets
summarized on long watches, and a tick that forgets its watermark re-reads old
comments as new ones.

Report the baseline to the user in three lines at most, then start the loop.

## Step 2 — The 30 minute loop

Call `ScheduleWakeup` with `delaySeconds: 1800` and `prompt: "/follow-up-jira
<TICKET>"`. Each wake-up re-enters this skill.

On every tick, read the ticket comments and keep only those that the reporter
wrote after the watermark.

**No new reporter comment** is the common case. Schedule the next wake-up with
`noop: true` and write nothing to the user. A watch that reports "still nothing"
every 30 minutes trains the user to ignore it.

**New reporter comments** move to Step 3. Advance the watermark first, so a
crash mid-investigation does not replay the same comment.

Ignore comments from anyone who is not the reporter. Mention one in a single
line only when it reports the same defect, because that changes how urgent the
rejection is.

## Step 3 — Classify the feedback

Read every new comment together and decide one of three outcomes. When two
comments disagree, the newest one wins.

**Approval** — the reporter states the behaviour now works. "Confirmed", "works
on production now", "tested, all good", "thanks, you can close it".

**Rejection** — the reporter reports that the original problem persists, or that
the change broke something else.

**Ambiguous** — everything else. A question. A scheduling note ("I will test
tomorrow"). A request for behaviour the ticket never covered. Feedback about a
different ticket.

Bias hard towards ambiguous. Ambiguous costs the user one line to read. The
other two branches are expensive: a wrong resolve reopens the ticket and burns
the reporter's trust, and a wrong investigation burns a full cycle on a comment
that only asked when the deploy landed.

### Approval

Move the ticket to the resolved status. Do not guess the transition name —
project workflows differ:

```
mcp__atlassian__getTransitionsForJiraIssue(cloudId, issueIdOrKey=<TICKET>)
```

Match a transition named for resolution, case-insensitively. Stop and ask the
user when nothing matches or when two candidates fit.

Then apply it, tell the user the ticket is closed and quote the approving
comment, and end the loop with `ScheduleWakeup({stop: true})`.

Add no reaction and no thank-you comment. The Jira MCP exposes no reaction tool,
and a comment would break the one hard rule.

### Ambiguous

Change nothing on the ticket. Summarize the comment to the user in one or two
lines, say what you think it needs, and schedule the next wake-up with
`noop: false`. The loop continues.

Route a request for new behaviour here too, and suggest a separate ticket. This
ticket's scope closed when the reporter validated it.

### Rejection

Go to Step 4.

## Step 4 — Investigate and fix a rejection

Move the ticket back to the investigation status, using the same enumerate-then-
match approach as above. Do this first, so the board reflects reality while the
work runs.

Then work in this order:

**1. State the defect in one sentence.** Quote the reporter's own words for what
they saw. A defect restated in your own words drifts from what they reported.

**2. Confirm the cause with a subagent.** Dispatch an exploring subagent with
the original requirement, the reported symptom, and the diff that shipped. Ask
it for the mechanism and a `file:line`, not for a fix.

A second reader matters here because you carry the assumptions that produced the
defect. The subagent does not. Do not take its answer at face value — verify the
mechanism in the code yourself before you edit. A confident wrong root cause
produces a confident wrong fix, and the reporter validates twice.

**3. Fix the root cause, not the reported path.** Grep every caller of the
function you are about to change. One guard in a shared function is a smaller
diff than a guard in each caller, and it fixes the siblings the reporter has not
hit yet.

**4. Prove both directions.** Two checks, and both must pass:

- A new check that fails before the fix and passes after it. This proves the
  reported defect is gone.
- The ticket's original acceptance check. This proves the central behaviour the
  ticket was opened for still works.

The second check is the one that is easy to skip and expensive to skip. A fix
that satisfies the reporter's latest comment and quietly undoes the ticket's
main outcome reads as progress and is a regression.

Write the smallest runnable check when none exists. Never report a fix on
reasoning alone.

**5. Update the pull request.** Commit and push to the existing branch when that
pull request is still open. Open a fresh branch and pull request off the default
branch when the original already merged, and link it to the ticket.

## Step 5 — Report, then hand back

End the run with a session message that holds exactly this, and nothing else:

1. **Feedback** — what the reporter reported, quoted.
2. **Root cause** — the mechanism, with `file:line`.
3. **Fix** — what changed, in one or two sentences.
4. **Evidence** — the commands run and their real result. Say plainly when
   something failed or was skipped.
5. **Pull request** — the link and its state.
6. **How to revalidate by hand** — the exact steps and the environment the user
   needs to walk through before messaging the reporter again.

Send a `PushNotification` alongside it. The user is away by definition; a
rejection that waits for them to look at the terminal loses the time this skill
was built to save.

Then stop the loop with `ScheduleWakeup({stop: true})`.

The loop stops on purpose. The ticket now needs a deploy and a new validation
message, and the user sends both by hand. Tell them to run
`/follow-up-jira <TICKET>` again once they have — a fresh run resets the
watermark and watches for the next answer.
