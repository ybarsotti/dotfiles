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

0. **Wrap the run in `/goal`.** `/goal` is built into Claude Code and Codex; it keeps an agent
   driving toward a stated objective instead of stopping at the first natural pause. Open it
   before anything else, with the objective stated as the *finished* run — not the next step:

   ```text
   /goal Build <plan title> to a merged-ready state: every lane done and gated, /deep-review
   clean, QA green with evidence, PR open, run report built. Stop only on a blocker no agent
   can decide alone.
   ```

   The Rules' *Continuous run* clause says what not to stop for; `/goal` is what makes that
   hold when a round drags or a lane goes quiet. If `/goal` is unavailable in this harness, say
   so in one line and carry on under the rule alone — never treat its absence as permission to
   check in between phases.

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
5. **Open the diff pane** for the human: `wave-hunk CWD <baseline_commit>`. Pass the baseline,
   never the bare working tree — you commit between rounds. A failure here never blocks a lane.

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

`decision` events never reach you as a trigger — a lane recording why it chose something is
for Phase 5's report to read, not a reason to interrupt a round. But they are the one thing in
the run that dies with the worker session, so if a lane answers a `question` with a real design
choice, or reports working around something the plan missed, tell it in the `reply.sh` to record
that through `decision.sh` before moving on.

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

**Annotate the diff pane after that commit**, when Phase 1 opened one. Turn this round's
`decision.sh` entries into inline notes, one per decision, on the line it produced — the human
reads them while the next round runs. The `hunk-review` skill holds the commands; re-anchor
against a fresh `hunk session review` first, because a commit moves line numbers.

**After three rounds, stop and `AskUserQuestion`.** `round-gate.sh RUN_DIR 4` (or whatever
exceeds `max_rounds`) already refuses outright with its own escalation record instead of
running anything — obey it rather than calling it a fourth time on your own judgement.

## Phase 4 — Review, QA, gap fixes, frozen SHA, PR

These steps run **back to back, unattended** — no progress check-ins between them.

1. **Full peer review.** `Skill(skill="deep-review", args="default --reviewers 6 --ratio 3:3")`
   over the whole run's diff — the one thorough pass; every per-round `round-gate.sh` review
   was intentionally light. Route each required fix back through the **owning lane**
   (`reply.sh`), never your own editor; rerun the relevant verification, commit.
2. **Record it while it is still true.** Through `decision.sh`, per lane and for the review
   itself: what was built, which findings landed, which were rejected and why. A fix nobody
   recorded is a fix the Phase 5 report cannot show.
3. **QA agent** — its own agent, whose only job is to test. Pick the pass by what this machine
   actually has, checking in this order:
   - `~/.claude/skills/qa-testing/SKILL.md` exists → `Skill(skill="qa-testing")` in EXECUTE
     mode, driving a real browser through `agent-browser` over every flow and screen the plan
     touched, capturing screenshots and recordings. Give it the running URL and the current
     SHA; it verifies side effects in every system, not just the happy path on screen.
   - The plan's `## QA / test-execution` names a `qa-plan.yaml` → also run the scripted pass,
     after the exploratory one:
     `Skill(skill="qa-test-plan", args="--phase execute --qa-plan <path> --url <url> --commit <sha>")`.
   - **Neither available** → still QA it: dispatch a plain agent with `agent-browser` over the
     plan's flows, and say in the report which pass was skipped and why. A missing skill
     downgrades the evidence; it never cancels the QA step.
4. **Gap fixes by a different agent.** The agent that tested never fixes what it found — hand
   each gap, with its evidence and reproduction, to the owning lane (or a fresh implementer
   once the lanes are torn down), record the fix, then re-run the QA agent. A gap closes when
   QA says so, not when the fixer does. Loop 3 → 4 until QA is clean, capped at 3 QA rounds;
   at the cap, `AskUserQuestion` with the surviving findings.
5. **Freeze.** Commit, record the full `git rev-parse HEAD`. QA evidence binds the commit it
   ran against — any later change invalidates it. Never finish on missing, blocked or stale
   evidence; surface a blocker when the URL or the commit proof is unavailable.
6. **Open the PR.** `Skill(skill="pr-description", args="--plan <plan.md> --ticket <KEY-123> --evidence <qa-index.html>")`
   — requirements reconciled against the finished diff, Mermaid, key decisions, and the
   **evidence** from step 3: screenshots for a changed screen, a GIF or recording for a changed
   flow. Keep the returned PR URL for Phase 5.

## Phase 5 — Run report

Everything the run knows about itself is scattered across `manifest.json`, `events.jsonl`, the
per-lane decision records, the plan and git. Build the single readable artifact from it — last,
after the SHA is frozen and QA has run, so it reports the finished run rather than a snapshot
of one mid-flight:

```bash
build-run-report.sh RUN_DIR \
  --final-sha <full-sha> \
  --review ~/.claude/deep-review-runs/<RUN_ID>/report.md \
  --qa <path-to-qa-index.html> \
  --pr <pr-url>
```

It writes `RUN_DIR/report/index.html` — a self-contained page covering what was built
(diffstat baseline→final), the lane table with `owns`/`depends_on`, every decision, trade-off
and assumption the lanes recorded, the plan's own pre-implementation rationale, drift (contract
version moved, extra rounds, blocked events), the final board plus full event timeline, the
review and QA evidence (screenshots and recordings live in the linked QA report), and the PR.

Omit `--review`/`--qa`/`--pr` only when that artifact genuinely does not exist — the report says
so explicitly, which is the honest rendering. **Do not hand-write or supplement this page from
memory.** Every claim on it must come from a file in the run directory; a decision that no lane
recorded through `decision.sh` is one this report legitimately does not have.

Report run directory, final `board.sh` table, contract version, round count, final SHA, QA
verdict, the PR URL, and **both** HTML paths — the QA evidence report and this run report.
**Leave panes alive** — success does not tear down cmux state.

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

The same holds for decision records: `lanes/<lane>/decisions/*.json` is what a lane said about
its own reasoning. It is the best account of that reasoning anyone will get, and it is still an
account, not an audit trail.

## Rules

- **You orchestrate; you never implement.** Directing lanes, answering their questions, gating
  rounds, routing review and QA findings back to the owning agent, and committing — that is the
  whole job. The only way this session writes feature code is if the user explicitly asked for
  it (deep-plan's option B), and a plan that reached `/deep-execute` did not.
- **Continuous run.** Phases 2 → 5 run end to end without a check-in. Stop only for a genuine
  blocker no agent can decide alone — an ambiguous product decision, a missing credential, a
  hard-gate failure that survived a fix attempt, the round or QA cap. "This is a good moment to
  report progress" is not a blocker; neither is a failing test you can route back to its lane.
  Phase 0 wraps the run in `/goal` (below) so this survives a stall, not just your intent.
- **The tester never fixes; the fixer never signs off.** QA gaps go back to the owning lane or
  a fresh implementer, and the QA agent re-verifies the fix.
- **Documentation is part of done.** The plan's `## Documentation impact` lists what goes
  stale — those edits belong to a lane like any other file, and a round is not done with them
  outstanding. Same for a project `README`/`docs/` page the change contradicts.
- **Use the code-intel tools, not `grep`.** Serena (`find_symbol`, `find_referencing_symbols`,
  `replace_symbol_body`) for exact symbol work, GitNexus (`impact` before editing a symbol,
  `detect_changes` before committing) for blast radius, Graphify (`query`/`path`/`explain`,
  `GRAPH_REPORT.md`) for cross-module reasoning. Tell every lane the same in its brief, and
  refresh the indexes after the run (`gitnexus analyze`, `graphify update .`).
- Workers never run `git` — the orchestrator is the sole committer, between rounds.
- The contract and shared files are committed before fanout and are read-only afterwards.
- A failing `round-gate.sh` JSON is a hard gate — read it, fix, rerun, never advance.
- The plan suggests a lane's agent; `AskUserQuestion` confirms it against `agents.allowlist`.
- Round 1 gets orchestrator review before anything reaches the human.
- After three rounds, stop and `AskUserQuestion`.
- The run report is built from the run directory by `build-run-report.sh`, never written by
  hand — an unrecorded decision is absent from it, and that absence is the truthful output.
- The run ends with a PR open, evidence attached, and the report linking both.
