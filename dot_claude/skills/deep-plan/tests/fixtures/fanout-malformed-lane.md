# Malformed-lane fanout fixture (malformed, on purpose)

Test-only fixture for `subplan-fanout.sh`'s failure-propagation path: a
declared `## Execution shape` with a truncated lane row must make the
parser fail, and `subplan-fanout.sh` must surface that failure instead of
silently falling back to legacy directory grouping.

## Affected files

- `src/widget.ts` — the widget

## Execution shape

- Mode: `parallel`
- Orchestrator lane: `orchestrator`
- Shared, committed pre-fanout and read-only afterwards: `justfile`
- Ownership syntax: exact repo-relative path, or a directory prefix ending in `/**`; multiple entries separated by `<br>`

| lane | scope | owns (path globs) | must-not-touch | agent | test_command | mock_command | depends_on |
|---|---|---|---|---|---|---|---|
| orchestrator | short row | `src/**` |
