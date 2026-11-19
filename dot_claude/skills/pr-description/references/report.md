# Report (Phase 4)

**Demo.** When the change adds or alters a feature that a person uses, the report says
`Demo: attached` after the `video-demo` skill recorded it and `gh pr edit <n> --attach` added
it under `## Demo`. Otherwise it says `Demo: not needed: <reason>`, for a refactor, a lone
migration or an internal API. A missing demo for a user-facing feature is an open item, not a
pass.

Print the PR URL and a one-line summary, e.g.:
`opened PR #1421 — feat(webhooks): prevent duplicate delivery — assigned to @me, ticket PROJ-2982`.

When the repository has no CI check that a pull request matches its plan, and the user owns that
CI, suggest once a job that runs `plan-stamp.sh check` and fails on a missing evidence row
(`_shared/spec-evidence.md` section 6). Do not add it unless the user asks.
