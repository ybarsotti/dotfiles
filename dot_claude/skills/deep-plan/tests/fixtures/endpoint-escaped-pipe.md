# Escaped-pipe endpoint fixture

Test-only fixture. Exercises an API contract endpoint table cell containing
an escaped pipe (`` \| ``), verifying that `plan-to-json.sh` round-trips it
to a literal `|` in the emitted `response_shape` instead of treating it as
a column delimiter.

## API contract

- Contract version: `1.0.0`
- Materialized contract: `contract.ts`
- Contract kind: `typescript`
- Contract validation command: `true`

| endpoint | method | full_path | status_codes | request_shape | response_shape |
|---|---|---|---|---|---|
| get-widget | GET | /widgets/:id | 200,404 | none | `string \| number` |
