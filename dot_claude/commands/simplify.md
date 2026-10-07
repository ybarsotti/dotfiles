---
description: Light cleanup pass — dead code, guard clauses, nesting, obvious duplicates, clearer names
---

# /simplify

Run a light cleanup pass over the code that just changed. It makes code simpler and more
readable; it does not restructure. For code smells, architecture or DRY across a codebase, use
`/refactor` instead.

**Arguments:** `$ARGUMENTS`

```text
/simplify [path-or-scope]
```

## What you must do

Invoke the `simplify` skill. Do not clean up inline. The skill lives at
`~/.claude/skills/simplify/SKILL.md` and holds the full contract: what the pass changes, what
it must leave alone, and the verification it runs after each change.

`deep-review` Phase 5 invokes this same skill by default, so a change that went through a
review has already had this pass.
