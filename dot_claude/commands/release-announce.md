---
description: Draft the release announcement, one comment per ticket, and the changelog body from a tag or a range — drafts only, never posts
argument-hint: [tag | from..to] [pt|en]
---

# /release-announce

Draft the texts for a release that shipped: the team announcement in your own voice, one
comment per ticket that the release addressed, and the changelog or GitHub release body.

**Arguments:** `$ARGUMENTS`

```text
/release-announce [tag | from..to] [pt|en]
```

With no argument, the release is the newest release tag.

## What you must do

Invoke the `release-announce` skill. The skill lives at `~/.claude/skills/release-announce/SKILL.md`
and holds the full contract: the voice, the commit-to-PR-to-ticket steps, the three drafts and
the list of uncertain points.

Return drafts only. Never post to a chat tool and never comment on a ticket.
