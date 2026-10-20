---
description: Inventory what a plan or a diff asks the team to own — complexity, maintenance, and the work that leaves the team
---

# /shed-light

Show what an implementation asks the team to maintain. Use it when a plan or a PR grew
machinery and somebody must decide whether the added work is worth it.

**Arguments:** `$ARGUMENTS`

```text
/shed-light [plan-path | diff-scope]
```

With no argument, the target is the current diff against the branch base.

## What you must do

Invoke the `shed-light` skill. The skill lives at `~/.claude/skills/shed-light/SKILL.md` and
holds the full contract: the inventory rules, the complexity ratings, the separate maintenance
estimate, and the external-work section.

This report carries no verdict. High complexity can be the right answer, so present the burden
and let the reader decide.
