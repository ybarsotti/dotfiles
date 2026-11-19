# Workers in Orca

The build chain starts its implementer and fixer agents as Orca workers when the session runs
in Orca. Each worker is a child of this session: it gets its own pane, the user can watch it,
and Orca wakes this session when the worker reports. Outside Orca, the chain uses its own
subagents, as before.

This file applies to the implementer of each task in `implement`, to the fixer agent of
`after-approval.md` sections 2 and 6, and to the fresh implementer that `/deep-execute` starts
for a file that no lane owns. `/deep-execute` lanes already run in Orca terminals through
`orca-launch.sh`. QA agents stay subagents.

## 1. Choose the mode

Use Orca mode when all three checks pass:

1. `command -v orca` finds the CLI.
2. `orca status --json` reports `runtimeReachable: true`.
3. `orca worktree current --json` resolves the current folder to an Orca worktree.

If one check fails, use the subagent mode (section 3). Say which check failed, in one line.

## 2. Orca mode

1. Read the guide once per session: `orca skills get orchestration`. Follow its rules.
2. Write the spec of each worker to a file in the run folder. The spec is self-contained:
   - the task and the plan path;
   - the files the worker may edit, and the files it must not touch;
   - the rules: strict TDD, the `ub-mode` skill and its gates, no `git commit`, no
     `git push` and no pull request (this session commits and opens the PR with `/pr`);
   - the code rules: read `~/.claude/skills/_shared/implementer-rules.md`, the Core section
     plus Backend or UI for the files of the task;
   - the evidence that proves it is done: the test command and its output, the gate output.
3. Start the worker:
   `orca orchestration worker-start --spec-file <spec> --worktree current --agent claude
   --model sonnet --effort medium --task-title "<task>" --json`
4. Run one worker at a time in the shared worktree. Start workers in parallel only for tasks
   whose file sets do not overlap.
5. End the turn. Orca wakes this session when a worker sends `worker_done`, a question or an
   escalation. Ending the turn to wait for a worker is not a stop: the goal stays open, and
   the chain continues when Orca wakes the session.
6. Answer a question with `orca orchestration reply`. Send a fix to the worker that wrote the
   code with `orca orchestration send --to dispatch:<dispatch_id>`.
7. After `worker_done`, read the diff, run the task's tests and gates, then commit.

Never poll a worker, and never type into its terminal. A worker is Claude by default. Use
`--agent codex` only when the user or the plan names Codex for that work.

If `worker-start` fails, do not rerun it. Read `failedStage`, follow
`orca skills get orchestration --reference references/recovery-and-cleanup.md`, and use the
subagent mode for that task when the worker cannot start.

## 3. Subagent mode

Start the implementer or fixer with the Agent tool. The subagent runs on the model of
`CLAUDE_CODE_SUBAGENT_MODEL` (Sonnet). Watch it on the schedule of `agent-watch.md`.
