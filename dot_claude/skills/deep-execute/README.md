# deep-execute

Runs an approved [deep-plan](../deep-plan/README.md) parallel plan as lane workers, in
parallel Wave Terminal blocks, inside ONE shared git worktree. Every worker stays inside its lane's
declared `owns` globs; the orchestrator is the sole committer, gates every round, and never
lets a worker touch `git` itself.

## Quick start

```bash
# 1. Have an approved plan whose Execution shape declares Mode: parallel, disjoint lanes,
#    and one API contract (deep-plan produces exactly this shape).

# 2. Run the slash command from Claude Code
/deep-execute /absolute/path/to/plan.md
/deep-execute /absolute/path/to/plan.md --max-rounds 5
/deep-execute /absolute/path/to/plan.md --resume ~/.claude/deep-execute-runs/<RUN_ID>
```

## Architecture

```
slash command (~/.claude/commands/deep-execute.md)
   │
   ▼
SKILL.md (this skill — orchestrates)
   │
   ▼
scripts/init-run.sh        — validates the plan, scaffolds RUN_DIR + manifest.json
scripts/event.sh           — atomic append to events.jsonl (workers call this, not the orchestrator)
scripts/board.sh           — folds events.jsonl to a Markdown status table
scripts/monitor-events.sh  — blocks, emits ONE trigger JSON, never guesses past what it observed
scripts/reply.sh           — writes lanes/<lane>/reply.md and wakes the pane
scripts/validate-contract.sh   — sha256 / version / lint check on the contract
scripts/validate-run-state.sh  — schema + boundary checks (the union guarantee lives here)
scripts/round-gate.sh      — lane-tests → contract → run-state → light review, in that order
scripts/decision.sh        — records one lane decision/assumption, then announces it on the log
scripts/build-run-report.sh — renders the run's HTML report from the run directory alone
```

`init-run.sh` scaffolds `RUN_DIR/wave/` as the launch transport's own run directory (a
different manifest shape than this skill's own `RUN_DIR/manifest.json`) and `wave-launch.sh`
launches each lane there as a Wave block running `worker-loop.sh`.

**Why a loop instead of a REPL.** Wave has no way to type into a live block — `wsh run`
launches one and `wsh termscrollback` reads one, but there is no `wsh send`. cmux had
`cmux send`, which is how a `waiting` lane used to be woken. So the wake is a file:
`worker-loop.sh` blocks on `lanes/<lane>/reply.md` and resumes the lane's session when it
moves. Each lane is pinned to its own `--session-id` UUID, because every lane shares one
worktree and resuming "the last session" would cross lanes. Codex lanes are stateless per
turn — `codex exec resume` takes a session id but nothing pins one at creation — so a codex
lane re-reads its prompt file and reply each turn instead.

## The lane-agent allowlist

The plan's `agent` column (e.g. `opus high`, `codex gpt-5.6-terra high`) is a **suggestion**.
Before launch, the orchestrator confirms or swaps each lane's agent via `AskUserQuestion`,
offering exactly the lines in `agents.allowlist`:

```
opus high
sonnet high
codex gpt-5.6-terra high
codex gpt-5.6-sol high
```

`validate-plan.sh` already checked the plan's suggestion is one of these lines; the
`AskUserQuestion` step is about the human's judgement, not a second validity check.

## Event / reply protocol

Workers never talk to the orchestrator except through two scripts:

- **`event.sh RUN_DIR LANE TASK TYPE MSG [--files PATH...]`** — the only way to write to
  `events.jsonl`. `TYPE` is one of `task_start`, `task_done`, `progress`, `question`,
  `waiting`, `blocked`, `done` (plus `decision`, which only `decision.sh` emits). `--files`
  appends to that lane's `worker-<lane>.files.txt` attribution log in the same call.
- **`board.sh RUN_DIR [--lane LANE]`** — the only way a worker reads run state; folds the
  log to the latest event per (lane, task) as a Markdown table.
- **`decision.sh RUN_DIR LANE TASK --title T --rationale R [--kind decision|assumption]
  [--alternative A]... [--tradeoff T]...`** — records one non-obvious choice.

A lane that finishes its assigned work emits `waiting` and **stops** — it does not poll. The
orchestrator's `Monitor` sits on `monitor-events.sh RUN_DIR`, which blocks until exactly one
trigger fires (draining any backlog first, so an event that landed before the monitor
attached is never missed) and prints one JSON line:

```json
{"type": "waiting", "lane": "backend", "task": "Task 3", "msg": "...", "run_dir": "..."}
```

`type` is one of the happy-path triggers (`waiting`, `blocked`, `question`, `done`) or a
failure signature (`invalid_event`, `vanished_pane`, `fatal_signature`, `monitor_error`,
`timeout`) — every trigger except `timeout` exits 0, so the caller must branch on `.type`,
never the exit code. Once the orchestrator has something for a lane, `reply.sh RUN_DIR
LANE MESSAGE` (or `reply.sh RUN_DIR --all MESSAGE` for a contract-wide announcement) writes
`lanes/<lane>/reply.md`, and that write IS the wake. `reply.sh` attempts
every lane even when an earlier one fails to wake, and reports each lane's outcome as its own
JSON line — a wake failure is surfaced, never swallowed, because a `waiting` lane that never
gets its reply is stranded by design.

## Round policy

`round-gate.sh RUN_DIR ROUND --json` runs, in this fixed cheapest-first order, short-
circuiting on the first failure: lane tests (each lane's own `test_command`) → contract
(`validate-contract.sh`) → run-state (`validate-run-state.sh`) → one light reviewer pass
(deep-review's `project-patterns` persona, must `APPROVE`). Every stage's records are
returned even when skipped — nothing is silently omitted, nothing skipped is reported as
having passed. A `fail` blocks the round; `warn` (e.g. `post-done-writes-absent`) never does.

The default cap is **max 3 rounds**, read from `manifest.json`'s `max_rounds` (patched at
init time if `--max-rounds N` was passed). Calling `round-gate.sh` for a round beyond the cap
refuses outright — an escalation record, every other stage skipped — rather than running
anything. The orchestrator commits each passing round (`git add -A && git commit`); workers
never run `git` themselves. After three rounds without a clean pass, the orchestrator stops
and calls `AskUserQuestion` rather than looping on its own judgement.

## Contract drift

A `blocked` event about the contract itself means the contract needs to change, not the
worker. The orchestrator edits the materialized contract, bumps its semantic version,
commits (workers never commit), recomputes the sha256 and patches `manifest.json`'s
`contract.version`/`contract.sha256`, then runs `reply.sh RUN_DIR --all` with the new
version — every lane learns the change, not just the one that hit it.

## Resume

`--resume RUN_DIR` reconstructs from disk what's genuinely on disk: `manifest.json` (round,
`max_rounds`, contract state, worker list), the full event history via `board.sh`, and every
round already committed to git. It does **not** reconstruct whether a given lane's pane is
still alive and mid-edit — the last event in `events.jsonl` proves only what that lane last
reported. Resume re-probes every lane through `monitor-events.sh` (which surfaces
`vanished_pane`/`fatal_signature` for real) before trusting the board and resuming the wait
loop.

## Attribution: what is and isn't enforced

`worker-<lane>.files.txt` is a log a lane writes about itself — it is **self-declared and
unauthenticated**. Any process with access to `RUN_DIR` can log any path under any lane's
name; nothing here proves who actually wrote a given file. The one boundary that is actually
enforced is `changed-files-within-union` inside `validate-run-state.sh`: computed from git
only (the union of every lane's `owns`, diffed against the round's baseline commit),
independent of anything a worker claims about itself. Everything else attribution-shaped —
`changed-files-attributed-once`, `worker-file-logs-valid`, `post-done-writes-absent` — is an
advisory diagnostic that a forged or missing log entry can defeat; treat its `warn`/`fail` as
a signal worth investigating, never as proof.

## Decision records and the run report

An approved plan carries the reasoning behind the decisions taken *before* any code was
written. Everything decided *during* the run — which of two viable implementations a lane
picked, what it assumed about a lane it doesn't own, where it worked around something the plan
didn't anticipate — lives only in that worker's session, and dies with it. `decision.sh` is the
one channel that outlives the pane:

```bash
decision.sh RUN_DIR LANE TASK --title "Materialized view for the totals" \
  --rationale "The plan left the aggregation strategy open; a view keeps reads to one query." \
  --alternative "Compute in the API layer — N+1 across three tables" \
  --tradeoff "Up to 60s of refresh lag on the totals"
```

It writes `lanes/<lane>/decisions/<NNN>.json` and emits a `decision` event carrying only the
headline. The split is not cosmetic: an `events.jsonl` line has to stay single-line and under
`PIPE_BUF` for concurrent appends to be atomic, and rationale is prose. `decision` events are
deliberately **not** monitor triggers — they are for the report to read, not a reason to
interrupt a round.

`build-run-report.sh RUN_DIR [--final-sha SHA] [--review report.md] [--qa index.html]` then
renders `RUN_DIR/report/index.html`: what was built (git diffstat, baseline → frozen SHA), the
lane table with `owns`/`depends_on`, every recorded decision with its alternatives and
tradeoffs, the plan's own pre-implementation rationale, drift (contract version moved, extra
rounds, blocked lanes), the final board plus the full event timeline, and the review and QA
evidence. Self-contained HTML, light and dark, no external assets.

Every claim on that page comes from a file in the run directory — it is never written or
padded from a model's memory of the run. The honest consequence: a decision no lane recorded
is absent from it, and the page says that rather than implying no decisions were made. The
same caveat as attribution applies — a decision record is the lane's own account of its
reasoning, which is the best account anyone will get and still not an audit trail.

## Artifacts produced

```
RUN_DIR/
├── manifest.json                  # schema-conformant run state (schemas/run-state.schema.json)
├── events.jsonl                   # append-only event log
├── worker-<lane>.files.txt        # per-lane attribution log (self-declared, see above)
├── lanes/<lane>/reply.md          # the orchestrator's current instruction for that lane
├── lanes/<lane>/decisions/NNN.json # decisions/assumptions that lane recorded mid-run
├── light-review/round-<N>/        # round-gate.sh's own reviewer transcript per round
├── report/index.html              # the run report (build-run-report.sh)
└── wave/
    ├── manifest.json              # launch bookkeeping (block_ref, session_id)
    └── worker-<lane>.prompt.md    # the prompt each lane block was launched with
```

At the end of a successful run, one full `/deep-review` pass runs over the whole diff, the run
report is built, and the Wave blocks are left alive — teardown is a separate, human-confirmed
step.
