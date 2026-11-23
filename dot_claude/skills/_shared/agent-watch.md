# Watch the agents you started

An orchestrator that starts agents and then waits for them can miss two failures. The agent
stalls: it waits on a prompt, loops, or dies. Or the agent drifts: it works, but on the wrong
thing. This rule makes the orchestrator look at both, on a schedule.

It applies to every executor that starts agents for tasks or lanes: `implement` (Orca workers
and subagents), `deep-execute` (lane workers), a `Workflow` run, and a `codex exec` slice.

## 1. Start the check with the first agent

When the first agent starts, schedule a recurring check every 10 minutes.

- Claude Code: `CronCreate(cron="*/10 * * * *", prompt="Check the agents of <run>: <how to read their status and their scope>")`.
  Keep the job ID. Record it: `workflow.sh log <step file> "watch job <id>"`.
- Codex has no scheduler. Wait on the agents with a timeout of 10 minutes or less, and run
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

An agent is **stalled** when one of these is true:

- It shows no new output, step, commit or log line since the previous check.
- It waits on a permission prompt, a question, or an input that nobody will send.
- Its process or pane is gone and it emitted no `done`.

An agent is **off course** when one of these is true:

- It edits a file outside the files its task allows.
- Its diff does something the task and the plan do not ask for, or skips what they ask for.
- It skipped a step of its step file, such as the failing test before the code.
- It works around a failing test, a lint rule or a gate instead of fixing the cause.

Act on each stalled or off-course agent at once:

1. Read its log and its diff first.
2. Send it the correction: what is wrong, the plan section or the task line it breaks, and
   what to do instead. Use `orca orchestration send`, `SendMessage` or `reply.sh`.
3. Wake or restart a stalled agent the same way.
4. Escalate to the user when the same agent stalls or drifts twice. Do not wait for it to
   recover by itself.

Record each correction in the Log of the step file, for example
`workflow.sh log <file> "build.2 corrected: worker w2 edited src/api outside its scope"`.

## 3. Stop the check

Delete the job with `CronDelete` when the last agent finished. Do not leave a check that runs
after the build ends.
