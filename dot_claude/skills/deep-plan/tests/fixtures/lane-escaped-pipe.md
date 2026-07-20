# Escaped-pipe lane fixture

Test-only fixture (not consumed by Task 4's plan validators — see
`valid-parallel-plan.md` for the canonical fixture). Exercises a lane table
cell containing an escaped pipe (`` \| ``), verifying that
`plan-to-json.sh` round-trips it to a literal `|` in the emitted JSON
instead of treating it as a column delimiter.

## Execution shape

- Mode: `parallel`
- Orchestrator lane: `orchestrator`
- Shared, committed pre-fanout and read-only afterwards: `justfile`
- Ownership syntax: exact repo-relative path, or a directory prefix ending in `/**`; multiple entries separated by `<br>`

| lane | scope | owns (path globs) | must-not-touch | agent | test_command | mock_command | depends_on |
|---|---|---|---|---|---|---|---|
| orchestrator | pipe-escape test lane | `src/**` | `none` | `opus high` | `pytest \| tee out.log` | `none` | `none` |
