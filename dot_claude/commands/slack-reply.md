---
description: Read a Slack thread, check the facts in the project, and draft a reply for the user to approve before it is sent
argument-hint: <thread URL | channel name> [what to answer]
---

# /slack-reply

Draft a reply to a Slack thread. Every fact in the draft comes from the thread, the code or a
source you read. Nothing is sent without the user's approval.

**Arguments:** `$ARGUMENTS`

## 1. Find the thread

- A thread URL gives the channel ID and the parent timestamp (`p1700000000123456` is
  `1700000000.123456`). Read it with `slack_read_thread`.
- A channel name: find it with `slack_search_channels`, read the latest messages with
  `slack_read_channel`, and pick the thread that asks the user something. When more than one
  fits, list them and ask which one.
- Read the whole thread, the files and links it shares (`slack_read_file`, `slack_read_canvas`),
  and the profile of each person in it (`slack_read_user_profile`) for their role.

## 2. Find who the user is

Read the user's own profile with `slack_read_user_profile` and no user ID. Use that ID to
see which messages are theirs and what they already said. Never hard-code a user ID.

## 3. Check the facts in the project

Find the project the thread is about: the repository, the service, the ticket or the PR that
it names. Read before you answer:

- the code: the function, the endpoint, the model or the screen in question. Use the
  project's code tools first (GitNexus, Graphify, Serena) when they exist, then Grep and Read;
- the history: `git log` of the files, and the PRs (`gh pr view`, `gh pr list --search`);
- the ticket and its comments, when the thread names one (Jira or Linear);
- the deploy state, when the question is "is it live?": the release tag or the deployed
  commit, from the release skill or the project's deploy docs;
- earlier answers on the topic: `slack_search_public_and_private` for the same terms.

When the answer needs a number (rows affected, users, a count), get it from a read-only
query or the code, and say where it came from. When you cannot check a claim, say so in the
draft. Never guess a behavior that the code can answer.

## 4. Draft the reply

- Answer the question first, in the language and tone of the thread.
- Keep it under 500 characters unless the question needs more. Use Slack `mrkdwn`: bullets
  for lists, code blocks for code, a link to the PR, the file at a commit, or the ticket.
- Write for the reader. A non-developer gets what changes for them, not the internals.
- Name what is still open and who owns it.

Never put in the draft: secrets, tokens, connection strings, internal hostnames, customer
personal data, or a quote from a private channel or DM that the thread's channel cannot see.
When the answer needs any of these, say so and ask how to proceed.

## 5. Ask, then send

Show the draft and the sources you checked. Ask: send, edit, or save as a Slack draft.

- **Send:** `slack_send_message` with `thread_ts` set to the parent timestamp.
- **Draft:** `slack_send_message_draft`, so the user sends it from Slack.

Send nothing without an explicit "send". After sending, give the message link.
