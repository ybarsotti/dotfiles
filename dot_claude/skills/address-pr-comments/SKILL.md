---
name: address-pr-comments
description: Fix the valid review comments on an open pull request and nothing else. Use when a review requests changes, when a new actionable comment arrives during the pr-description watch, or when the user asks to address, answer or resolve PR comments. Treats each comment as a claim to verify, fixes only valid in-scope ones, replies in every thread, resolves the addressed threads and reruns the tests. Not for a first review of a PR.
---

# Address PR comments

A review comment is a claim, not an order. Verify it against the code before you change
anything. Fix what is valid and inside the PR's scope. Answer every thread with the fix or the
reason for no fix.

The request to run this skill includes the replies and the thread resolutions on the PR. Do
them without asking again, unless the user limits the task to analysis or a draft. This skill
gives no permission to merge, deploy or open new issues.

## 1. Establish the boundary

1. Read the PR title and body, the linked task, and the approved plan when one exists.
2. State the PR's intended outcome and its exclusions in two lines.
3. Fetch the review threads with their ids and their resolved state. A flat comment list does
   not show resolution. Use GraphQL:
   ```bash
   gh api graphql -F owner=<owner> -F repo=<repo> -F n=<n> -f query='
     query($owner:String!,$repo:String!,$n:Int!){repository(owner:$owner,name:$repo){
       pullRequest(number:$n){reviewThreads(first:100){nodes{id isResolved isOutdated
         comments(first:20){nodes{databaseId author{login} path line body}}}}}}}'
   ```
4. Read the review bodies and the top-level comments too: `gh pr view <n> --json reviews,comments`.
5. Skip the threads that are already resolved, and the ids the caller already handled.

## 2. Triage every comment

Read the current code, its callers and the requirement before you decide. Merge duplicate
comments that report one cause.

| Disposition | Action |
| --- | --- |
| Valid and in scope | Make the smallest complete fix, including the callers it affects, and a test that fails without it. |
| Already fixed or outdated | Confirm it on the current head. Cite the line or the commit. |
| Invalid | Give the concrete counter-evidence. Leave the code unchanged. |
| Valid but out of scope | Record it as a follow-up for the user. Keep it out of this PR. |
| Needs a product decision | Ask the user. Continue the work that does not depend on it. |

A comment is valid when it names a concrete failure: wrong behaviour, a security or data
integrity defect, a missed requirement, or a broken written repository rule. A severity label
or a reviewer's insistence does not make a comment valid.

**No scope creep.** An optional abstraction, an unrelated cleanup, a cosmetic change or a
speculative guard is not a reason to grow the PR. When a valid fix cannot fit the PR's
intended outcome, tell the user. Do not expand the scope in silence.

## 3. Fix and verify

1. Apply each accepted fix. Follow the existing architecture and conventions.
2. Read the resulting diff. Remove anything the fix did not need.
3. Rerun the tests that cover the changed code, then the checks the repository requires.
4. A pending, skipped or absent check is not a passing check.
5. Do not weaken a test, a lint rule or a threshold to close a comment.
6. Commit and push through the repository's normal route.

## 4. Reply and resolve

Reply only after the fix is on the remote head and the tests pass.

1. Reply in each thread with the disposition, the fix commit SHA or the line, and the
   verification:
   ```bash
   gh api repos/<owner>/<repo>/pulls/<n>/comments/<comment-id>/replies -f body='<reply>'
   ```
2. Resolve each thread you fixed, and each thread you declined with evidence:
   ```bash
   gh api graphql -F id=<thread-id> -f query='
     mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}'
   ```
3. Leave a thread open when the defect remains or the decision waits on the user.
4. Fetch the threads again. Verify that every addressed thread shows `isResolved: true`.
5. When a permission error blocks a resolution, report the exact error. Do not claim the
   thread is closed.

## 5. Report

Give the user one line per comment: the link, the disposition, and the commit or the reason.
Then list the follow-ups, the questions that wait on the user, the test results, and the
threads still open.
