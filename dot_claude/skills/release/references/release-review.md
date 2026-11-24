# Release review

The detailed review of what a release ships. Section 3 of `SKILL.md` runs it when the user
asks for it, or when the release carries a migration, a money change or an auth change.
Every command here reads. Nothing merges, tags, deploys or writes to a database.

```bash
git fetch origin --tags --quiet
LAST=$(git describe --tags --abbrev=0 --match "${PREFIX}v[0-9]*" --exclude '*-*' "origin/$BRANCH")
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
```

## 1. What ships, and who approved it

```bash
git log --format='%h %an %s' "$LAST..origin/$BRANCH" -- "$APP_PATH"
gh api "repos/$REPO/pulls/<n>/reviews" --jq '[.[]
  | select(.state == "APPROVED" and .user.type == "User") | .user.login] | unique'
```

`user.type == "User"` drops bot reviewers. A comment from an AI reviewer is not an
approval. Write one row per PR:

| PR | Area | Change (one line) | Author | Human approvals |
|---|---|---|---|---|

Done when every commit in the range has a row and the report states "N of M PRs merged with
no human approval".

## 2. Migrations

List the migration files in the range, then read each one and classify it:

| Class | Looks like | Reversible |
|---|---|---|
| Additive schema | a new table, a nullable or defaulted column, a new index | yes |
| Permission grant | a data migration that adds a permission to roles | only with a real reverse |
| Trigger | a database trigger created in raw SQL | check the reverse SQL |
| Destructive schema | drop, rename, or a column made NOT NULL | no: the previous build may not run on it |
| Data rewrite | a data migration that updates or deletes existing rows | no |

Mark as irreversible every migration with an empty reverse and every data rewrite.
Redeploying the old build leaves the rewritten rows as they are.

Size every data rewrite on production. Write a `COUNT` that mirrors the filter and the
change condition of the forward code: the rows it touches, and per column the rows whose
value actually changes. Run it on a read replica inside `BEGIN READ ONLY; ... ROLLBACK;`,
through the access path that the project documents. Never print a connection string or a
password. Without replica access, report the rewrite as unmeasured: that is a risk in itself.
The PR text rarely shows the real scale.

## 3. Business risk

Read the diff of every PR that touches:

- money: price, discount, approval routing, tax, refunds, invoices, commissions;
- permissions, authentication, sessions, and the shape of a token one service sends another;
- data that crosses tenants or organizations.

Name what changes for whom, with a number when one exists: orders, accounts or requests
affected.

When parts of the system deploy separately (backend and frontend, API and worker), old and
new versions run side by side for a window. For each contract change, answer both: does the
old side accept the new side's requests, and does the new side accept the old side's? Name
the window and who gets an error in it. Sessions minted before the deploy stay live.

## 4. CI on every release commit

```bash
gh run list --commit <sha> --json name,status,conclusion
```

Run it for each commit in the range, not only the last one. Report each failure and the
result on the release commit.

## 5. What runs in each environment now

Read the build that each environment runs, from the deploy tool the project documents (an
image tag, a deploy record, a health endpoint that reports the commit). Map it to git:

```bash
git describe --tags --exact-match <sha>     # a release, or empty for a branch build
git rev-list --count <sha>..origin/$BRANCH  # commits on the branch that this build lacks
git merge-base --is-ancestor <release sha> <sha> && echo included
```

A branch build does not exercise the release. Done when the report gives each environment's
commit and says, for the release commits, "ran in staging" or "CI only".

## 6. Post-release steps

From the PR bodies, collect every management command, backfill, flag change and check, in
the order to run them, each with its PR.

## 7. Risk score

Score the release on six dimensions, 1 (low) to 5 (high), each with one line tied to a PR:

| Dimension | 1 | 5 |
|---|---|---|
| Blast radius | one internal user | every user and feature |
| Reversibility | plain revert | irreversible: data rewrite, sent email, payment |
| Data risk | no writes | schema change, data rewrite, money data |
| Integration risk | no contract changes | public API, payment or identity provider |
| Novelty | known pattern in this code | new to the codebase |
| Test coverage | every changed path tested | untested paths |

The band follows the highest score, not the average: any 5 is HIGH, any 4 is MEDIUM.
A HIGH band needs a watch plan (the metric, the dashboard, how long) and a rollback plan.
Recommend a database snapshot before a deploy that ships a data rewrite or a destructive
schema change.

## Report

Present it in chat, once. Later updates report only what changed.

1. **What ships:** the rows of check 1.
2. **Risks, highest first:** irreversible data rewrites and money changes, then auth and
   permission changes, then PRs with no human approval, then commits that ran only in CI.
   Each names its PR and a number.
3. **Score:** the six scores, the band, the watch plan and the rollback plan.
4. **Release steps:** the snapshot when needed, the deploy order, and the check 6 steps.
