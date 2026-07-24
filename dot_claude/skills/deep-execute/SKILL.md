---
name: deep-execute
description: Runs an approved deep-plan parallel plan as lane workers in one shared cmux worktree. Use when invoked via /deep-execute, or when the user has an approved plan whose Execution shape declares disjoint lanes and an API contract and wants it built by parallel agents instead of one session. Coordinates fan-out, the event/reply protocol, round gating, contract drift and escalation — it does not write plans (deep-plan) or review code itself (deep-review, invoked once per run at the end).
---

# deep-execute

You are the **orchestrator** of a `/deep-execute` run. An approved plan already declares
lanes with disjoint `owns` globs, a suggested agent per lane, and one API contract. Every
deterministic check — plan validation, boundary enforcement, contract validation, round
gating — is a script call. Your job is the judgement around those calls: which lane to wake,
whether a `blocked` event is real contract drift or a question you can answer yourself,
whether a round's failures are worth re-running or worth waking a human for.

**You never write lane code.** Lane workers do that, in parallel, in their own cmux panes,
inside the SAME shared worktree. You commit, you gate, you reply — you don't edit their files.

## Phase 0 — Preflight

1. Confirm the target plan is approved and `Mode: parallel` with a declared API contract
   (deep-plan's `validate-plan.sh --root` already enforced this at plan time; `init-run.sh`
   re-checks it before scaffolding anything).
2. Require a clean worktree (`git status --porcelain`). A dirty tree at fan-out time means
   uncommitted work that predates `baseline_commit` — `validate-run-state.sh`'s boundary
   checks diff against that baseline, so anything already dirty at init time gets misread as
   an unowned write from no lane at all.
3. For each non-orchestrator lane, the plan's `agent` column is a **suggestion**, not a
   decision. Present it via `AskUserQuestion` — options are the exact lines in
   `agents.allowlist` — and let the user confirm or swap each lane's agent before launch.

## Phase 1 — Contract and shared files, then scaffold

1. Materialize the plan's contract file and every `shared_read_only` path, commit them —
   **before fanout, and read-only for every lane afterward**. `init-run.sh` refuses to start
   if any of these is missing or uncommitted; this is why.
2. Run `init-run.sh PLAN RUN_DIR CWD ORCH_SURFACE`. It re-validates the plan, records
   `baseline_commit` as the current `HEAD`, writes the schema-conformant `RUN_DIR/manifest.json`
   (contract, workers, `max 3 rounds` by default), and scaffolds `events.jsonl`,
   `lanes/<lane>/reply.md`, `worker-<lane>.files.txt` and cmux's own `RUN_DIR/cmux/manifest.json`.
3. If the user passed `--max-rounds N` and `N` differs from the default, patch
   `RUN_DIR/manifest.json`'s `max_rounds` field now — `round-gate.sh` reads that field, never a
   hardcoded number, so this is the only place the override needs to land.
4. Launch every non-orchestrator lane in the same worktree with the confirmed agent specs,
   via cmux-orchestrator's `launch-workers.sh RUN_DIR/cmux CWD SPEC...` (grammar
   `name:runner:model@effort`; bare `name` means `claude:sonnet`).

## Phase 2 — Monitor and react

Hold a `Monitor` on `monitor-events.sh RUN_DIR`, in a loop, for the whole round. Every trigger
except `timeout` exits 0 — branch on the JSON `.type` field, never the exit code. The filter
must cover the happy path AND the failure path alike: `waiting`, `blocked`, `question`, `done`
— and `invalid_event`, `vanished_pane`, `fatal_signature`, `monitor_error`, `timeout`. A filter
that only recognizes the first four goes silent on a crash, and silence reads as "still
working" — treat every failure-signature trigger as its own incident, not a warning to log
past.

- **`question`** — answer from the plan or the materialized contract when the answer is
  already decided there; otherwise `AskUserQuestion` the human and `reply.sh LANE` with their
  answer.
- **`waiting`** — a lane that finished its assigned work emits `waiting` and stops; it does
  not poll. Read `board.sh RUN_DIR` (or the manifest's `depends_on`) and do not wake a
  `waiting` lane until every lane in its `depends_on` has emitted `done`. A reply that never
  arrives strands that lane forever — an unsent wake is an incident, not a warning.
- **`blocked` — contract drift.** A worker blocked on the contract itself means the contract
  is wrong, not the worker. Edit the materialized contract directly, bump its semantic version,
  commit the change (workers never commit — see Rules), recompute its sha256 and patch
  `manifest.json`'s `contract.version`/`contract.sha256` so `validate-contract.sh` checks
  against the new baseline, then run `reply.sh RUN_DIR --all "<new version + summary>"` —
  every lane needs to learn the contract moved, not just the one that noticed.
- **`done`** — record it; once every non-orchestrator lane has emitted `done`, the round is
  ready to gate.
- **`invalid_event` / `vanished_pane` / `fatal_signature` / `monitor_error`** — investigate the
  named lane (`board.sh --lane LANE`, a manual pane capture) before deciding whether to
  restart it or escalate; never assume it will recover on its own.
- **`timeout`** — nothing fired within the bound; call `monitor-events.sh` again unless the
  silence itself looks like a stall worth investigating.

## Phase 3 — Round gate

Once every non-orchestrator lane has emitted `done` for the round, run
`round-gate.sh RUN_DIR ROUND --json`. It short-circuits lane tests → contract
(`validate-contract.sh`) → run-state (`validate-run-state.sh`) → one light reviewer pass, in
that fixed cheapest-first order, and reports every stage — including the ones it skipped.

**A failing `round-gate.sh` JSON is a hard gate: read which item failed, fix the root cause
(route the fix back through the owning lane via `reply.sh`), rerun `round-gate.sh` — never
advance the round on a failing gate.** `warn`-only items (e.g. `post-done-writes-absent`)
never block; only `fail` does.

For round 1 specifically, let `round-gate.sh`'s own review stage run and settle before
surfacing anything about that round to the human — round 1 gets orchestrator review before
anything reaches the human. Only a genuine hard-gate failure that survives a fix attempt, or
the max-rounds cap below, is worth `AskUserQuestion`.

Once a round passes, commit it (`git add -A && git commit`) — workers never run `git`; the
orchestrator is the sole committer, between rounds. Then bump `manifest.json`'s `round` and
either start the next round (more tasks remain) or move to Phase 4.

**After three rounds, stop and `AskUserQuestion`.** `round-gate.sh RUN_DIR 4` (or whatever
exceeds `max_rounds`) already refuses outright with its own escalation record instead of
running anything — obey it rather than calling it a fourth time on your own judgement.

## Phase 4 — Final review, frozen SHA, and QA evidence

When every lane is `done` and the last round's gate passed, run one full `/deep-review` over
the whole run's diff (`Skill(skill="deep-review")`) — this is the one thorough pass; every
per-round `round-gate.sh` review was intentionally light. Apply required fixes, rerun relevant
verification, commit final state, then record full `git rev-parse HEAD`.

If approved plan's `## QA / test-execution` references `qa-plan.yaml`, resolve running URL from
environment/worktree config and invoke:

```text
Skill(
  skill="qa-test-plan",
  args="--phase execute --qa-plan <path> --url <url> --commit <full-sha>"
)
```

QA must execute after review/fixes so evidence binds final SHA. Any later code change invalidates
that report and requires new QA attempt. Do not finish with missing, blocked, or stale evidence;
surface blocker when URL or commit proof is unavailable.

Report run directory, final `board.sh` table, contract version, round count, final SHA, QA verdict,
and HTML report path. **Leave panes alive** — success does not tear down cmux state.

## Resume (`--resume RUN_DIR`)

Reconstructible from disk: `manifest.json` (round, `max_rounds`, contract state, worker
list), the full history in `events.jsonl` via `board.sh`, and every round already committed
to git. **Not** reconstructible: whether a lane's pane is still alive and mid-edit — the last
line in `events.jsonl` proves only what that lane last reported, not its current state.
Before resuming the monitor loop, probe every lane (a fresh `monitor-events.sh` call surfaces
`vanished_pane`/`fatal_signature` for real) rather than trusting the board on faith.

## Attribution is self-declared, not authenticated

`worker-<lane>.files.txt` is a log a lane writes about itself — any process with access to
`RUN_DIR` could log any path under any lane's name. Do not describe it, in anything you say to
the user, as proving who wrote what. The one enforced boundary is `changed-files-within-union`
inside `validate-run-state.sh`: computed from git only, independent of any worker's own
claims. Everything else attribution-shaped (`changed-files-attributed-once`,
`worker-file-logs-valid`, `post-done-writes-absent`) is advisory diagnostic, not proof.

## Rules

- Workers never run `git` — the orchestrator is the sole committer, between rounds.
- The contract and shared files are committed before fanout and are read-only afterwards.
- A failing `round-gate.sh` JSON is a hard gate — read it, fix, rerun, never advance.
- The plan suggests a lane's agent; `AskUserQuestion` confirms it against `agents.allowlist`.
- Round 1 gets orchestrator review before anything reaches the human.
- After three rounds, stop and `AskUserQuestion`.
