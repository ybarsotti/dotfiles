---
description: Classify every claim in a finished artifact as READ or INFERRED, then verify or downgrade each INFERRED claim
---

# /blindspot

Run a blindspot pass over a finished artifact: a plan, a review report, a PR body, a status
update. Self-review compares what you wrote against what you read. This pass finds the claims
that rest on what you never read.

**Arguments:** `$ARGUMENTS`

```text
/blindspot [path-or-artifact]
```

With no argument, the artifact is the one this session just produced.

## What you must do

Invoke the `blindspot` skill. Do not improvise the pass. The skill lives at
`~/.claude/skills/blindspot/SKILL.md` and holds the full contract: the READ and INFERRED
definitions, the procedure, and the surfaces that go unread.

Run it even when a review already came back clean. A clean review shares the same unopened
files as the author, which is the reason this pass exists.
