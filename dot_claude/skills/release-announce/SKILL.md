---
name: release-announce
description: Use when the user asks for a release message, release notes, an announcement for a version that shipped, "what do I tell the team", a changelog or GitHub release body, or wants each ticket reporter told that their ticket shipped, or types /release-announce. Reads a tag or a commit range, resolves each commit to its pull request and its linked tickets (GitHub issues, Jira or Linear keys), and drafts a team announcement in the user's own voice, one comment per ticket, and a changelog body. Returns drafts only. Never posts and never comments.
---

# Release notes

Draft three texts for a release: (a) the team announcement, (b) one comment per ticket, and
(c) the changelog or GitHub release body. Return every draft in the chat, each in its own code
block, for the user to copy. **Never post to a chat tool, never comment on a ticket, and never
edit a release.**

**Arguments:** a tag (`v1.4.0`, `web-v1.4.0`), a range (`v1.3.0..v1.4.0`), or nothing for the
newest release tag. Optionally a language: `pt` or `en`.

## Voice

The user writes these posts himself. Match his voice. Do not improve it.

- Short. A greeting, one line that says what shipped, the ticket list, done.
- Plain words. The readers are the people who use the product, not engineers.
- Say what a person can now do differently, not what the code does. Do not write service
  names, table names, framework words, "refactor", "endpoint", "migration" or "resolver".
- One line per ticket: `<KEY> – <the ticket summary, as written>`.
- Add an indented sub-line under a ticket only when the reader must act, or would otherwise be
  surprised. Put the @-mention of the person who must act on that line. Never mention a person
  only to inform them.
- No headings, no bold, no bullet characters, no emoji, no hype. Blank lines separate blocks.
- Do not mention commits, pipelines, tests or how the release was built.
- Write in the language that the user asks for. When the user names none, use the language of
  the user's earlier release posts if you have them, else English, and say which one you used.

The pattern:

```
Hi team!

Just shipped v1.4.0 including:

PROJ-101 – Export invoices as CSV
PROJ-104 – Require a reason when an order is cancelled
Existing draft orders need a reason before you can cancel them @<name>

Attaching a demo below
```

In Portuguese, the same shape: `Oi time!`, then `Acabei de publicar a v1.4.0 com:`.

## Steps

1. **Find the range.** Use the tag or the range that the user gives. Otherwise take the newest
   release tag. For a tag, the start is the previous tag with the same prefix:

   ```bash
   git fetch --tags --quiet
   TAG=$(git describe --tags --abbrev=0 --match "${PREFIX}v[0-9]*" --exclude '*-rc*' origin/HEAD)
   PREV=$(git describe --tags --abbrev=0 --match "${PREFIX}v[0-9]*" --exclude '*-rc*' "$TAG^")
   ```

   When `origin/HEAD` is missing, run `git remote set-head origin --auto` first. `PREFIX` is
   empty for `vX.Y.Z` tags and `<app>-` for per-app tags. For a per-app tag, limit
   every `git log` below to the app folder with `-- <app path>`.

2. **List the commits.** `git log --format='%h %s' "$PREV..$TAG"`. When the repository has a
   `release-notes` recipe (`just release-notes <app> <from> <to>`), read its grouped output too.

3. **Resolve each commit to a PR.** Take the number from `(#123)` in a squash subject, or ask
   GitHub:

   ```bash
   gh api "repos/{owner}/{repo}/commits/<sha>/pulls" --jq '.[].number'
   gh pr view <n> --json number,title,body,author,url,headRefName,closingIssuesReferences
   ```

4. **Resolve each PR to its tickets.**
   - GitHub issues: `closingIssuesReferences`, and `#123` or `Fixes #123` in the body.
   - Jira or Linear keys: match `[A-Z]{2,}-\d+` in the PR title, body, branch name and commit
     messages. The pattern also matches `UTF-8`, `SHA-256` or `CVE-2025`. Keep a key only when
     the tracker resolves it.
   - Read each ticket with the tool that is available: an Atlassian tool (for example
     `getJiraIssue` with the fields `summary`, `status` and `reporter`), a Linear tool, or
     `gh issue view <n> --json title,author,state`. Copy the summary **verbatim**. The team
     knows the tickets by these titles.
   - Without a tracker tool, list the keys as unverified and write no summary for them.

5. **Drop what the readers cannot see.** A commit with no ticket that is internal (tooling,
   tests, refactoring, CI, developer docs) stays out of draft (a). When such a change is
   visible to the readers, write it as a plain line with no key.

6. **Find what needs a person.** For each ticket, ask: must someone do something, redo
   something, or expect something to look different? Read the PR body (post-release steps,
   breaking changes, data changes) and the ticket reporter. That gives the sub-line and its
   @-mention.

7. **Draft (a), the team announcement**, in the voice above, ready to paste into a chat tool.
   Ask whether a ticket from an earlier release that was never announced should go in too.

8. **Draft (b), one comment per ticket** in draft (a), labelled with the ticket key. A change
   with no ticket gets no comment. Keep it to three lines or fewer:

   ```
   Hi @<reporter> – shipped in v1.4.0.
   You can now export invoices as CSV from the invoice list.
   To check: open an invoice list and choose Export > CSV. Could you confirm?
   ```

   Line 2 says what shipped, in the reader's words. Line 3 says how to verify it, only where
   the reporter can see it. When the release does not close the ticket (a phase shipped, a part
   did not), add one sentence that says exactly what did not ship.

9. **Draft (c), the changelog or GitHub release body.** When a release tool already wrote the
   `CHANGELOG.md` section for this version, reuse it. Otherwise group by type: Breaking changes,
   Features, Fixes, Performance. Write one line per change with its PR link and ticket key.
   Leave out `chore`, `ci`, `test`, `style`, `build` and `docs` unless a reader would notice the
   change.

10. **List what you were unsure about**, under the drafts: a ticket that you could not resolve,
    a mention that you guessed, a caveat that you left out, a ticket that may not be fully done.

11. **Optional: the Plannotator Inbox.** When the user asks for it, or works away from the
    chat, send the three drafts as finished work by the rules of
    `~/.claude/skills/_shared/inbox.md`. Use the thread name `release <tag>`. The Inbox is a
    channel to the user, so this is not a post.

## Never

- Post to a chat tool, comment on a ticket, or transition a ticket. These are drafts. The user
  decides what reaches the readers.
- Invent a ticket key, or attach a summary that you did not read from the tracker.
- Include an internal-only change because its diff is large.
- Explain the implementation. When a line makes sense only to a developer, cut it.
- Say that a ticket is done when only part of it shipped.
