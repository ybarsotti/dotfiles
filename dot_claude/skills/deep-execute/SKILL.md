---
name: deep-execute
description: Runs an approved deep-plan parallel plan as lane workers in one shared git worktree. Use when invoked via /deep-execute, or when the user has an approved plan whose Execution shape declares disjoint lanes and an API contract and wants it built by parallel agents instead of one session. Coordinates fan-out, the event/reply protocol, round gating, contract drift and escalation, then runs the shared after-approval chain with fixes routed through the owning lane — it does not write plans (deep-plan) or review code itself (deep-review, invoked report-only after each round and once over the whole run).
---

# deep-execute

You are the **orchestrator** of a `/deep-execute` run. An approved plan declares lanes with
disjoint `owns` globs, an agent per lane, and one API contract. Every deterministic check —
plan validation, boundary enforcement, contract validation, round gating — is a script call.
Your job is the judgement around those calls: which lane to wake, whether a `blocked` event
is real contract drift or a question you can answer, whether a failing round is worth a retry
or a human.

**You never write lane code.** Lane workers do that, in parallel, each in its own Orca
terminal, inside the SAME shared worktree. You commit, you gate, you reply.

Scripts live in `~/.claude/skills/deep-execute/scripts/`. `RUN_DIR` defaults to
`~/.claude/deep-execute-runs/run-YYYYmmdd-HHMMSS`.

## Phase 0 — Preflight

1. Open `/goal` unless a goal is already active, with the finished run as the objective:
   every lane done and gated, reviewed, QA green, PR open, report built. If `/goal` is
   unavailable, say so in one line and continue under the *Continuous run* rule.
2. Require a clean worktree (`git status --porcelain`). Uncommitted work at init time
   predates `baseline_commit` and reads as an unowned write from no lane.
3. Do not ask the user for agents. Each lane runs the agent of the plan, which
   `validate-plan.sh` already checked against `agents.allowlist`. A user override arrives as
   `--agent LANE=AGENT` and must be one line of that file.
4. On `--dry-run`, run `init-run.sh ... --dry-run`, show its output, and stop.

## Phase 1 — Contract and shared files, then scaffold and launch

1. Materialize the contract file and every `shared_read_only` path and commit them. They are
   committed before fanout and are read-only afterwards; `init-run.sh` refuses to start
   otherwise.
2. `init-run.sh PLAN RUN_DIR CWD ORCH_SURFACE [--max-rounds N] [--agent LANE=AGENT]...`
   validates the plan, records `baseline_commit`, and writes `manifest.json` (round 1,
   max 3 rounds by default), `events.jsonl`, `lanes/<lane>/replies/` and the `launch/`
   directory: one rendered brief per lane (tasks, owns, test command, contract, script
   paths), the worker rules, and the agent and session id of each lane. It refuses a
   `RUN_DIR` that already holds a run.
3. `orca-launch.sh RUN_DIR` opens one Orca terminal per lane in the run's workspace
   (`orca worktree current`) and runs `worker-loop.sh` in it. Outside Orca, start
   `worker-loop.sh RUN_DIR LANE` in any terminal, or with `nohup` (README, *Without Orca*).

## Phase 2 — Monitor and react

Hold a `Monitor` on `monitor-events.sh RUN_DIR`, in a loop. Branch on the JSON `.type`, never
the exit code: `timeout` and `monitor_error` exit 1, everything else exits 0. The filter covers
the happy path and the failure path alike: `waiting`, `blocked`, `question`, `done` — and
`invalid_event`, `vanished_pane`, `fatal_signature`, `monitor_error`, `timeout`. A filter that
knows only the first four goes silent on a crash, and silence reads as "still working".

**Acknowledge each event trigger after you acted on it:** `monitor-events.sh RUN_DIR --ack
<seq>`. Until then every call returns the same trigger, so nothing is lost when you crash
between the trigger and the reply.

- **`question`** — answer from the plan or the contract when they decide it. Otherwise post it
  to the run's Inbox thread with `Holds up: lane <LANE>`, ack it, and keep the other lanes
  running (`~/.claude/skills/_shared/inbox.md`). Use `AskUserQuestion` only when every lane is
  blocked or the Inbox is absent. Send the answer with `reply.sh RUN_DIR LANE "<answer>"`.
- **`waiting`** — read `board.sh RUN_DIR` and wake the lane only when every lane in its
  `depends_on` has emitted `done`. An unsent wake strands the lane: it is an incident.
- **`blocked` — contract drift.** A worker blocked on the contract means the contract is
  wrong. A contract change goes to `AskUserQuestion` first (`_shared/after-approval.md`).
  After approval: tell the affected lanes to pause, edit the contract,
  bump its semantic version, commit it, run `contract-bump.sh RUN_DIR <version>`, then `reply.sh RUN_DIR --all
  "<new version + summary>"`. The bump records the approved checkpoint that the gate compares
  the contract against.
- **`done`** — record it; once every lane emitted `done` in this round, gate the round.
- **`invalid_event` / `fatal_signature` / `monitor_error`** — investigate the lane
  (`board.sh --lane LANE`, `lanes/<lane>/worker.log`) before you restart or escalate.
- **`vanished_pane`** — the worker loop died. Relaunch it with `orca-launch.sh RUN_DIR LANE`;
  it resumes the same session and delivers the replies that waited on disk.
- **`timeout`** — call `monitor-events.sh` again unless the silence looks like a stall.

`decision` events never interrupt a round. When a lane makes a real design choice, tell it to
record it with `decision.sh`, and add the `D-NNN` row to the plan's `## Deviations` yourself
(`_shared/spec-evidence.md` §3) — the run-state check accepts deviation-only plan edits.
Record your own decisions in `RUN_DIR/decisions.md`.

## Phase 3 — Round gate and round review

Once every lane emitted `done` for the round, run `round-gate.sh RUN_DIR ROUND --json`. It
checks, cheapest first: round bound and retry budget → round complete → lane tests →
acceptance commands → contract (`validate-contract.sh`) → run state (`validate-run-state.sh`).

**A failing `round-gate.sh` JSON is a hard gate: read the failed item, route the fix to the
owning lane with `reply.sh`, rerun the gate — never advance the round on a failing gate.**
`warn` items never block, but read each attribution warning before you commit. After 3 failed
gates of one round, the gate refuses the round: `AskUserQuestion`.

When the round passes, commit it (`git add -A && git commit`). Then review it report-only:
`Skill(skill="deep-review", args="default --scope <previous round commit>..HEAD --no-fix
--no-simplify")`. Route each CRITICAL, HIGH and MEDIUM fix to the owning lane, gate, commit.
Round 1 gets orchestrator review before anything reaches the human. Then bump
`manifest.json`'s `round` and start the next round, or go to Phase 4.

**After `max_rounds` rounds, stop and `AskUserQuestion`.** `round-gate.sh` refuses a round above
the cap on its own.

## Phase 4 — The shared chain, through the lanes

Run steps 2 to 9 of `~/.claude/skills/_shared/after-approval.md` in order, unattended, with
its `/deep-execute` routing: every `/deep-review` runs `--no-fix --no-simplify`, and every fix
from review or QA goes to the owning lane with `reply.sh`, then `round-gate.sh`, then a
commit. A file that no lane owns goes to a fresh implementer. Mark the phases with
`set-phase.sh RUN_DIR review|qa|delivery` as you reach steps 2, 3 and 7. Record each landed and
rejected finding with `decision.sh` while it is still true.

Before step 7, freeze: commit, record the full `git rev-parse HEAD`, and run `plan-stamp.sh
check PLAN`. Never finish on a changed plan or on stale QA evidence. Open the PR with
`--no-watch`, so the report comes before the watch.

## Phase 5 — Run report (step 8 of the chain)

```bash
build-run-report.sh RUN_DIR --final-sha <full-sha> \
  --review ~/.claude/deep-review-runs/<RUN_ID>/report.md --qa <qa-index.html> --pr <pr-url>
```

It writes `RUN_DIR/report/index.html` from the run directory alone: what was built, the
lanes, every recorded decision, `decisions.md`, the `D-NNN` deviations, drift, the board and
timeline, review, QA, open findings and the PR. Omit `--review`/`--qa`/`--pr` only when that
artifact does not exist; the page says so. **Do not hand-write or supplement this page from
memory.** A decision no one recorded is absent from it, and that absence is the truthful
output. Close with `finish-run.sh RUN_DIR [--qa PATH]`, which refuses a missing or unrendered
report. Send the report summary to the run's Inbox thread with `report/index.html` in
`attachments` (`_shared/inbox.md`). Then start the PR watch (step 9) and leave the lane loops
alive; teardown (`lanes/<lane>/stop`) is a separate step the user confirms.

## Resume (`--resume RUN_DIR`)

Reconstructible from disk: `manifest.json` (round, `max_rounds`, contract, checkpoint), the
launch manifest (agents, session ids), the event history via `board.sh`, every unacknowledged
trigger, and every round committed to git. **Not** reconstructible: whether a lane's process
is still alive and mid-edit — the last event proves only what the lane last reported.

1. Never run `init-run.sh` again; it refuses an existing run.
2. Run `run-status.sh RUN_DIR`. Relaunch each `dead` lane with `orca-launch.sh RUN_DIR LANE`.
3. Restart the `Monitor`. Its first liveness probe runs at once, and it replays every
   unacknowledged `question`, `waiting` and `blocked` event before anything new.

## Attribution is self-declared, not authenticated

`worker-<lane>.files.txt` is a log a lane writes about itself; any process with access to
`RUN_DIR` could log any path under any lane's name. Never describe it as proof of who wrote
what. The one enforced boundary is `changed-files-within-union` in `validate-run-state.sh`:
computed from git only, independent of any worker's claims. `changed-files-attributed-once`,
`worker-file-logs-valid` and `post-done-writes-absent` are advisory `warn` signals. Decision
records are the same: a lane's own account of its reasoning, not an audit trail.

## Rules

- **You orchestrate; you never implement.** The only way this session writes feature code is
  an explicit user request (deep-plan's option B), and a plan that reached `/deep-execute` did
  not make one.
- **Continuous run.** Phases 2 to 5 run end to end without a check-in. Stop only for a
  blocker no agent can decide: an ambiguous product decision, a contract change, a missing
  credential, a spent retry budget, the round or QA cap.
- Workers never run `git` (claude lanes have it as a disallowed tool);
  the orchestrator is the sole committer, between rounds.
- The plan's validated agent runs; `--agent` overrides it with a line of `agents.allowlist`.
- **Documentation is part of done.** The plan's `## Documentation impact` edits belong to a
  lane like any other file.
- **Use the code-intel tools, not `grep`.** Serena for symbols, GitNexus (`impact`,
  `detect_changes`) for blast radius, Graphify for cross-module questions. Tell every lane the
  same, and refresh the indexes after the run.
- The run report is built from the run directory by `build-run-report.sh`, never written by
  hand.
