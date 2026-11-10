# After plan approval — the build chain

The approval of the plan is the go signal. Do not stop at a handoff and do not wait for the
user to type the next command. Run the steps below in order, unattended, until the PR is open
and the report is delivered. `deep-plan`, `simple-plan`, `jira-workflow`, `implement` and
`deep-execute` all use this chain. This file is the only full description of it; other files point here.

Stop early only in these cases:

- The user said to stop at the plan, for example "only plan" or "não implementa".
- A decision changes a requirement, a business rule, a contract or the scope. Ask the user.
- A loop below reaches its round limit with failures left. Report them and ask.

The ultracode question of option C is not a stop case. The planning skill asks it once, at
plan approval, before this chain starts (`plan-routing.md`). This chain never asks it.

## 0. Hold the chain open

1. Open `/goal` unless a goal is already active. State the objective as the finished result:
   "built, reviewed, QA green, PR open, report delivered". Name the plan path in it.
2. Record each decision you make on the way in `$RUN_DIR/decisions.md`: the decision, the
   rejected alternative, and the reason. The report reads this file.

## Parallel agents run in Orca

Start each agent that runs beside this session as an Orca worker: the QA agents, the
`ui-designer`, a Codex implementer. An Orca worker is a full interactive session, so it has the
`Artifact` tool that `claude -p` lacks. Load the guide once with `orca skills get
orchestration`, then start the worker:

```bash
orca orchestration worker-start --worktree current --agent claude --json \
  --spec "Read ~/.claude/agents/qa-ui.md and follow it. <the inputs it lists>"
```

- Start every independent worker, then end your turn. Orca wakes you with each `worker_done`.
- Add `--keep-open` when the user will talk to the worker, as with the `ui-designer`.
- A worker that must run without permission prompts starts in its own terminal:
  `orca terminal create --worktree current --command "claude --dangerously-skip-permissions" --json`,
  then `orca orchestration worker-start --task <task_id> --terminal <handle>`.
- Outside an Orca workspace (`orca worktree current` fails), use the `Agent` tool with the same
  agent name. Never use `claude -p` for an agent that needs the `Artifact` tool.

## 1. Build

The executor comes from the last section of `~/.claude/skills/_shared/plan-routing.md`:
A is `/deep-execute`, B is the `implement` skill, C is `Workflow`, D is Codex. The planning
skill picks it before this chain starts. Run option C only when `$RUN_DIR/decisions.md`
records the user's ultracode opt-in, or the session runs at ultracode effort. Without either,
run option B.

The session that planned orchestrates. It does not write feature code. Build with strict
TDD. Record each departure from the plan as a `D-NNN` row under the plan's `## Deviations`.

**Review each part when it is done.** A part is a task in option B, a round in option A, a
stage, or a slice in option D. In option C, the workflow's adversarial reviewer replaces this
per-part review (`plan-routing.md`, "How option C runs"). Before the next part starts, run
`/deep-review default --scope <commit before the part>..HEAD`. Fix every CRITICAL, HIGH and
MEDIUM finding through the agent that wrote the part, then commit. The next part builds on reviewed
code.

`/deep-execute` runs steps 2 to 9 itself. For options B, C and D, run them from this session.

**Under `/deep-execute`, the lane that owns the code applies every fix.** Run each
`/deep-review` with `--no-fix --no-simplify`, so the review only reports. Send each fix to
the owning lane with `reply.sh RUN_DIR LANE "<finding, file, line, fix>"`, gate the fix with
`round-gate.sh`, then commit. A file that no lane owns goes to a fresh implementer agent.

## 2. Review

1. Run `/deep-review default` over the whole change. Each part had its own review; this pass
   checks how the parts fit together. Its Phase 4.5 fixes every CRITICAL, HIGH and MEDIUM finding and
   re-runs the panel, for 2 fix rounds at most.
2. A separate agent applies the fixes. The reviewer never fixes its own finding. Under
   `/deep-execute`, that agent is the owning lane (section 1).
3. Fix a MEDIUM finding when the fix is local and does not change behavior. Record every
   finding you do not fix, with the reason, under `## Open findings`.

## 3. Is the environment ready?

Find the app URL in this order: the `base_url` of `qa-plan.yaml`, the QA steps of the plan,
the project `CLAUDE.md`. Check it with `curl -sf -o /dev/null <url>`.

- It answers: run steps 4 and 5.
- It does not answer: skip steps 4 and 5. Record "QA skipped: <url> did not answer" in the
  report. Do not start or rebuild an environment the user did not ask for.

## 4. UI parity — the `qa-ui` agent

Run this step when the plan has a UI design pass. Dispatch the `qa-ui` agent with:

- the plan path, and the `Canvas:` URL of the UI design pass when the plan has one;
- the app URL and the routes of the changed screens;
- the output folder `$RUN_DIR/qa/ui/`.

Run it as an Orca worker. It reads the canvas with the `Artifact` tool. The agent screenshots each new or changed element at desktop width and at 390 px. When a
canvas exists, it compares each element with its artboard. The implementation must match the
artboard: layout, spacing, copy, color, type, states and icons. The agent returns one row per
difference.

## 5. Business rules and end to end — the `qa-business` agent

Dispatch the `qa-business` agent with the plan path, `qa-plan.yaml` when it exists, the app
URL, and the output folder `$RUN_DIR/qa/business/`. It runs each requirement and each
`Cover now` edge case through the real UI. It checks every side effect: the database row, the
API response, the email, the queue. It records a video of each flow.

Run steps 4 and 5 in parallel. They touch different things.

## 6. Fix and re-test

1. A separate fixer agent fixes every difference from step 4 and every failure from step 5.
   The QA agents never fix code.
2. Re-run only the QA agent that found the problem, on the fixed commit.
3. Stop after 3 rounds. Report what is still open and ask the user. The chain runs unattended,
   so ask each decision as an Inbox question when the Inbox exists, else `AskUserQuestion`
   (`~/.claude/skills/_shared/inbox.md`).

When a fix changes code that the review saw, run `/deep-review` once more on the fix.

## 7. Open the PR

0. When `.workflow/config.json` exists, run `Skill(skill="workflow-post-implementation")` with the step 2 review and the QA results as evidence. It chains to `workflow-finish`.
1. Freeze the commit SHA. Every result in the report names this SHA.
2. Run `/pr --no-watch`. It attaches the screenshots and the video with `gh --attach`, opens
   the PR and returns. The watch starts in step 9, after the report.
3. When the change adds or alters a feature a person uses, record a narrated demo with the
   `video-demo` skill after the PR is open. Attach it with `gh pr edit <n> --attach` under a
   `## Demo` heading, and link it in the report. Skip it for a refactor, a lone migration or
   an internal API, and say why.

## 8. Deliver the report

`/deep-execute` builds its report with `build-run-report.sh`. That script reads the lane
records of a run (`manifest.json`, `events.jsonl`, `decision.sh` output), which options B, C
and D do not write. For options B, C and D, write `$RUN_DIR/report/index.html` yourself. It is one self-contained page with these sections:

1. **Summary** — what was built, the ticket, the PR link, the frozen SHA.
2. **Requirements** — the ticket coverage table, each row with its proof.
3. **Decisions** — each row of `decisions.md` and each `D-NNN` deviation.
4. **Review** — the findings, what was fixed, and the open findings.
5. **Tests** — the test commands and their results, and each QA scenario with its verdict.
6. **UI parity** — for each element, the artboard and the implementation side by side.
7. **Evidence** — the screenshots and the videos.
8. **Open items** — everything still open, with the reason.

Copy each image and video into `$RUN_DIR/report/media/` and link it by a relative path.
Then run `open "$RUN_DIR/report/index.html"` and give the user the absolute path.

Send the finished-work summary to the Inbox thread of the ticket or branch: the PR in `pulls`,
the QA screenshots in the body, and the report and videos in `attachments` (`_shared/inbox.md`).

## 9. Watch the PR

Start the watch of Phase 5 of `~/.claude/skills/pr-description/SKILL.md` on the PR number:
review comments go to `address-pr-comments`, failing checks to systematic debugging, until the
PR merges or closes. Under `/deep-execute`, a fix still goes to the owning lane while its loop
runs.
