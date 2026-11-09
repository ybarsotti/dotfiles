<!-- Hand-written. docs/skills-map.mjs copies this file into docs/skills-map.md. -->

The table lists flows that two or more files defined at the first review. Each row gives the status and the change, or the reason to keep the overlap. Three shared docs now hold the single copy of a flow: `_shared/after-approval.md` (the build chain), `_shared/plan-routing.md` (which pipeline plans and which executor builds) and `_shared/ticket-start.md` (claim a Jira issue and move it to in progress). The `implement` skill is the single-session executor (option B).

| # | Overlap | Status | Change or reason |
|---|---|---|---|
| 1 | The build chain after plan approval had five descriptions. | Resolved | `after-approval.md` is the only full copy. `commands/deep-plan.md`, `commands/simple-plan.md`, `skills/simple-plan/SKILL.md` Phase 5 and `skills/deep-plan/SKILL.md` Phase 3.5 point to it in one line. |
| 2 | Three files said that `deep-plan` stops at the approved plan. | Resolved | `commands/deep-plan.md`, `skills/deep-plan/README.md` and `skills/jira-workflow/SKILL.md` now say that it builds through to the PR unless the user said to stop. The README handoff with `/simplify` x2 and `/qa-test-plan` is replaced by a pointer. |
| 3 | `jira-workflow` had its own serial build, review and QA path. | Resolved | `jira-workflow` section 3 now delegates to the chain and keeps only the Jira steps: debugging for a bug ticket, verification before `/pr`, the commit body, the `/pr` arguments, the ticket comment and the notifications. |
| 4 | `simplify` could run three times on one change. | Resolved | The `/simplify` x2 step left `jira-workflow`. The deep-review Phase 5 pass is the only one. |
| 5 | QA execution had four routes. | Resolved | One route: the chain starts the `qa-ui` and `qa-business` agents. `qa-business` runs `qa-test-plan --phase execute` when a `qa-plan.yaml` exists, else `agent-browser`. Its optional `qa-testing` route and the `qa-testing` step of `jira-workflow` are gone. `commands/deep-execute.md` now matches the skill. |
| 6 | QA had three skills and three commands for one workflow. | Resolved | The `qa-plan` and `qa-execute` skills are deleted. Their trigger phrases and the `--plan PATH` rule moved into the `qa-test-plan` description and arguments. The three commands stay. |
| 7 | Every command repeats its skill. | Kept, reduced | The commands reach Codex, so they stay. The restated chain and QA text left `deep-plan`, `simple-plan` and `deep-execute` commands, which caused rows 2 and 5. The phase overviews and argument grammars stay as user documentation. |
| 8 | Three skills chose the pipeline or the mode with their own criteria. | Resolved | The criteria and the question rules are in `plan-routing.md`. `deep-plan` Phase 0.4, `simple-plan` Phase 0.5 and `workflow-mode` section 2 point to it and keep their own question. |
| 9 | Two places replied to PR review threads. | Resolved | The pr-description watch step 3 is deleted. `address-pr-comments` replies and resolves. |
| 10 | Two skills opened a pull request. | Resolved | `follow-up-jira` opens a new PR with `Skill(skill="pr-description")`. |
| 11 | Two watch loops. | Kept | They watch different sources: PR review and CI, and the reporter's ticket comment after deploy. |
| 12 | Two copies of the Jira status transition. | Resolved, one kept | The start transition of `jira-workflow` moved to `ticket-start.md`, which `deep-plan` and `simple-plan` also read. `follow-up-jira` keeps its own transitions, because they move the issue to done or back to investigation, not to in progress. |
| 13 | Two run reports. | Kept | `build-run-report.sh` reads the lane records of a `deep-execute` run (`manifest.json`, `events.jsonl`, `decision.sh` output). Options B, C and D do not write them. `after-approval.md` section 8 states this reason. |
| 14 | Four checks for over-engineering. | Kept | They run at different stages: plan upkeep (`shed-light`), plan review (`ponytail-review`), diff review and cleanup (`simplify`). In the diff review, `simplicity` flags local constructs and `code-judo` looks for a different shape of the whole change. |
| 15 | The demo video ran only in one pipeline. | Resolved | The `video-demo` step moved into `after-approval.md` section 7, so every pipeline runs it. |
| 16 | Two screenshot annotators. | Kept | The descriptions split the use: QA evidence and stakeholder images. |
| 17 | The name `plan` had two meanings. | Resolved | The journal skills `log`, `plan` and `retro` are deleted, with the journal system. |
