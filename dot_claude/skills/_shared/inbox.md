# The Plannotator Inbox — when a long run talks to the user

The Inbox is a non-blocking channel to the user. You send a message and keep working. The
user answers when they can. This file is the only rule set for it; skills point here.
`plannotator inbox --help` gives the full tool reference.

## Is it available?

- In Claude Code, the Inbox exists when the `plannotator_inbox` tool is listed
  (`mcp__plannotator__plannotator_inbox`, maybe deferred: load it with tool search).
- In Codex, use the CLI when `command -v plannotator` succeeds: the stdio server is
  `plannotator inbox mcp`.
- When neither exists, use the fallback: `AskUserQuestion` for a decision, and
  `PushNotification` for status.

## Use the Inbox for

- **A decision that blocks only part of the work.** Other work goes on, for example the other
  lanes of a parallel run. Write a `:::question` block with a `Recommended:` line and a
  `Holds up: <what waits>` line. Add `Stopped: <why>` only when nothing can go on.
- **A blocker only the user can clear**, such as a merge, a sign-in or a deploy approval. Write
  one `:::action` block.
- **Finished long work:** a run report, a PR ready to merge, QA results. Put each screenshot in
  the body as `![alt](path)` where you write about it. Put the report and the videos in
  `attachments`. Pass the PR in `pulls` on the first message about it.
- **Status the user wants while away:** a PR approved and green, a review that needs them.

Use one thread per work stream. Name it with `thread` after the run, the ticket or the
branch, for example `PROJ-123` or `deep-execute run-20261109-1412`. Reuse the same name on
each message of that stream.

## Do not use the Inbox for

- A decision that stops all work now while the user is in the chat. Use `AskUserQuestion`.
- The planning grill and the brainstorm. They are a conversation. Keep them in the chat.
- An approval gate. The Plannotator plan review stays the gate for a plan.

A decision that you put in the Inbox stays there. Never ask it again in the chat with
`AskUserQuestion`. When the user comes back to the chat, tell them what waits, with the
thread link.

## Questions during a build chain

After the plan is approved, a question never stops the run. Send it to the Inbox, keep the
recommended answer as the working answer, and go on.

1. **Ground the recommendation, in this order:**
   1. the current rule: what the code or the data does today, with `file:line` or the query;
   2. the documentation: the ticket, the plan, the project docs, an earlier decision;
   3. when neither decides it: two or three options, each with its cost, and your pick.

   Write the source on the `Recommended:` line, for example
   `Recommended: keep today's rule (orders/service.py:88)`.
2. **Batch.** Put every question that comes up before your next send in one message, one
   `:::question` block each. Use one thread per run, named after the ticket or the branch.
3. **Go on with the recommended answer.** Record it in `decisions.md` as
   `pending: <thread link>`. Build it so that another answer is a small change.
4. **The PR opens with the questions still open.** `/ship-it` lists each pending decision in
   the PR body under `## Decisions waiting for confirmation`, with its thread link.
5. **When the answer comes**, compare it with the working answer. The same answer: mark the
   row of `decisions.md` confirmed. Another answer: change the code, run the tests, push, and
   update the PR body.

Stop the run only when no answer is safe to build on: a destructive migration, money, access
or data shared across tenants. Then mark the step with `workflow.sh block` and wait.

## Replies

A reply arrives in the session by itself when the session is idle. Its first line is
`Plannotator Inbox: <title> (<reply id>)`. End your turn instead of waiting for it.

1. Route the answer to the place that waits for it. For a lane, run
   `reply.sh RUN_DIR LANE "<answer>"`.
2. Confirm with `send_message`, `reply_to` set to the reply id.
3. Resolve the thread (`resolve_message`) only when no question, action item or open work is
   left in it.

## Content

Never put a secret, a token or customer data in a message or an attachment. The Inbox is
local to this machine, but the user can share an attachment.
