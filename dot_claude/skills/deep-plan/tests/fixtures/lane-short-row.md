# Short lane row fixture (malformed, on purpose)

Test-only fixture (not consumed by Task 4's plan validators). The lane row
below is truncated to 3 columns instead of the required 8 — this must be
rejected loudly by `plan-to-json.sh` rather than silently defaulting the
missing columns to empty strings.

## Execution shape

- Mode: `parallel`
- Orchestrator lane: `orchestrator`
- Shared, committed pre-fanout and read-only afterwards: `justfile`
- Ownership syntax: exact repo-relative path, or a directory prefix ending in `/**`; multiple entries separated by `<br>`

| lane | scope | owns (path globs) | must-not-touch | agent | test_command | mock_command | depends_on |
|---|---|---|---|---|---|---|---|
| orchestrator | short row | `src/**` |
