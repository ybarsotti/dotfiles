# Watch the agents you started

An orchestrator that starts agents and then waits for them can miss a stalled agent. The
agent waits on a prompt, loops, or dies, and the orchestrator does not look. This rule makes
the orchestrator look on a schedule.

It applies to every executor that starts agents for tasks or lanes: `implement` (subagents),
`deep-execute` (lane workers), a `Workflow` run, and a `codex exec` slice.

## 1. Start the check with the first agent

When the first agent starts, schedule a recurring check every 5 minutes.

- Claude Code: `CronCreate(cron="*/5 * * * *", prompt="Check the agents of <run>: <how to read their status>")`.
  Keep the job ID.
- Codex has no scheduler. Wait on the agents with a timeout of 5 minutes or less, and run
  the check at each timeout.

Write in the prompt where the status lives, so the check needs no other context: the task
IDs, the `RUN_DIR`, `board.sh RUN_DIR`, the worker logs, or the `/workflows` run.

## 2. Run the check

For each running agent, compare its state with the previous check. An agent is **stalled**
when one of these is true:

- It shows no new output, commit, event or log line since the previous check.
- It waits on a permission prompt, a question, or an input that nobody will send.
- Its process or pane is gone and it emitted no `done`.

Act on each stalled agent at once. Read its log first. Then answer it, wake it (`SendMessage`,
`reply.sh`), or restart it. Escalate to the user when the same agent stalls twice. Do not
wait for a stalled agent to recover by itself.

## 3. Change the interval

- After 2 checks in a row where every agent made progress, replace the job with one that
  runs every 20 minutes (`CronDelete`, then `CronCreate(cron="*/20 * * * *", ...)`).
- Go back to every 5 minutes after a stall, and after you start a new agent or a new round.

## 4. Stop the check

Delete the job with `CronDelete` when the last agent finished. Do not leave a check that
runs after the build ends.
