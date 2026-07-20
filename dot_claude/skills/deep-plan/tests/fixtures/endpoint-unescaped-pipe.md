# Unescaped-pipe endpoint fixture (malformed, on purpose)

Test-only fixture (not consumed by Task 4's plan validators). The
`response_shape` cell below contains a bare, unescaped `|` — an ordinary
TypeScript union, e.g. `string | number` — which must shift the row's
remaining columns and be rejected loudly by `plan-to-json.sh` rather than
silently truncated to `string`.

## API contract

- Contract version: `1.0.0`
- Materialized contract: `contract.ts`
- Contract kind: `typescript`
- Contract validation command: `true`

| endpoint | method | full_path | status_codes | request_shape | response_shape |
|---|---|---|---|---|---|
| get-widget | GET | /widgets/:id | 200,404 | none | `string | number` |
