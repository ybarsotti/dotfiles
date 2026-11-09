# deep-execute

Runs an approved [deep-plan](../deep-plan/README.md) parallel plan as lane workers, one Orca
terminal per lane, inside ONE shared git worktree. Each worker stays inside its lane's `owns`
globs; the orchestrator is the sole committer, gates every round, and routes every fix back to
the lane that owns the code. `SKILL.md` is the orchestrator's procedure; this file is the
reference for the person who runs it.

## Quick start

Prerequisites:

- [ ] The plan is approved and published (`publish-plan.sh`), with `Mode: parallel`, disjoint
      lanes and one API contract. `_shared/plan-routing.md` says when a plan qualifies.
- [ ] The worktree is clean (`git status --porcelain` prints nothing).
- [ ] The contract file and every `shared_read_only` file exist and are committed.
- [ ] The session runs inside an Orca workspace (`orca worktree current` succeeds).
- [ ] `jq`, `git`, `claude`, and `codex` when a lane uses it, are on `PATH`.
- [ ] bash 4 or later is on `PATH` (`bash --version`; macOS needs `brew install bash`).

Run it from Claude Code:

```bash
/deep-execute /abs/path/docs/superpowers/plans/2026-11-09-totals/plan.md
```

- The run directory defaults to `~/.claude/deep-execute-runs/run-YYYYmmdd-HHMMSS`.
- `--dry-run` scaffolds into a temporary directory, prints the lanes, agents, contract and
  expected review count, and stops.
- `--max-rounds N` changes the cap (default max 3 rounds).
- `--agent LANE=AGENT` replaces the plan's agent of one lane; AGENT is a line of
  `agents.allowlist`.
- Resume an interrupted run: `/deep-execute --resume RUN_DIR`. It reads the plan from the
  run's `manifest.json`.

Known tradeoff: claude lanes run with `--dangerously-skip-permissions`, with no sandbox. They
rely on the shared-worktree boundary checks, on `Bash(git:*)` as a disallowed tool, and on a
`git` shim first on `PATH` for every lane (an absolute path such as `/usr/bin/git` bypasses it). Codex
lanes run in the `workspace-write` sandbox, with the run directory writable and network on.
Codex lanes need write access to the run directory for `event.sh`, so a misbehaving lane
could edit `manifest.json`. The round gate validates the manifest schema again, and the
orchestrator is the only committer.

## Scripts

```
scripts/init-run.sh          validates the plan, scaffolds RUN_DIR once (refuses a second call)
scripts/orca-launch.sh       one Orca terminal per lane running worker-loop.sh; relaunches a lane
scripts/worker-loop.sh       runs one lane as agent turns: brief first, then each reply
scripts/event.sh             atomic append to events.jsonl (workers call it)
scripts/board.sh             folds events.jsonl to a Markdown status table
scripts/monitor-events.sh    blocks, emits ONE trigger JSON; --ack SEQ marks it handled
scripts/reply.sh             publishes a numbered reply for a lane; the publish is the wake
scripts/contract-bump.sh     records an approved contract change and its checkpoint commit
scripts/validate-contract.sh sha256 / version / lint check on the contract
scripts/validate-run-state.sh schema + boundary checks (the union guarantee lives here)
scripts/round-gate.sh        round bound → round complete → lane tests → acceptance → contract → run state
scripts/decision.sh          records one lane decision or assumption
scripts/build-run-report.sh  renders the run's HTML report from the run directory alone
scripts/finish-run.sh        refuses to finish without a rendered report, then opens it
scripts/run-status.sh        phase, task percentage, elapsed time, and the loop state of each lane
scripts/set-phase.sh         advances the human-facing phase
schemas/event.jq             the one event validator that every writer and reader applies
```

## The lane loop

The orchestrator never types into a terminal. Each lane runs `worker-loop.sh RUN_DIR LANE`,
which takes its runner, model, effort and session id from `launch/manifest.json`:

- The first turn sends the rendered brief (`launch/worker-<lane>.prompt.md`), with the worker
  rules (`launch/system-prompt.txt`) as a system prompt.
- `reply.sh` publishes `lanes/<lane>/replies/<NNNNNN>.md` atomically. The loop delivers every
  reply above `replies.consumed` on its next turn, also one that landed mid-turn.
- A claude lane keeps one conversation: `--session-id` on the first turn, `--resume` after, also
  after a relaunch. A codex lane is stateless, so each codex turn sends the rules and the brief
  again.
- `done` ends a round, not the lane: the loop waits for the next reply. It exits 0 only when
  `lanes/<lane>/stop` exists.
- The loop writes `lanes/<lane>/loop.pid` and tees the agent output to
  `lanes/<lane>/worker.log`. A failing agent, a turn timeout and the turn cap emit `blocked`.

### Without Orca

Start each loop in any terminal, or headless:

```bash
nohup ~/.claude/skills/deep-execute/scripts/worker-loop.sh RUN_DIR LANE >/dev/null 2>&1 &
```

Liveness reads the pid file, so the monitor and `reply.sh` work the same way.

## The lane-agent allowlist

The plan's `agent` column must be one of the lines in `agents.allowlist`, which
`validate-plan.sh` checks. That agent runs without a second question; `--agent` overrides it.

```
opus high
sonnet high
codex gpt-5.6-terra high
codex gpt-6-sol medium
```

## Event / reply protocol

- **`event.sh RUN_DIR LANE TASK TYPE MSG [--files PATH...]`** — the only way to write
  `events.jsonl`. `TYPE` is `task_start`, `task_done`, `progress`, `question`, `waiting`,
  `blocked` or `done` (`decision` comes from `decision.sh`). The lane must be a lane of the run;
  the event carries the round from `manifest.json`. `--files` appends to that lane's
  `worker-<lane>.files.txt`.
- **`board.sh RUN_DIR [--lane LANE]`** — the latest event per (lane, task) as a table.
- **`monitor-events.sh RUN_DIR`** prints one trigger: `question`, `waiting`, `blocked`,
  `done`, `invalid_event`, `vanished_pane`, `fatal_signature`, `monitor_error` or `timeout`.
  `timeout` and `monitor_error` exit 1; the others exit 0. An event trigger repeats until
  `monitor-events.sh RUN_DIR --ack <seq>`, so a crash between trigger and reply loses nothing.
- **`reply.sh RUN_DIR LANE|--all MESSAGE`** — one JSON line per lane; `woken:false` when the
  lane's loop is not running. The reply waits on disk for the relaunch.

## Round policy

`round-gate.sh RUN_DIR ROUND --json` short-circuits in a fixed order and reports every stage,
the skipped ones too. A `fail` blocks the round; `warn` never does. A child validator that
crashes is a `fail`. The default cap is max 3 rounds (`--max-rounds N`). After 3 failed gates of
one round, the gate refuses the round until a human decides. After each passing round the
orchestrator commits, then runs a report-only `/deep-review` and routes the fixes to the lanes.

## Contract drift

A `blocked` event about the contract means the contract must change. After the user approves,
the orchestrator edits the contract, bumps its semantic version, commits it, runs
`contract-bump.sh RUN_DIR VERSION`, and announces it with `reply.sh RUN_DIR --all`. The bump
stores the new hash and `checkpoint_commit`; the contract checks compare against that
checkpoint, and `baseline_commit` stays the start of the run.

## Attribution: what is and isn't enforced

`worker-<lane>.files.txt` is a log a lane writes about itself: it is **self-declared and
unauthenticated**. The one enforced boundary is `changed-files-within-union` in
`validate-run-state.sh`, computed from git only (the union of every lane's `owns`, diffed
against `baseline_commit`). `worker-file-logs-valid`, `changed-files-attributed-once` and
`post-done-writes-absent` only `warn`: they are diagnostics that a forged or missing log entry
can defeat.

## Artifacts produced

```
RUN_DIR/
├── manifest.json                 run state (schemas/run-state.schema.json)
├── status.json                   phase and start time
├── events.jsonl                  append-only event log
├── decisions.md                  the orchestrator's own decisions
├── worker-<lane>.files.txt       per-lane attribution log (self-declared)
├── gate/round-<N>.fails          failed gates of a round (the retry budget)
├── lanes/<lane>/replies/         numbered replies; replies.consumed is the delivered mark
├── lanes/<lane>/decisions/       decision records of the lane
├── lanes/<lane>/loop.pid         pid of the lane loop; stop ends it
├── lanes/<lane>/worker.log       agent output of the lane
├── launch/manifest.json          per lane: runner, model, effort, session_id, brief, block_ref
├── launch/system-prompt.txt      the worker rules
├── launch/worker-<lane>.prompt.md the rendered brief
└── report/index.html             the run report (build-run-report.sh)
```
