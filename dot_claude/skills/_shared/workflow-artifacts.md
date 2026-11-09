# Workflow artifacts — schema reference

The workflow stage skills write these artifacts. The repository's verifier,
`.workflow/scripts/verify.mjs`, accepts or rejects them. The header comment of that script is
the source of truth. Read it when this file and the script disagree, and follow the script.

Read only the section of the stage you run.

## Where the artifacts live

Each task writes its artifacts in `.workflow/tasks/<branch>/`. A branch `feat/x` maps to
`.workflow/tasks/feat/x/`.

| Mode | Artifacts |
|---|---|
| fast | `workflow.md` |
| standard | `workflow.md`, `plan.md`, `post-plan.md`, `post-implementation.md`, `finish.md`, `decisions.md` |

## Shared commands

Run these from the repository root. They set the base ref, the task folder and the two hashes.

<!-- commands -->
```bash
BASE="${BASE_REF:-$(git symbolic-ref -q --short refs/remotes/origin/HEAD || echo main)}"
TASK_DIR=".workflow/tasks/$(git branch --show-current)"
DIFF_HASH=$(BASE_COMMIT="$(git merge-base "$BASE" HEAD)" node --input-type=module -e 'import { diffHash } from "./.workflow/scripts/verify.mjs"; console.log(diffHash({ root: ".", baseCommit: process.env.BASE_COMMIT }))')
if [ -f "$TASK_DIR/plan.md" ]; then PLAN_HASH="sha256:$(shasum -a 256 <"$TASK_DIR/plan.md" | cut -d' ' -f1)"; fi
```

- `DIFF_HASH` comes from the `diffHash` function of the verifier. Do not compute it by hand.
  Pass the base commit in the environment, because the verifier reads `process.argv[1]` when it
  loads.
- `diff_hash` covers the commits between the merge base and `HEAD`, without `.workflow/`.
  Commit the code first, then compute the hash. An uncommitted change is not in the hash.
- `plan_hash` covers the bytes of `plan.md`. Any later edit to `plan.md` makes `post-plan.md`
  stale.
- Do not set `base_commit` in `workflow.md`. The verifier then uses the merge base, and a
  rebase keeps the hash correct.

## Run the verifier

```bash
node .workflow/scripts/verify.mjs --base-ref "$BASE" --through <stage> --enforcement blocking
```

`<stage>` is `post-plan`, `post-implementation` or `finish`. Exit 0 is a pass. Exit 1 prints one
violation per line, as `CODE file: message`. Exit 2 is a usage, configuration or git error:
fix the command or the configuration, then run it again.

Fix each violation with the table below, then run the verifier again. Stop after 3 rounds with
violations left. Show them to the user and ask how to continue.

| Code | Fix |
|---|---|
| `MISSING_ARTIFACT` | Write the artifact. A missing `plan.md` means: copy the approved plan into the task folder. |
| `BAD_FRONTMATTER` | Make the frontmatter one JSON object between two `---` lines. |
| `MODE_MISMATCH` | Make `mode` equal the `choice` of the last decision with `id: "mode"`. |
| `MISSING_CHECK` | Add the check, with `result` `pass` or `findings`. `blocked` fails: do the work that the check needs. |
| `BAD_ANCHOR` | Add exactly one `<a id="..."></a>` with evidence text after it, for each `details_ref`. |
| `STALE_DIFF_HASH` | The code changed after the stage ran. Review the new commits, then write the new `DIFF_HASH`. |
| `STALE_PLAN_HASH` | `plan.md` changed after the review. Review the change, then write the new `PLAN_HASH`. |
| `OPEN_DEFECT` | Fix the defect and set `status: "fixed"`, or ask the user to accept it and set `status: "accepted"`. |
| `RULE_NOT_COVERED` | Review the change against the named rule. List it in the check's `rules[]`, with an anchor for its evidence. |
| `RULE_TEST_MISSING` | Add a test that contains the rule id, and list the test file in the rule's `tests`. |
| `BUSINESS_SKIP_REJECTED` | Set `business_rules` to `review`, and add the `business-rules` check. |
| `NOT_READY` | Set `ready_to_review: true` only when no other violation is left. |
| `PENDING_DECISION` | Ask the user with `AskUserQuestion`, write the answer in `summary`, and set `status: "decided"`. |

## Field rules

- A check is `{id, result, details_ref}`. `result` is `pass`, `findings` or `blocked`. A rules
  check also has `rules[]`, each `{id, details_ref}`.
- A finding is `{id, class, status, summary, ref?}`. `class` is `defect` or `note`. `status` is
  `open`, `fixed` or `accepted`. An open defect fails the verifier.
- A decision is `{id, summary, status}`. `status` is `pending` or `decided`. The mode decision
  has `id: "mode"` and `choice` (`fast` or `standard`).
- Each `details_ref` names one anchor `<a id="..."></a>` in the body of the same artifact. The
  anchor occurs once, and text follows it.
- An artifact can hold more checks than the stage requires. Each extra check needs an anchor too.
- The verifier selects each active rule whose `paths` match a changed file. A standard task
  lists each selected rule in `repo-rules`. A fast task lists it in the check of its kind:
  `technical-rules`, `implementation-rules` or `business-rules`.

## The three reviewer roles

The stages review with three roles: correctness, simplicity, repo-rules. Each role becomes one
check.

1. Reuse the results of a review that already ran on the same plan or diff. Do not run a second
   review for a role that has results.

   | Source | correctness | simplicity | repo-rules |
   |---|---|---|---|
   | `deep-plan` verdicts (`$RUN_DIR/verdict-<persona>-iter<N>.json`, last round) | architect, flow-mapper, qa, ticket-matcher | — | project-developer |
   | `simple-plan` Phase 3 | — | `ponytail:ponytail-review` | project fit |
   | `deep-review` run (`~/.claude/deep-review-runs/<RUN_ID>/`) | correctness | simplicity | project-fit |

   Before you reuse a `deep-review` run that this session did not just finish, run
   `~/.claude/skills/deep-review/scripts/check-stale.sh <run dir>`. Reuse it only on exit 0.
2. For each role with no results, start one `Agent`. Send all of them in one message, so they
   run in parallel. Give each agent the plan or the diff, and its persona:
   - correctness: `~/.claude/skills/deep-review/personas/correctness.md`;
   - simplicity: `~/.claude/skills/deep-review/personas/simplicity.md`;
   - repo-rules: `~/.claude/skills/deep-review/personas/project-fit.md`, plus every rule file
     with `status: active` in the folders that `.workflow/config.json` names. Tell it to
     report, for each rule whose `paths` match a changed file, whether the change keeps the
     rule's `assertion`.
3. Write each role's result as one check. Write each problem as a finding. A bug, a broken rule
   or a missing test is a `defect`. Anything else is a `note`.
4. Write the evidence under the check's anchor: the source (a file path, a run id or the agent
   role), and what the reviewer found.

## Examples

Each example is valid. `sha256:<diff_hash>` and `sha256:<plan_hash>` stand for the values of
`DIFF_HASH` and `PLAN_HASH`. `TR-001` is an active technical rule that the diff selects.

### Fast: `workflow.md`

`workflow-mode` writes the mode fields. `workflow-finish` adds the hash, the checks, the
findings and `ready_to_review`. With `"business_rules": "review"`, add a `business-rules`
check and drop `business_reason`.

<!-- example: fast-workflow.md -->
```markdown
---
{
  "stage": "workflow",
  "task": "feat/x",
  "ran_at": "2026-11-09T12:00:00Z",
  "mode": "fast",
  "decisions": [
    {"id": "mode", "summary": "Fast: a narrow change to one module. It touches no business behavior, permission, migration or integration.", "status": "decided", "choice": "fast"}
  ],
  "business_rules": "skip",
  "business_reason": "No active business rule matches the changed paths.",
  "diff_hash": "sha256:<diff_hash>",
  "verdict": "pass",
  "checks": [
    {"id": "technical-rules", "result": "pass", "details_ref": "technical-rules", "rules": [{"id": "TR-001", "details_ref": "tr-001"}]},
    {"id": "implementation-rules", "result": "pass", "details_ref": "implementation-rules", "rules": []},
    {"id": "tests", "result": "pass", "details_ref": "tests"},
    {"id": "correctness", "result": "pass", "details_ref": "correctness"},
    {"id": "simplicity", "result": "findings", "details_ref": "simplicity"}
  ],
  "findings": [
    {"id": "F1", "class": "note", "status": "accepted", "summary": "The helper could be inlined. The user kept it for the next task.", "ref": "simplicity"}
  ],
  "ready_to_review": true
}
---
# Workflow: feat/x

<a id="technical-rules"></a>
The repo-rules agent read every active technical rule. The diff selects TR-001.

<a id="tr-001"></a>
TR-001 holds: `src/app.js` keeps the documented interface.

<a id="implementation-rules"></a>
The diff selects no active implementation rule.

<a id="tests"></a>
`just test` passed: 42 tests, 0 failures.

<a id="correctness"></a>
The correctness agent found no defect.

<a id="simplicity"></a>
The simplicity agent found one note, F1.
```

### Standard: `workflow.md`

<!-- example: standard-workflow.md -->
```markdown
---
{
  "stage": "workflow",
  "task": "feat/x",
  "ran_at": "2026-11-09T12:00:00Z",
  "mode": "standard",
  "decisions": [
    {"id": "mode", "summary": "Standard: the change alters who can approve an order.", "status": "decided", "choice": "standard"}
  ]
}
---
# Workflow: feat/x

The user confirmed the standard mode.
```

### Standard: `post-plan.md`

<!-- example: standard-post-plan.md -->
```markdown
---
{
  "stage": "post-plan",
  "task": "feat/x",
  "ran_at": "2026-11-09T13:00:00Z",
  "plan_hash": "sha256:<plan_hash>",
  "verdict": "pass",
  "checks": [
    {"id": "correctness", "result": "findings", "details_ref": "correctness"},
    {"id": "simplicity", "result": "pass", "details_ref": "simplicity"},
    {"id": "repo-rules", "result": "pass", "details_ref": "repo-rules", "rules": [{"id": "TR-001", "details_ref": "tr-001"}]}
  ],
  "findings": [
    {"id": "P1", "class": "defect", "status": "fixed", "summary": "The plan did not cover an empty list. The plan now has a test for it.", "ref": "correctness"}
  ]
}
---
# Post-plan review: feat/x

<a id="correctness"></a>
Source: the deep-plan verdicts of round 2. The architect found P1. The plan now covers it.

<a id="simplicity"></a>
Source: a simplicity agent. It found nothing to delete.

<a id="repo-rules"></a>
Source: the project-developer verdict of round 2. The plan follows the repository rules.

<a id="tr-001"></a>
The plan keeps the interface of `src/app.js`, as TR-001 requires.
```

### Standard: `post-implementation.md`

<!-- example: standard-post-implementation.md -->
```markdown
---
{
  "stage": "post-implementation",
  "task": "feat/x",
  "ran_at": "2026-11-09T16:00:00Z",
  "diff_hash": "sha256:<diff_hash>",
  "verdict": "pass",
  "checks": [
    {"id": "tests", "result": "pass", "details_ref": "tests"},
    {"id": "runtime", "result": "pass", "details_ref": "runtime"},
    {"id": "correctness", "result": "pass", "details_ref": "correctness"},
    {"id": "simplicity", "result": "pass", "details_ref": "simplicity"},
    {"id": "repo-rules", "result": "pass", "details_ref": "repo-rules", "rules": [{"id": "TR-001", "details_ref": "tr-001"}]}
  ],
  "findings": []
}
---
# Post-implementation review: feat/x

<a id="tests"></a>
`just test` passed: 44 tests, 0 failures.

<a id="runtime"></a>
The qa-business agent ran the approval flow on the dev server. All 3 scenarios passed.

<a id="correctness"></a>
Source: deep-review run 20261109-1530. The correctness persona found no defect.

<a id="simplicity"></a>
Source: deep-review run 20261109-1530. The simplicity persona found no finding.

<a id="repo-rules"></a>
Source: deep-review run 20261109-1530. The project-fit persona found no finding.

<a id="tr-001"></a>
TR-001 holds: the diff keeps the interface of `src/app.js`.
```

### Standard: `finish.md`

<!-- example: standard-finish.md -->
```markdown
---
{
  "stage": "finish",
  "task": "feat/x",
  "ran_at": "2026-11-09T17:00:00Z",
  "diff_hash": "sha256:<diff_hash>",
  "verdict": "pass",
  "findings": [],
  "ready_to_review": true
}
---
# Finish: feat/x

Every earlier artifact passes the verifier. No defect is open and no decision is pending.
```

### Standard: `decisions.md`

<!-- example: standard-decisions.md -->
```markdown
---
{
  "stage": "decisions",
  "task": "feat/x",
  "ran_at": "2026-11-09T13:00:00Z",
  "decisions": [
    {"id": "D-001", "summary": "Keep the old endpoint for one release. The mobile app still calls it.", "status": "decided"}
  ]
}
---
# Decisions: feat/x

D-001: the user chose to keep the old endpoint for one release.
```
