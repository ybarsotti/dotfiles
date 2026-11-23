# Watch the agents you started

An orchestrator that starts agents and then waits for them can miss two failures. The agent
stalls: it waits on a prompt, loops, or dies. Or the agent drifts: it works, but on the wrong
thing. This rule makes the orchestrator look at both, on a schedule.

It applies to every session that delegates work to agents:

- the planning skills: `simple-plan` and `deep-plan` start explorers, the planners of
  `dispatch-planners.sh`, the `plan-reviewer` agents and the review personas, the breakdown
  and UI/UX agents, and the `ui-designer` worker;
- the executors: `implement` (Orca workers and subagents), `deep-execute` (lane workers), a
  `Workflow` run, and a `codex exec` slice.

## 1. Start the check with the first agent

When the first agent starts, schedule a recurring check every 5 minutes.

- Claude Code: `CronCreate(cron="*/5 * * * *", prompt="Check the agents of <run>: <how to read their status and their scope>")`.
  Keep the job ID. Record it: `workflow.sh log <step file> "watch job <id>"`.
- Codex has no scheduler. Wait on the agents with a timeout of 5 minutes or less, and run
  the check at each timeout.

Write in the prompt everything the check needs, so it needs no other context: the `RUN_DIR`,
the plan path, each agent with its task and its allowed files, and where its status lives
(its step file `$RUN_DIR/agents/<agent>-<task>.md`, `orca orchestration worker-read`,
`board.sh RUN_DIR`, the worker logs, or the `/workflows` run).

The check is the only poll. Between two checks, end the turn and let Orca or the harness wake
you when an agent finishes or asks.

## 2. Run the check

For each running agent, read its step file (`workflow.sh status <file>`), its latest output
and its diff (`git -C <worktree> diff --stat` and `git diff` of the files it touched). Compare
them with the previous check and with its task.

An agent must never sit still. An agent is **stalled** when one of these is true:

- It shows no new output, step, commit or log line since the previous check.
- It waits on a permission prompt, a question, or an input that nobody will send.
- Its process or pane is gone and it emitted no `done`.
- One command runs far longer than it should, or never ends: a test runner in watch mode, a
  dev server in the foreground, a `sleep` or polling loop, an install that hangs, a `git`
  command that waits for an editor, a command that waits on stdin.
- It loops: the same command, the same error or the same failing test shows up 3 or more times
  in its output, or it edits a file back and forth between two versions.
- Its output moves but its step file and its diff do not change across 2 checks. It is busy,
  not making progress.

An agent is **off course** when one of these is true:

- It edits a file outside the files its task allows.
- Its diff does something the task and the plan do not ask for, or skips what they ask for.
- It skipped a step of its step file, such as the failing test before the code.
- It works around a failing test, a lint rule or a gate instead of fixing the cause.
- An explorer or a planner researches something the question did not ask, reads the same
  files again and again, or drafts a plan for a different problem than the task.
- A reviewer reviews something outside the plan or the diff it got.

Act on each stalled or off-course agent at once:

1. Read its log and its diff first: `orca orchestration worker-read`, `orca terminal read`,
   the subagent output, or the lane log.
2. Stop a hung command. In Orca: `orca terminal send --terminal <handle> --interrupt`. For a
   background job of the harness: `TaskStop`. Then tell the agent which command hung and how
   to run it so it ends: a non-watch flag, a timeout, `--no-edit`, input from a file.
3. Break a loop. Tell the agent what repeats, what you see as the cause, and the next step to
   try. When it cannot find the cause, tell it to run `superpowers:systematic-debugging`
   instead of a new attempt at the same fix.
4. Send a drift correction: what is wrong, the plan section or the task line it breaks, and
   what to do instead. Use `orca orchestration send`, `SendMessage` or `reply.sh`.
5. Restart an agent that does not answer the message, with the same spec and a note on what
   went wrong.
6. Escalate to the user when the same agent stalls or drifts twice. Do not wait for it to
   recover by itself.

Record each correction in the Log of the step file, for example
`workflow.sh log <file> "build.2 corrected: worker w2 edited src/api outside its scope"`.

## 3. Stop the check

Delete the job with `CronDelete` when the last agent finished. Do not leave a check that runs
after the build ends.
