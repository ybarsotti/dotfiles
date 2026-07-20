# Unescaped-pipe lane fixture (malformed, on purpose)

Test-only fixture (not consumed by Task 4's plan validators). The
`test_command` cell below contains a bare, unescaped `|` — this must shift
the row's remaining columns and be rejected loudly by `plan-to-json.sh`
rather than silently parsed with corrupted values.

## Execution shape

- Mode: `parallel`
- Orchestrator lane: `orchestrator`
- Shared, committed pre-fanout and read-only afterwards: `justfile`
- Ownership syntax: exact repo-relative path, or a directory prefix ending in `/**`; multiple entries separated by `<br>`

| lane | scope | owns (path globs) | must-not-touch | agent | test_command | mock_command | depends_on |
|---|---|---|---|---|---|---|---|
| orchestrator | bad row: bare pipe | `src/**` | `none` | `opus high` | `foo | grep bar` | `none` | `none` |
