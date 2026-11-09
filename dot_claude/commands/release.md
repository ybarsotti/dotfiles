---
description: Cut a release of the current repository — detect release-please or tags, review what ships, run the checks, tag only after you confirm, then draft the notes
argument-hint: [app] [auto|patch|minor|major|X.Y.Z]
---

# /release

Cut a release of the current repository. It works with a release-please Release PR, with
another release tool, or with plain semver tags per app.

**Arguments:** `$ARGUMENTS`

```text
/release [app] [auto|patch|minor|major|X.Y.Z]
```

With no argument, the release covers every app that changed, and the bump is `auto`.

## What you must do

Invoke the `release` skill. The skill lives at `~/.claude/skills/release/SKILL.md` and holds
the full procedure: the mechanism detection, the review of what ships, the version rules, the
checks, the confirmation and the hand-off to `release-notes`.

The command authorizes the review only. Merging a Release PR, pushing a tag and publishing a
release each wait for your confirmation of that exact version. It never force-pushes and never
deploys.
