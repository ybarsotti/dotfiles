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
