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
2. `orca status --json | jq -e '.result.runtime.reachable == true'` exits 0.
3. `orca worktree current --json | jq -e '.ok == true'` exits 0: the current folder is an
   Orca worktree.

## 1.5 Choose the agent

Each worker runs a predefined agent from `~/.claude/agents/`. The agent file holds the role,
the rules, the model and the effort. The spec holds only what changes from task to task.

| Work | Agent |
|---|---|
| A task that edits server code, APIs, models, migrations or jobs | `implementer-backend` |
| A task that edits screens, components or client state | `implementer-frontend` |
| A review finding or a QA failure | `fixer` |
| A plan review in `simple-plan` | `plan-reviewer` |

A task that edits both sides goes to `implementer-frontend` when it changes a screen, else to
`implementer-backend`.

Print the result of section 1 before the first worker, in one line: `Workers: orca` or
`Workers: subagent (<check> failed: <reason>)`. If one check fails, use the subagent mode
(section 3). Never use the subagent mode when all three checks pass.

## 2. Orca mode

1. Read the guide once per session: `orca skills get orchestration`. Follow its rules.
2. Write the spec of each worker to a file in the run folder. The spec is self-contained:
   - the one row of `$RUN_DIR/chain.md` that the worker owns, with its exact command. The
     worker does that step only: it starts no other step of the chain, and it hands the next
     step back to this session;
   - the task and the plan path;
   - the files the worker may edit, and the files it must not touch;
   - the test command and the gates that prove it is done;
   - for the frontend, the `Canvas:` URL of the UI design pass, when the plan has one.

   The agent file holds the rules: strict TDD, `ub-mode`, the implementer rules, and no
   commit, push or pull request. Do not repeat them in the spec.
3. Start the worker in two commands. `worker-start --agent` takes only an Orca agent id, not a
   predefined agent. So create the terminal with `claude --agent <name>` first, then start the
   worker in it. Pass the worktree by its id: `--worktree current` names the worktree of the
   Orca terminal that runs this session, which can differ from the folder of the task. It then
   fails with `selector_not_found`. The id from `orca worktree current` follows the folder.
   ```bash
   WT="id:$(orca worktree current --json | jq -r '.result.worktree.id')"
   HANDLE=$(orca terminal create --worktree "$WT" --command "claude --agent <name>" --json \
     | jq -r '.result.terminal.handle')
   orca orchestration worker-start --spec-file <spec> --terminal "$HANDLE" \
     --task-title "<task>" --json
   ```
   Do not pass `--model` or `--effort`: the agent file sets them, and `worker-start` refuses
   them with `--terminal`.
4. Run one worker at a time in the shared worktree. Start workers in parallel only for tasks
   whose file sets do not overlap.
5. End the turn. Orca wakes this session when a worker sends `worker_done`, a question or an
   escalation. Ending the turn to wait for a worker is not a stop: the goal stays open, and
   the chain continues when Orca wakes the session.
6. Answer a question with `orca orchestration reply`. Send a fix to the worker that wrote the
   code with `orca orchestration send --to dispatch:<dispatch_id>`.
7. After `worker_done`, read the diff, run the task's tests and gates, then commit.
8. After the commit, close the worker:
   `orca orchestration worker-release --dispatch <dispatch_id> --json`.

Never type into the terminal of a worker, and never poll a worker. Orca wakes this session
when a worker finishes or asks. When you read its diff, check that it stays inside its task
and its allowed files before you commit. A worker is Claude by default. Use
`--agent codex --model gpt-6.1-terra` only when the user or the plan names Codex for that work.
Codex has no predefined agents, so start the spec of a Codex worker with
`Read ~/.claude/agents/<name>.md and follow it.` A Codex worker or `codex exec` that builds,
fixes or reviews UI gets the design images as images: `codex exec -i <png> -i <png> ...`. In
the spec, list each image path and the motion spec, and tell it to open them. Never send only
the canvas source.

If `worker-start` fails, do not rerun it. Read `failedStage`, follow
`orca skills get orchestration --reference references/recovery-and-cleanup.md`, and use the
subagent mode for that task when the worker cannot start.

## 3. Subagent mode

Start the implementer or fixer with the Agent tool and `subagent_type: <name>` from section
1.5. Send the spec of section 2 as the prompt. Do not pass `model`: the agent file sets it.
Send a follow-up or a fix to the same agent with `SendMessage`.
