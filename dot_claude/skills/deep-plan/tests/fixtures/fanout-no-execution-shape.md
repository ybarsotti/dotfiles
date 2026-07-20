# No-execution-shape fanout fixture (legacy plan)

Test-only fixture for `subplan-fanout.sh`'s legacy fallback path: a plan
with no `## Execution shape` section at all must still fan out via the
original top-level-directory grouping, with no error.

## Affected files

- `src/widget.ts` — the widget
- `docs/widget.md` — the doc
