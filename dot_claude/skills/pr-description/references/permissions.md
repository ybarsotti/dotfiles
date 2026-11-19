# Permissions section (Phase 2.6)

**A reviewer cannot approve an access change they have to infer.** Decide whether this diff
changes who may do what: a new or renamed role, a changed permission or scope, a new guarded
endpoint or action, an altered policy, decorator, guard, middleware, `can?` rule or row-level
rule. Changed paths naming `permission`, `role`, `policy`, `scope`, `ability`, `guard`,
`authoriz`, or a migration on a roles or permissions table are the signal. When it is
ambiguous, assume it does.

If it does not, leave the section out. This section appears only when access changed.

If it does, the body carries a `## Permissions` table: **every role in the system as a row**,
and **one column per action this PR adds or changes**. The reader must see, without opening
the code, which roles gained an ability and which stayed out.

| Role | Create record | Delete record | Enforced at |
| --- | --- | --- | --- |
| `owner` | ✅ | ✅ | `policies/record.py:34` |
| `admin` | ✅ | ✅ | `policies/record.py:34` |
| `member` | ✅ | ❌ | `policies/record.py:41` |
| `viewer` | ❌ | ❌ | denied by default |

Rules for the table:

1. **Read the roles from the project, never from memory.** Take them from the role enum,
   the roles table, the seed or the fixture that defines them, and cite that source under the
   table. A role you invented is worse than no table.
2. **Every role appears**, including the ones this PR does not touch. A role missing from the
   table reads as an oversight, and the reviewer cannot tell which it was.
3. **`Enforced at` names a `file:line`** for each allowed cell, or says `denied by default`
   when the role falls through with no rule. A `✅` with nothing behind it is the bug this
   table exists to catch.
4. **Mark a role whose access this PR changes.** Add a `Change` column with `+ gained`,
   `- lost` or `unchanged` when the PR alters existing access rather than adding a new action.
5. **Say what is not covered.** When an action is guarded in the UI but not on the server, or
   the reverse, write it under the table as a one-line warning. Do not let the ✅ imply both.

Derive the cells from the code in the diff, not from the ticket's intention. When the two
disagree, write the table from the code and flag the disagreement — that gap is the most
valuable thing this section can surface.
