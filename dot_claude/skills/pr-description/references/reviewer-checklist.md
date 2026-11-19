# Reviewer checklist (Phase 2)

The reviewer validates, returning concrete fixes:
- **Title is Conventional Commit?** valid `type`, optional scope, ≤ 70 chars.
- **Mermaid present and consistent** with the domains in `git diff --name-only main...HEAD`? (no phantom components, no missing major area)
- **NO file list / no counts** anywhere in the body, except the 3 to 5 risk links of
  `## How to review`?
- **How to review** present: a reading order by area, the riskiest places with one line
  each, and what to skim?
- **Ticket present** (linked or an explicit `_no ticket_`)?
- **Slack threads present** (linked when supplied, or explicit `_none found_`)?
- **Requirements matrix complete** and statuses supported by diff/test evidence?
- **Key decisions preserved** from plan/ticket context?
- **Stages and deferred edge cases** — a staged plan's stage table is present with the next
  stage to review; every `Out of scope` edge case ID from the plan is listed?
- **Evidence present** — when the diff touches UI, an `## Evidence` section with a flow
  GIF/recording (and before/after for changed screens) or an honest local-asset list; when it
  does not, the explicit `_no UI change — no visual evidence_`?
- **Evidence by requirement** — one row per `evidence.tsv` line, each result naming the SHA
  it ran at, that SHA equal to HEAD, and no `pass` without a proof that ran?
- Body is objective about *what we solve* (not a changelog of the diff)?
