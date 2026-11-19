# Checklist (orchestrator ticks after Phase 3)

Verify each and report the state to the user:

- [ ] `title-conventional` — title matches `^(feat|fix|refactor|perf|docs|test|chore)(\(.+\))?: .+`, ≤ 70 chars
- [ ] `mermaid-present` — body has a ```mermaid block, consistent with the changed domains
- [ ] `no-file-list` — no "Affected files"/"Files changed" section, no path inventory, no `+/-` counts
- [ ] `ticket-linked-or-n/a` — ticket linked, or an explicit `_no ticket_` when none exists
- [ ] `slack-linked-or-n/a` — relevant threads linked, or explicit `_none found_`
- [ ] `requirements-reconciled` — every requirement maps to implementation evidence and status
- [ ] `key-decisions-present` — important decisions and trade-offs are preserved
- [ ] `evidence-attached` — UI change ⇒ `## Evidence` carries a flow GIF/recording, before/after
      screenshots for changed screens, and a link to the QA report + its SHA; no UI change ⇒ the
      explicit `_no UI change — no visual evidence_`
- [ ] `permissions-tabled-or-n/a` — access change ⇒ `## Permissions` lists every role in the
      system, one column per changed action, a `file:line` or `denied by default` behind each
      cell, and the source the role names came from; no access change ⇒ section absent
- [ ] `blindspot-passed` — every claim in the body is READ, or rewritten to what was observed
- [ ] `assigned-to-me` — PR assignee includes `@me`
- [ ] `codex-review-applied` — codex reviewer ran and its fixes were applied (or `--no-codex` was set)

If any box other than `codex-review-applied` (when `--no-codex`) is unchecked, loop back to
the relevant phase before declaring done.
