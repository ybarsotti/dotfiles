# Query cost and the production check

A query that is fast on a dev database can be slow in production. The dev table holds 50 rows;
the production table holds 5 million, with a different distribution. This file defines how a
plan states the cost of its queries, and how a reviewer checks that cost against production.
`simple-plan`, `deep-plan` and the `senior-backend` reviewer of `deep-review` use it.

## 1. The query cost table — in the plan

Write one row per query the change adds or changes. An ORM call, a serializer that loads a
relation, and a loop that calls the database are queries too.

| Query | Where | Runs | Queries per request | Rows at production size | Index | Measured | Optimization |
|---|---|---|---|---|---|---|---|
| Orders of an account | `OrderService.list` | per request | 1 (was 1 + N) | ~2,000 per account | `order_account_id_created_idx` | production `EXPLAIN` | `select_related("customer")`; keyset pagination |

- **Runs**: per request, per row, per batch job, or per event.
- **Queries per request**: the count after the optimization. Write the count before it when
  the plan removes an N+1.
- **Rows at production size**: the rows the query reads, not only the rows it returns.
- **Index**: the index the query uses, or `none: sequential scan` with the reason it is safe.
- **Measured**: `production EXPLAIN`, `seeded dev EXPLAIN`, or `static`. A `static` row names the
  exact `EXPLAIN` command to run.
- **Optimization**: write it now. Do not wait for the production check to propose it.

Omit the table when the change adds and changes no query. Write `Query cost: no` and the reason.

## 2. When to ask for the production check

Ask when the cost depends on the production volume:

- an N+1, or a query inside a loop;
- a `WHERE`, `JOIN` or `ORDER BY` with no supporting index;
- a new query on a table that can hold more than 100,000 rows;
- `OFFSET` pagination, an aggregate, or a result set with no `LIMIT`;
- a new index, when the choice of columns and their order depends on the data.

Give the optimization first, in every case. The production check confirms the optimization or
changes it. It never replaces it.

The person who asks:

- **A planning session** asks the user directly, with `AskUserQuestion`.
- **A headless reviewer** cannot ask. It records the finding with its optimization in
  `--suggestion`. Then it records one `QUESTION` finding titled `prod-check: <query>`, with the
  exact read-only SQL of section 4 in `--description`. The `deep-review` orchestrator collects
  these findings and asks the user once.

The `deep-review` orchestrator handles the `prod-check:` findings before its fix round:

1. Ask the user once with `AskUserQuestion`.
2. On approval, run an `Agent` with the `senior-backend` persona. Give it the findings, the
   connection the user chose, and sections 3 to 6 of this file. It writes `prod-check.md` in
   the run folder.
3. Change the severity of each original finding from the result, then fix.
4. When the user declines, keep the static findings. List the `EXPLAIN` commands under
   `## Open findings`.

Ask once for all the queries of a run. Name each query, the table, and the SQL that will run.
The user chooses how to connect: a read replica, a read-only DSN in an environment variable, or
a command the project already has. The user can also decline. Then mark the rows `static`.

Production sizing. Read the database instance size, the connection pool size and the pool
timeout from the project's `CLAUDE.md`, `ARCHITECTURE.md` or `docs/`. When they are unknown,
add them to the same question. A query that reads many pages from disk holds a pool connection
and starves every other request. Judge its cost against the pool, not the query time alone.

## 3. Safety rules — read before you connect

- Get the approval of the user for each run. An approval in an earlier run does not carry over.
- Prefer a read replica to the primary database.
- Open a read-only session with a timeout. On Postgres:
  `PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=5000' psql "$DSN"`.
  On MySQL: `SET SESSION TRANSACTION READ ONLY; SET SESSION max_execution_time = 5000;`.
- Read the credentials from the environment or from the project's command. Never print them.
  Never write them to a file, a log or a report.
- Run only the statements of section 4. Never run `INSERT`, `UPDATE`, `DELETE`, DDL, `VACUUM`,
  `ANALYZE <table>`, or a change of settings. Never create an index in production. The index
  goes in a migration.
- Run `EXPLAIN ANALYZE` only on a `SELECT`, only on a replica, and only with the timeout.
  `EXPLAIN ANALYZE` executes the statement, so never run it on a write.
- Never select customer rows. Read counts, sizes, statistics and plans. Never copy a value of a
  customer column into a report. `pg_stats.most_common_vals` holds real values, so do not read it.

## 4. What to read in production

Postgres, for each table the query reads:

```sql
SELECT relname, reltuples::bigint AS estimated_rows,
       pg_size_pretty(pg_total_relation_size(oid)) AS total_size
FROM pg_class WHERE relname IN ('<table>');

SELECT indexname, indexdef FROM pg_indexes WHERE tablename = '<table>';

SELECT attname, n_distinct, null_frac, correlation
FROM pg_stats WHERE tablename = '<table>' AND attname IN ('<column>', ...);

SELECT seq_scan, idx_scan, n_live_tup FROM pg_stat_user_tables WHERE relname = '<table>';

EXPLAIN (FORMAT TEXT) <the query, with a realistic parameter>;
-- replica only:
EXPLAIN (ANALYZE, BUFFERS) <the same SELECT>;
```

Take a realistic parameter from the distribution, for example the account with the most orders.
Find it with an aggregate that returns a count and an id, never a customer value. When
`pg_stat_statements` is installed, read the `calls`, `mean_exec_time` and `rows` of the current
form of the query. On MySQL, read `information_schema.TABLES`, `SHOW INDEX`, and
`EXPLAIN FORMAT=TREE`.

## 5. Simulate the load

When production allows only `EXPLAIN` without `ANALYZE`, or no access at all, simulate it:

1. Take the row counts and the distribution from section 4. Without access, take them from the
   ticket, the user, or a stated assumption.
2. Seed the dev or test database to that size with the project's factories or `generate_series`.
   Copy the distribution: rows per foreign key, the null fraction, the distinct values.
3. Run `ANALYZE <table>` on the dev database, then `EXPLAIN (ANALYZE, BUFFERS)` for the query
   before and after the optimization.
4. When the optimization adds an index and `hypopg` is installed on dev, test the index as a
   hypothetical index first.

## 6. Report

For each query, give:

- the plan node that costs the most, quoted from the `EXPLAIN` output;
- the index that the query uses, or the sequential scan;
- the estimated rows and the actual rows, and the skew between them;
- the time before and after the optimization, and where it was measured;
- the `shared hit + read` buffers before and after. A warm cache hides cost. For example, and
  only as an illustration, not as sizing data: 800k buffers can run in 1 s on an idle replica
  and in 80 s on the primary under load;
- the queries per request, before and after;
- the verdict: the optimization holds, the optimization changes, or the query is safe as it is.

Update the query cost table of the plan with these values. In `deep-review`, the result changes
the severity of the original finding: up when production is worse than the static guess, down
when the query is safe at production size.
