# Phase 3 reviewer details

This file belongs to `simple-plan`. `SKILL.md` names the step that needs it.

Run it whenever the plan adds or changes a table, a column, an index, a migration, or a query
— including an ORM call or a serializer that loads a relation. Skip it otherwise and record
that you skipped it.

Point it at the plan, not at a diff, and tell it to answer two questions:

1. **Does the structure make sense?** Not "is it valid" — whether the shape matches what the
   data is. Judge the column types, the nullability, the keys and constraints, whether a JSON
   column holds fields the code will query by, whether the normalisation fits how the data is
   written and read, and whether the table has a growth and retention story. Its schema pass
   lists what to look for; constraint rule 13 governs the migration count.
2. **Will the queries hold at real size?** The plan's new reads, judged against the indexes
   that will exist after the migration: a query with no supporting index, an N+1 the plan sets
   up, an unbounded result set, `OFFSET` pagination on a table that grows. When a dev database
   is reachable, it reconstructs the SQL and runs `EXPLAIN (ANALYZE)` on a seeded table rather
   than guessing; when it is not, it says so and gives the exact `EXPLAIN` to run. It checks
   the section 6b table, and it names each query that needs the production check of
   `~/.claude/skills/_shared/query-check.md`. You ask the user for that check, run it, and
   update the table.

A finding here is cheap now and expensive later: a wrong column type ships as a migration, and
a missing index ships as an outage. The plan states the final schema, the indexes and the
migration count before implementation starts.

Give the project-fit reviewer `$PLAN_PATH`, `$RUN_DIR/context.md`, and
`~/.claude/skills/simple-plan/references/constraints.md`. Tell it to reject the plan when any constraint rule is broken,
and to quote the rule number.

Both reviewers check test coverage against constraint rule 10. For every row of the TDD
plan, the reviewer confirms that the mock target is the outermost call to an external
service. The reviewer rejects a row that mocks a service, repository, dispatcher, client, or
model method of this project, and names the outermost call to mock instead. Example finding:
"TDD row 3 mocks `VendorInvoiceLinkDispatcher` (rule 10). Use the real dispatcher and mock
`deliver_invoice_link_task.delay`."

Apply the findings. Re-run the reviewers. **Stop after three rounds.** Record any finding you
did not apply, with the reason, in a `## Open findings` section at the end of the plan.
