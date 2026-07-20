# Typo Heading Fixture

### Execution shape

- Mode: `parallel`
- Orchestrator lane: `orchestrator`

| lane | scope | owns (path globs) | must-not-touch | agent | test_command | mock_command | depends_on |
|---|---|---|---|---|---|---|---|
| orchestrator | test lane | `justfile` | `none` | `orchestrator` | `tests/o.sh` | `none` | `none` |

## Affected files

- `justfile` — test
