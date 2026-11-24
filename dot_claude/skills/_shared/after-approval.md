# After plan approval — the build chain

The approval of the plan is the go signal. Do not stop at a handoff and do not wait for the
user to type the next command. Run the steps below in order, unattended, until the PR is open
and the report is delivered. `deep-plan`, `simple-plan`, `jira-workflow`, `implement` and
`deep-execute` all use this chain. This file is the only full description of it; other files point here.

Stop early only in these cases:

- The user said not to build, for example "only plan", "plan only", "do not implement",
  "não implementa" or "só o plano".

A request to approve the plan is not a stop. "Stop at the plan for my approval", "wait for my
approval" and "I want to review the plan first" ask for the Plannotator gate, which every plan
has. When the gate approves, the chain starts. When you cannot tell whether the user wants the
build, ask one question at the approval: build now, or stop at the plan. Never close the run
on a guess.
- A decision is never a stop. The orchestrator takes the decision with the least impact,
  records it, sends it to the Inbox for review, and goes on (`_shared/inbox.md`, "Decisions
  during a build chain").
- A loop below reaches its round limit with failures left. Report them and ask.

The ultracode question of option C is not a stop case. The planning skill asks it once, at
plan approval, before this chain starts (`plan-routing.md`). This chain never asks it.

## 0. Hold the chain open

1. Open `/goal` unless a goal is already active. State the objective as the finished result:
   "built, reviewed, QA green, PR open, report delivered". Name the plan path in it.
2. Record each decision you make on the way in `$RUN_DIR/decisions.md`: the decision, the
   rejected alternative, and the reason. The report reads this file.
3. Keep the step file `$RUN_DIR/chain.md` with `~/.claude/skills/_shared/workflow.sh`. The
   planning skill creates it at its start, with the planning steps and the chain steps of
   `_shared/workflows/chain.steps`. When `/implement` starts without a planning run, create it:
   `workflow.sh init "$RUN_DIR/chain.md" implement --plan <plan>`.
4. Add one build row per task of the plan, in order:
   `workflow.sh add "$RUN_DIR/chain.md" build.<n> "<task>" --after build`.
5. Mark each step when it ends, with its evidence:
   - `workflow.sh done <file> <id> "<path, URL, or command and result>"`;
   - `workflow.sh skip <file> <id> "<reason>"` when the step does not apply;
   - `workflow.sh wait <file> <id> "<worker>"` before you end a turn to wait for a worker;
   - `workflow.sh block <file> <id> "<question>"` before you ask the user.
6. At the end of each task and each step, run `workflow.sh status <file>`. Tell the user in one
   short block what is done, what is next, and what is left.

**An instruction of the user is a step.** When the user says "before X, do Y" (validate with
Codex, show me first, run it against staging), add Y as a row before X at once:
`workflow.sh add <file> <id> "<Y, in the user's words>" --after <the step before X>`. Do not
start X while that row is open. Its evidence is what Y produces, not proof that a tool ran.

**Evidence is the output of the check.** A step is done when its evidence shows the check
itself: the test output, the diff, the report, the images. "The tool could read the files" is
not the evidence of a review. A step whose id starts with `visual` or `qa-ui` needs images:
`workflow.sh done` refuses it without an existing image file or a folder that holds images.

The Stop hook `~/.claude/hooks/workflow-gate.sh` blocks the end of a turn while a step is
`todo`. The `review` step cannot be skipped after code was built. When the user stops the run,
run `workflow.sh close <file> "<reason>"`. When the user then asks for the build, run
`workflow.sh reopen <file> "<reason>"` and start the chain at its first open step.

## Parallel agents run in Orca

Start each agent that runs beside this session as an Orca worker: the QA agents, the
`ui-designer`, a Codex implementer. An Orca worker is a full interactive session, so it has the
`Artifact` tool that `claude -p` lacks. Load the guide once with `orca skills get
orchestration`, then start the worker:

```bash
WT="id:$(orca worktree current --json | jq -r '.result.worktree.id')"
orca orchestration worker-start --worktree "$WT" --agent claude --model sonnet --json \
  --spec "Read ~/.claude/agents/qa-ui.md and follow it. <the inputs it lists>"
```

QA and UI analysis run on a mid-tier model, never on the top tier. Start the `qa-ui` and
`qa-business` workers with `--model sonnet`. A Codex QA worker uses `gpt-6.1-terra`, never
Opus, Sol or Astra. The build and the plan keep their own models.

- Start every independent worker, then end your turn. Orca wakes you with each `worker_done`.
- Add `--keep-open` when the user will talk to the worker, as with the `ui-designer`.
- A worker that must run without permission prompts starts in its own terminal:
  `orca terminal create --worktree "$WT" --command "claude --dangerously-skip-permissions" --json`,
  then `orca orchestration worker-start --task <task_id> --terminal <handle>`.
- Close the tab of each worker when its work is settled. Orca closes the tab of a worker that
  `worker-start` opened about 2 minutes after `worker_done`. It never closes a terminal that
  you created first, nor a `--keep-open` worker. Close those yourself with
  `orca terminal close --terminal <handle> --tab --json`: after `worker_done`, after a
  failure, and when the user is done with a `--keep-open` worker. A finished run leaves no
  worker tab open (`_shared/orca-workers.md` step 8).
- Outside an Orca workspace (`orca worktree current` fails), use the `Agent` tool with the same
  agent name. Never use `claude -p` for an agent that needs the `Artifact` tool.

**The repository's own workflow comes first.** When the repository defines one, it owns each
stage it covers, and this chain runs only the steps it lacks (`_shared/repo-workflow.md`).

## 1. Build

The executor comes from the last section of `~/.claude/skills/_shared/plan-routing.md`:
A is `/deep-execute`, B is the `implement` skill, C is `Workflow`, D is Codex. The planning
skill picks it before this chain starts. Run option C only when `$RUN_DIR/decisions.md`
records the user's ultracode opt-in, or the session runs at ultracode effort. Without either,
run option B.

The session that planned orchestrates. It does not write feature code. Build with strict
TDD. Record each departure from the plan as a `D-NNN` row under the plan's `## Deviations`.

**Review the whole change once, in step 2.** Do not run `/deep-review` after each part (a task
in option B, a round in option A, a stage, or a slice in option D). Each part passes its own
tests and gates before the next part starts. In option C, the workflow's adversarial reviewer
still runs as `plan-routing.md` describes ("How option C runs").

`/deep-execute` runs steps 2 to 8 itself. For options B, C and D, run them from this session.
Under every option, the final review of step 2 runs over the whole change: `/deep-review`, or
the code review stage of the repository workflow. No executor skips it.

**Under `/deep-execute`, the lane that owns the code applies every fix.** Run the
`/deep-review` with `--no-fix --no-simplify`, so the review only reports. Send each fix to
the owning lane with `reply.sh RUN_DIR LANE "<finding, file, line, fix>"`, gate the fix with
`round-gate.sh`, then commit. A file that no lane owns goes to a fresh implementer worker
(`orca-workers.md`).

## 2. Review

1. When the repository workflow has a code review stage, run it and skip this step
   (`_shared/repo-workflow.md`). Otherwise run `/deep-review default` over the whole change, with its full process: every phase, the
   fix rounds and the simplify pass. Each part had its own review; this pass checks how the
   parts fit together. Its Phase 4.5 fixes every CRITICAL, HIGH and MEDIUM finding and
   re-runs the panel on the fix delta only (`--scope <round base> --prior <run>`), for 3 fix
   rounds at most.
2. A separate agent applies the fixes. The reviewer never fixes its own finding. Start the
   `fixer` agent as `orca-workers.md` describes. Under `/deep-execute`, that agent is the owning lane
   (section 1).
3. Fix a MEDIUM finding when the fix is local and does not change behavior. Record every
   finding you do not fix, with the reason, under `## Open findings`.

## 3. Is the environment ready?

Find the app URL in this order: the `base_url` of `qa-plan.yaml`, the QA steps of the plan,
the project `CLAUDE.md`. Check it with `curl -sf -o /dev/null <url>`.

- It answers: run steps 4 and 5.
- It does not answer: skip step 5. Record "QA skipped: <url> did not answer" in the report.
  Do not start or rebuild an environment the user did not ask for. Run step 4 anyway when a
  canvas exists: `qa-ui` then compares from the recordings, the screenshots and the code.

## 4. UI parity — the `qa-ui` agent

**Check the first screen early, not only at the end.** When the plan has a UI design pass or a
canvas, the build checks each screen as soon as it renders:

1. After the first task that renders a new or changed screen, add a row
   `workflow.sh add <file> visual.<screen> "qa-ui on <screen>" --after build.<n>`.
2. Run the `qa-ui` agent on that screen only, against its design images.
3. Fix the differences with the `fixer` before the next task that touches a screen starts.
4. Mark the row done with the folder of the `qa-ui` screenshots. Repeat for each new screen.

The step below is the final pass over every screen.

Run this step when the plan has a UI design pass, or when a canvas exists for the change.
The visual pass of the agent that built the UI does not replace this step. `/ship-it` refuses to
open the PR without a `MATCH` from this agent for the head commit (its Phase 0.6 chain gate). Dispatch the `qa-ui` agent with:

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

1. The `fixer` agent fixes every difference from step 4 and every failure from step 5.
   Start it as `orca-workers.md` describes. The QA agents never fix code.
2. Re-run only the QA agent that found the problem, on the fixed commit.
3. Stop after 3 rounds. Report what is still open and ask the user. The chain runs unattended,
   so ask each decision as an Inbox question when the Inbox exists, else `AskUserQuestion`
   (`~/.claude/skills/_shared/inbox.md`, "Decisions during a build chain").

When a fix changes code that the review saw, run `/deep-review default --scope <commit before
the fixes>..HEAD` once on the fixes only. Do not review the whole change again.

## 7. Demo, report and PR

1. When `.workflow/config.json` exists, run `Skill(skill="workflow-post-implementation")` with
   the step 2 review and the QA results as evidence. It chains to `workflow-finish`.
2. Freeze the commit SHA. Every result in the report names this SHA.
3. When the change adds or alters a feature a person uses, record a narrated demo with the
   `video-demo` skill. Skip it for a refactor, a lone migration or an internal API, and say
   why.
4. Build the report of section 8.
5. Run `/ship-it`, with its watch. It attaches the screenshots and the demo with `gh --attach`,
   opens the PR, and watches it as Phase 5 of `~/.claude/skills/pr-description/SKILL.md`
   describes: review comments go to `address-pr-comments`, failing checks to systematic
   debugging, until the PR merges or closes. Mark the `pr` step done with the PR URL when the
   PR is open.

## 8. Deliver the report

`/deep-execute` builds its report with `build-run-report.sh`. That script reads the lane
records of a run (`manifest.json`, `events.jsonl`, `decision.sh` output), which options B, C
and D do not write. For options B, C and D, write `$RUN_DIR/report/index.html` yourself. It is one self-contained page with these sections:

1. **Summary** — what was built, the ticket, the branch, the frozen SHA.
2. **Requirements** — the ticket coverage table, each row with its proof.
3. **Decisions** — each row of `decisions.md` and each `D-NNN` deviation.
4. **Review** — the findings, what was fixed, and the open findings.
5. **Tests** — the test commands and their results, and each QA scenario with its verdict.
6. **UI parity** — for each element, the artboard and the implementation side by side.
7. **Evidence** — the screenshots and the videos.
8. **Open items** — everything still open, with the reason.

Copy each image and video into `$RUN_DIR/report/media/` and link it by a relative path.
Then run `open "$RUN_DIR/report/index.html"` and give the user the absolute path.

After `/ship-it` opens the PR, send the finished-work summary to the Inbox thread of the ticket or
branch: the PR in `pulls`, the QA screenshots in the body, and the report and videos in
`attachments` (`_shared/inbox.md`). Under `/deep-execute`, a fix during the watch still goes to
the owning lane.
