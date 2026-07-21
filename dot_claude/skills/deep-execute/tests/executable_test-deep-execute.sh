#!/usr/bin/env bash
# Test suite for the deep-execute run-state primitives: event.sh's atomic
# concurrent append, board.sh's fold-to-latest render, init-run.sh's plan-to-
# manifest scaffolding, and validate-run-state.sh's boundary enforcement —
# the script the whole lane-parallel safety model rests on.

set -eufo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
# shellcheck source=/dev/null
. "${ROOT}/dot_claude/skills/_shared/executable_assert.sh"

EVENT="${ROOT}/dot_claude/skills/deep-execute/scripts/executable_event.sh"
BOARD="${ROOT}/dot_claude/skills/deep-execute/scripts/executable_board.sh"
INIT_RUN="${ROOT}/dot_claude/skills/deep-execute/scripts/executable_init-run.sh"
VALIDATE_STATE="${ROOT}/dot_claude/skills/deep-execute/scripts/executable_validate-run-state.sh"
MONITOR="${ROOT}/dot_claude/skills/deep-execute/scripts/executable_monitor-events.sh"
REPLY="${ROOT}/dot_claude/skills/deep-execute/scripts/executable_reply.sh"
VALIDATE_CONTRACT="${ROOT}/dot_claude/skills/deep-execute/scripts/executable_validate-contract.sh"
ROUND_GATE="${ROOT}/dot_claude/skills/deep-execute/scripts/executable_round-gate.sh"
WORKER_PROMPT="${ROOT}/dot_claude/skills/deep-execute/templates/worker-system-prompt.txt"
FIXTURE_PLAN="${ROOT}/dot_claude/skills/deep-execute/tests/fixtures/init-run-plan.md"
SKILL_MD="${ROOT}/dot_claude/skills/deep-execute/SKILL.md"
README_MD="${ROOT}/dot_claude/skills/deep-execute/README.md"
COMMAND_MD="${ROOT}/dot_claude/commands/deep-execute.md"

assert_exit 0 test -f "$EVENT"
assert_exit 0 test -f "$BOARD"
assert_exit 0 test -f "$INIT_RUN"
assert_exit 0 test -f "$VALIDATE_STATE"
assert_exit 0 test -f "$MONITOR"
assert_exit 0 test -f "$REPLY"
assert_exit 0 test -f "$VALIDATE_CONTRACT"
assert_exit 0 test -f "$ROUND_GATE"
assert_exit 0 test -f "$WORKER_PROMPT"
assert_exit 0 test -f "$FIXTURE_PLAN"

# ─── event.sh: type/newline/size rejection ─────────────────────────────────

E1=$(mktemp -d)
assert_exit 0 "$EVENT" "$E1" backend "Task 9" task_start "starting"
assert_exit 1 "$EVENT" "$E1" backend "Task 9" bogus "unknown type"
assert_exit 1 "$EVENT" "$E1" backend "Task 9" progress "$(printf 'a\nb')"

printf -v BIG_MSG '%*s' 4090 ""
BIG_MSG="${BIG_MSG// /x}"
assert_exit 1 "$EVENT" "$E1" backend "Task 9" progress "$BIG_MSG"

BIG_STDERR=$("$EVENT" "$E1" backend "Task 9" progress "$BIG_MSG" 2>&1 >/dev/null || true)
assert_contains "$BIG_STDERR" "bytes" "oversized event names the byte count"

# Only the one legitimate event from above should have landed.
assert_eq "$(wc -l <"${E1}/events.jsonl" | tr -d ' ')" 1 "rejected events never reach the file"

# --files appends to worker-<lane>.files.txt in the same call
assert_exit 0 "$EVENT" "$E1" backend "Task 9" progress "wrote a file" --files "backend/a.sh" "backend/b.sh"
assert_eq "$(cat "${E1}/worker-backend.files.txt")" "$(printf 'backend/a.sh\nbackend/b.sh')" \
  "--files appends both paths"

# ─── event.sh: 50 genuinely concurrent appends ─────────────────────────────
# Each iteration backgrounds a fresh event.sh process (its own jq/date/printf
# subprocesses) with no synchronization between them but the shared file's
# O_APPEND fd — this races for real, not just in appearance.

CONC=$(mktemp -d)
for i in $(seq 1 50); do
  "$EVENT" "$CONC" backend "Task 9" progress "event-$i" &
done
wait

assert_eq "$(wc -l <"${CONC}/events.jsonl" | tr -d ' ')" 50 "50 concurrent appends produced exactly 50 lines"
assert_exit 0 jq -e . "${CONC}/events.jsonl"

BAD_LINES=0
while IFS= read -r line; do
  printf '%s' "$line" | jq -e . >/dev/null 2>&1 || BAD_LINES=$((BAD_LINES + 1))
done <"${CONC}/events.jsonl"
assert_eq "$BAD_LINES" 0 "every one of the 50 lines is individually valid JSON (no interleaving)"

DISTINCT_MSGS=$(jq -r '.msg' "${CONC}/events.jsonl" | sort -u | wc -l | tr -d ' ')
assert_eq "$DISTINCT_MSGS" 50 "all 50 distinct messages present — nothing dropped, truncated, or merged"

# ─── board.sh: fold to latest per (lane, task), --lane filter, empty log ───

BOARD_RUN=$(mktemp -d)
: >"${BOARD_RUN}/events.jsonl"
assert_exit 0 "$EVENT" "$BOARD_RUN" backend "Task A" task_start "starting"
assert_exit 0 "$EVENT" "$BOARD_RUN" backend "Task A" progress "halfway"
assert_exit 0 "$EVENT" "$BOARD_RUN" frontend "Task B" task_start "starting"
assert_exit 0 "$EVENT" "$BOARD_RUN" frontend "Task B" "done" "finished"

TABLE=$("$BOARD" "$BOARD_RUN")
assert_contains "$TABLE" "| backend | Task A | progress | halfway |" "board folds to the latest backend event"
assert_contains "$TABLE" "| frontend | Task B | done | finished |" "board folds to the latest frontend event"

FILTERED=$("$BOARD" "$BOARD_RUN" --lane backend)
assert_contains "$FILTERED" "| backend | Task A | progress | halfway |" "--lane keeps the matching row"
assert_eq "$(printf '%s' "$FILTERED" | grep -c frontend || true)" "0" "--lane filters out other lanes"

EMPTY_RUN=$(mktemp -d)
: >"${EMPTY_RUN}/events.jsonl"
EMPTY_TABLE=$("$BOARD" "$EMPTY_RUN")
assert_eq "$EMPTY_TABLE" "$(printf '| lane | task | status | message |\n|---|---|---|---|')" \
  "an empty event log renders the header only"

NO_FILE_RUN=$(mktemp -d)
NO_FILE_TABLE=$("$BOARD" "$NO_FILE_RUN")
assert_eq "$NO_FILE_TABLE" "$EMPTY_TABLE" "a missing events.jsonl also renders the header only"

# ─── worker system prompt: behavioral spec pinned ──────────────────────────

PROMPT_TEXT=$(cat "$WORKER_PROMPT")
assert_contains "$PROMPT_TEXT" 'Never run `git`' "prompt forbids git"
assert_contains "$PROMPT_TEXT" 'worker-<lane>.files.txt' "prompt names the attribution log"
assert_contains "$PROMPT_TEXT" 'event.sh RUN_DIR LANE TASK TYPE MSG' "prompt gives the event.sh interface"
assert_contains "$PROMPT_TEXT" 'board.sh RUN_DIR [--lane LANE]' "prompt gives the board.sh interface"
assert_contains "$PROMPT_TEXT" 'emit `waiting` and STOP' "prompt states finishing-early behavior"
assert_contains "$PROMPT_TEXT" 'Do not poll' "prompt forbids polling"

# ─── init-run.sh + validate-run-state.sh: scratch repo fixture ─────────────
# `new_repo` builds an isolated git repo matching the fixture plan's lane
# layout (backend/**, frontend/**, dot_claude/skills/deep-review/**, plus the
# orchestrator-owned contract/README and an unowned misc.txt for the rename
# test) so every scenario below runs against a real git history instead of
# the actual chezmoi repo.

new_repo() {
  local repo
  repo=$(mktemp -d)
  git -C "$repo" init --quiet -b main
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name "deep-execute test"
  mkdir -p "$repo/backend" "$repo/frontend" "$repo/dot_claude/skills/deep-review"
  printf '{"type":"object"}\n' >"$repo/contract.schema.json"
  printf '# readme\n' >"$repo/README.md"
  printf '#!/usr/bin/env bash\n' >"$repo/backend/service.sh"
  printf '#!/usr/bin/env bash\n' >"$repo/frontend/app.sh"
  printf '#!/usr/bin/env bash\n' >"$repo/dot_claude/skills/deep-review/checklist.sh"
  printf 'unowned by any worker lane\n' >"$repo/misc.txt"
  git -C "$repo" add -A
  git -C "$repo" commit --quiet -m init
  printf '%s' "$repo"
}

# new_run REPO — echoes a fresh RUN_DIR after scaffolding it with init-run.sh.
# Deliberately does NOT call assert_exit here: this runs inside a $(...)
# capture at every call site, and assert_exit's own "ok"/"FAIL" line would
# otherwise become part of the captured RUN_DIR string. Exit-code coverage
# for init-run.sh itself lives in the explicit happy-path check below,
# outside any capture.
new_run() {
  local repo="$1" run_dir
  run_dir="$(mktemp -d)/run"
  "$INIT_RUN" "$FIXTURE_PLAN" "$run_dir" "$repo" "surface:test" >/dev/null 2>&1 || true
  printf '%s' "$run_dir"
}

detail_of() {
  # detail_of JSON ITEM — the .detail of the named record.
  jq -r --arg item "$2" '.[] | select(.item == $item) | .detail' <<<"$1"
}
status_of() {
  jq -r --arg item "$2" '.[] | select(.item == $item) | .status' <<<"$1"
}

# ─── init-run.sh happy path: real parser output -> a manifest that ────────
# validates against schemas/run-state.schema.json (dogfooded via
# validate-run-state.sh's own manifest-schema-valid check, rather than a
# second hand-rolled schema checker in the test).

REPO_HAPPY=$(new_repo)
RUN_HAPPY="$(mktemp -d)/run"
assert_exit 0 "$INIT_RUN" "$FIXTURE_PLAN" "$RUN_HAPPY" "$REPO_HAPPY" "surface:test"

assert_exit 0 test -f "${RUN_HAPPY}/manifest.json"
assert_exit 0 jq -e . "${RUN_HAPPY}/manifest.json"
assert_eq "$(jq -r '.schema_version' "${RUN_HAPPY}/manifest.json")" "1.0.0" "manifest schema_version"
assert_eq "$(jq -r '.contract.path' "${RUN_HAPPY}/manifest.json")" "contract.schema.json" "manifest contract path"
assert_eq "$(jq -r '.contract.sha256' "${RUN_HAPPY}/manifest.json" | wc -c | tr -d ' ')" 65 \
  "manifest contract sha256 is a real 64-hex-char digest (+ newline)"
assert_eq "$(jq -c '[.workers[].lane] | sort' "${RUN_HAPPY}/manifest.json")" '["backend","frontend","review"]' \
  "manifest workers = non-orchestrator lanes only"
assert_eq "$(jq -r '.baseline_commit' "${RUN_HAPPY}/manifest.json")" "$(git -C "$REPO_HAPPY" rev-parse HEAD)" \
  "baseline_commit == git rev-parse HEAD at init time"
assert_exit 0 test -f "${RUN_HAPPY}/events.jsonl"
assert_exit 0 test -f "${RUN_HAPPY}/worker-backend.files.txt"
assert_exit 0 test -f "${RUN_HAPPY}/lanes/backend/reply.md"
assert_exit 0 test -f "${RUN_HAPPY}/cmux/manifest.json"
assert_exit 0 test -f "${RUN_HAPPY}/cmux/worker-backend.prompt.md"

HAPPY_JSON=$("$VALIDATE_STATE" "$RUN_HAPPY" --json)
assert_exit 0 "$VALIDATE_STATE" "$RUN_HAPPY" --json
assert_eq "$(status_of "$HAPPY_JSON" manifest-schema-valid)" pass "fresh manifest validates against the schema"
assert_eq "$(status_of "$HAPPY_JSON" changed-files-within-union)" pass "fresh run: nothing changed yet"
assert_eq "$(status_of "$HAPPY_JSON" contract-untouched)" pass "fresh run: contract sha matches"
assert_eq "$(jq '[.[] | select(.status=="fail")] | length' <<<"$HAPPY_JSON")" 0 "fresh run: zero failing items"

# ─── Boundary 1: worker-<lane>.files.txt attribution-input validity ───────
# Two distinct ways a log entry can be bogus (the brief's literal case is
# the first): a path outside the logging lane's own ownership at all, and a
# path that IS inside its ownership but was never actually written (no
# matching git change) — worker-file-logs-valid must catch both, by name.

REPO1=$(new_repo)
RUN1=$(new_run "$REPO1")
printf 'outside/file.txt\n' >"${RUN1}/worker-backend.files.txt"
printf 'backend/never-written.sh\n' >>"${RUN1}/worker-backend.files.txt"
J1=$("$VALIDATE_STATE" "$RUN1" --json) || true
assert_exit 1 "$VALIDATE_STATE" "$RUN1" --json
assert_eq "$(status_of "$J1" worker-file-logs-valid)" fail "bogus log entries fail worker-file-logs-valid"
D1=$(detail_of "$J1" worker-file-logs-valid)
assert_contains "$D1" "outside/file.txt(outside-own-ownership)" \
  "a path outside the lane's own ownership is named with that exact reason"
assert_contains "$D1" "backend/never-written.sh(logged-but-never-actually-changed)" \
  "a path inside ownership but never written is named with that exact reason"
assert_contains "$D1" "backend:" "diagnostic names the offending lane"

# ─── Boundary 2: worker writes outside its owns (real, untracked write) ───

REPO2=$(new_repo)
RUN2=$(new_run "$REPO2")
mkdir -p "${REPO2}/rogue"
printf 'x\n' >"${REPO2}/rogue/file.txt"
printf 'rogue/file.txt\n' >"${RUN2}/worker-backend.files.txt"
assert_eq "$(git -C "$REPO2" status --porcelain)" "?? rogue/" "the write is untracked in the scratch repo"
J2=$("$VALIDATE_STATE" "$RUN2" --json) || true
assert_exit 1 "$VALIDATE_STATE" "$RUN2" --json
assert_eq "$(status_of "$J2" changed-files-owned)" fail "an untracked write outside every lane's owns fails changed-files-owned"
assert_contains "$(detail_of "$J2" changed-files-owned)" "rogue/file.txt" "diagnostic names the offending path"
assert_contains "$(detail_of "$J2" changed-files-owned)" "matches=0" "diagnostic shows zero owning lanes"
assert_eq "$(status_of "$J2" changed-files-within-union)" fail "the same violation is caught by the baseline-diff union too"

# ─── Boundary 3: a worker that COMMITS an out-of-ownership write — the ────
# worktree goes clean, but the baseline diff still catches it. The write
# lands inside `review`'s own owned territory (so raw path-ownership alone
# would wave it through); it is the ATTRIBUTION check — no lane's files.txt
# logs it — that catches an unattributed write smuggled in via a commit.

REPO3=$(new_repo)
RUN3=$(new_run "$REPO3")
git -C "$REPO3" commit --quiet --allow-empty -m base
git -C "$REPO3" checkout --quiet -b worker-writes
mkdir -p "${REPO3}/dot_claude/skills/deep-review"
printf 'x\n' >"${REPO3}/dot_claude/skills/deep-review/stolen.md"
git -C "$REPO3" add -A
git -C "$REPO3" commit --quiet -m "worker commit"
assert_eq "$(git -C "$REPO3" status --porcelain)" "" "worktree is clean after the worker's own commit"

J3=$("$VALIDATE_STATE" "$RUN3" --json) || true
assert_exit 1 "$VALIDATE_STATE" "$RUN3" --json
assert_eq "$(status_of "$J3" changed-files-owned)" pass \
  "status-only check sees nothing — this is exactly the gap changed-files-within-union exists to close"
assert_eq "$(status_of "$J3" changed-files-attributed-once)" fail \
  "the baseline-diff union still shows the committed file; no lane logged it"
assert_contains "$(detail_of "$J3" changed-files-attributed-once)" "stolen.md" "diagnostic names the offending path"
assert_contains "$(detail_of "$J3" changed-files-attributed-once)" "attributed=0" "diagnostic shows zero attributions"

# ─── Boundary 4: a path with spaces and unicode is parsed and named intact ─

REPO4=$(new_repo)
RUN4=$(new_run "$REPO4")
mkdir -p "${REPO4}/rogue"
UNI_PATH='rogue/héllo wörld 世界.txt'
printf 'x\n' >"${REPO4}/${UNI_PATH}"
J4=$("$VALIDATE_STATE" "$RUN4" --json) || true
assert_exit 1 "$VALIDATE_STATE" "$RUN4" --json
assert_contains "$(detail_of "$J4" changed-files-within-union)" "$UNI_PATH" \
  "a path with spaces and unicode survives -z parsing and is named verbatim"

# ─── Boundary 5: a rename (--no-renames -> delete + add); the deleted ─────
# source is an unowned file, so it alone must fail changed-files-within-union even
# though the destination lands inside backend's own owns.

REPO5=$(new_repo)
RUN5=$(new_run "$REPO5")
git -C "$REPO5" mv misc.txt backend/renamed.txt
git -C "$REPO5" commit --quiet -m rename
J5=$("$VALIDATE_STATE" "$RUN5" --json) || true
assert_exit 1 "$VALIDATE_STATE" "$RUN5" --json
assert_eq "$(status_of "$J5" changed-files-within-union)" fail "a rename whose source is unowned fails changed-files-within-union"
assert_contains "$(detail_of "$J5" changed-files-within-union)" "misc.txt" "diagnostic names the deleted (source) path"

# ─── Boundary 6: a file touched by two lanes (attribution ambiguity) ──────

REPO6=$(new_repo)
RUN6=$(new_run "$REPO6")
printf 'x\n' >"${REPO6}/backend/shared-ish.txt"
printf 'backend/shared-ish.txt\n' >"${RUN6}/worker-backend.files.txt"
printf 'backend/shared-ish.txt\n' >"${RUN6}/worker-frontend.files.txt"
J6=$("$VALIDATE_STATE" "$RUN6" --json) || true
assert_exit 1 "$VALIDATE_STATE" "$RUN6" --json
assert_eq "$(status_of "$J6" changed-files-attributed-once)" fail "a path logged by two lanes fails attribution"
assert_contains "$(detail_of "$J6" changed-files-attributed-once)" "shared-ish.txt" "diagnostic names the ambiguous path"
assert_contains "$(detail_of "$J6" changed-files-attributed-once)" "attributed=2" "diagnostic shows two attributions"

# ─── Boundary 7: the contract file is modified ─────────────────────────────

REPO7=$(new_repo)
RUN7=$(new_run "$REPO7")
printf '{"type":"object","extra":true}\n' >"${REPO7}/contract.schema.json"
J7=$("$VALIDATE_STATE" "$RUN7" --json) || true
assert_exit 1 "$VALIDATE_STATE" "$RUN7" --json
assert_eq "$(status_of "$J7" contract-untouched)" fail "a modified contract fails contract-untouched"
assert_contains "$(detail_of "$J7" contract-untouched)" "sha256" "diagnostic cites the sha256 mismatch"

# ─── Boundary 8: a shared read-only file is modified ───────────────────────

REPO8=$(new_repo)
RUN8=$(new_run "$REPO8")
printf '# readme, but edited\n' >"${REPO8}/README.md"
J8=$("$VALIDATE_STATE" "$RUN8" --json) || true
assert_exit 1 "$VALIDATE_STATE" "$RUN8" --json
assert_eq "$(status_of "$J8" shared-files-untouched)" fail "a modified shared file fails shared-files-untouched"
assert_contains "$(detail_of "$J8" shared-files-untouched)" "README.md" "diagnostic names the offending shared path"

# ─── Boundary 9: forged attribution — the union check still passes (the ────
# write is genuinely inside `review`'s own territory), because attribution
# cannot be authenticated from inside one shared worktree. This is the
# scenario the Task 9 review found: `backend` commits a file that lives in
# `review`'s owned dir, the worktree goes clean, then a forged entry is
# appended to `worker-review.files.txt` claiming `review` logged it. Every
# check that only knows "is this self-consistent" (worker-file-logs-valid,
# changed-files-attributed-once) is blind to the forgery and passes — the
# split this task hardens is that their pass detail says so, so a reader of
# the JSON output does not mistake "passed" for "attribution is proven".

REPO9=$(new_repo)
RUN9=$(new_run "$REPO9")
git -C "$REPO9" commit --quiet --allow-empty -m base
git -C "$REPO9" checkout --quiet -b forged-attribution
printf 'x\n' >"${REPO9}/dot_claude/skills/deep-review/stolen2.md"
git -C "$REPO9" add -A
git -C "$REPO9" commit --quiet -m "backend commits into review's territory"
assert_eq "$(git -C "$REPO9" status --porcelain)" "" "worktree is clean after the forged commit"
printf 'dot_claude/skills/deep-review/stolen2.md\n' >>"${RUN9}/worker-review.files.txt"

J9=$("$VALIDATE_STATE" "$RUN9" --json)
assert_exit 0 "$VALIDATE_STATE" "$RUN9" --json
assert_eq "$(status_of "$J9" changed-files-within-union)" pass \
  "the hard union check passes — the write IS genuinely inside review's owned territory"
assert_eq "$(status_of "$J9" changed-files-attributed-once)" pass \
  "a single self-consistent forged log entry is indistinguishable from a true one — this check cannot catch it"
assert_eq "$(status_of "$J9" worker-file-logs-valid)" pass \
  "same blindness: the forged entry is inside review's own ownership and reflects a real (if not review-made) change"
assert_contains "$(detail_of "$J9" changed-files-attributed-once)" "self-declared" \
  "the passing attribution check's own detail says it is self-declared, not authenticated"
assert_contains "$(detail_of "$J9" worker-file-logs-valid)" "not proof of who wrote it" \
  "the passing log-validity check's own detail says the same"
assert_contains "$(detail_of "$J9" changed-files-within-union)" "computed from git only" \
  "the check that actually blocks describes itself as independent of any self-reported attribution"

# ─── Boundary 10: path-traversal guard is segment-based, not substring ────
# `foo..bar.txt` is a legitimate filename that merely contains two dots —
# it must be accepted. `../escape.txt` and `a/../../b` are genuine
# traversal and must be rejected, regardless of whether they're otherwise
# well-formed repo-relative-looking strings.

REPO10=$(new_repo)
RUN10=$(new_run "$REPO10")
printf 'x\n' >"${REPO10}/backend/foo..bar.txt"
printf 'backend/foo..bar.txt\n' >"${RUN10}/worker-backend.files.txt"
printf '../escape.txt\n' >>"${RUN10}/worker-backend.files.txt"
printf 'backend/a/../../b\n' >>"${RUN10}/worker-backend.files.txt"

J10=$("$VALIDATE_STATE" "$RUN10" --json) || true
assert_exit 1 "$VALIDATE_STATE" "$RUN10" --json
D10=$(detail_of "$J10" worker-file-logs-valid)
assert_contains "$D10" "../escape.txt(path-traversal)" "a leading ../ segment is rejected as path-traversal"
assert_contains "$D10" "backend/a/../../b(path-traversal)" "an embedded ../../ is rejected as path-traversal"
assert_eq "$(printf '%s' "$D10" | grep -c 'foo\.\.bar\.txt' || true)" "0" \
  "foo..bar.txt has no traversal segment and is not flagged at all — it was legitimately written and logged"

# ─── Boundary 11: post-done-writes-absent flags without hard-failing ──────
# `backend` emits `done`, then (properly logged, so every other check stays
# green) writes into its own territory again with an mtime manufactured to
# land after that `done` event. The new check must flag it — but only as
# "warn", never contributing to the exit code by itself.

REPO11=$(new_repo)
RUN11=$(new_run "$REPO11")
assert_exit 0 "$EVENT" "$RUN11" backend "Task 9" "done" "nothing left this round"
printf 'more work after done\n' >>"${REPO11}/backend/service.sh"
printf 'backend/service.sh\n' >>"${RUN11}/worker-backend.files.txt"
FUTURE_TS=$(date -v+1H +%Y%m%d%H%M.%S 2>/dev/null || date -d '+1 hour' +%Y%m%d%H%M.%S)
touch -t "$FUTURE_TS" "${REPO11}/backend/service.sh"

J11=$("$VALIDATE_STATE" "$RUN11" --json)
assert_exit 0 "$VALIDATE_STATE" "$RUN11" --json
assert_eq "$(status_of "$J11" post-done-writes-absent)" warn \
  "a lane writing in its own territory after its own done event is flagged, status warn not fail"
assert_contains "$(detail_of "$J11" post-done-writes-absent)" "backend:backend/service.sh" \
  "diagnostic names the offending lane and path"
assert_eq "$(jq '[.[] | select(.status=="fail")] | length' <<<"$J11")" 0 \
  "no item actually failed — post-done-writes-absent alone never trips the fail count"

# ═══════════════════════════════════════════════════════════════════════════
# Task 10: monitor-events.sh, reply.sh, validate-contract.sh, round-gate.sh
# ═══════════════════════════════════════════════════════════════════════════

# ─── monitor-events.sh: a minimal RUN_DIR is enough — it only reads ────────
# .workers[]?.lane from manifest.json (not the full run-state schema) and
# events.jsonl.
mon_run() {
  local d
  d=$(mktemp -d)
  printf '{"workers":[{"lane":"backend"},{"lane":"frontend"}]}\n' >"${d}/manifest.json"
  : >"${d}/events.jsonl"
  printf '%s' "$d"
}

# mon_run_with_surface — same, plus a cmux/manifest.json giving lane
# "backend" a real surface_ref, for the pane-health (vanished-pane /
# fatal-signature) triggers.
mon_run_with_surface() {
  local d
  d=$(mktemp -d)
  mkdir -p "${d}/cmux"
  printf '{"workers":[{"lane":"backend"}]}\n' >"${d}/manifest.json"
  printf '{"workers":[{"name":"backend","surface_ref":"surface:1"}]}\n' >"${d}/cmux/manifest.json"
  : >"${d}/events.jsonl"
  printf '%s' "$d"
}

# ─── Backlog drain: an event written BEFORE monitor-events.sh even starts ──
# must still produce a trigger — a bare `tail -n 0 -F` alone would miss it
# (see the script's own header for why the persisted watermark exists).
# This is the brief's own step-1 scenario, content-asserted field by field.

MON_WAIT=$(mon_run)
assert_exit 0 "$EVENT" "$MON_WAIT" frontend "Task 10" waiting "mock suite passed"
TRIGGER_WAIT=$("$MONITOR" "$MON_WAIT")
assert_eq "$(jq -r '.type' <<<"$TRIGGER_WAIT")" waiting "monitor-events.sh: a backlogged 'waiting' event produces a waiting trigger"
assert_eq "$(jq -r '.lane' <<<"$TRIGGER_WAIT")" frontend "monitor-events.sh: waiting trigger names the lane"
assert_eq "$(jq -r '.task' <<<"$TRIGGER_WAIT")" "Task 10" "monitor-events.sh: waiting trigger names the task"
assert_eq "$(jq -r '.msg' <<<"$TRIGGER_WAIT")" "mock suite passed" "monitor-events.sh: waiting trigger carries the event's own message"

MON_Q=$(mon_run)
assert_exit 0 "$EVENT" "$MON_Q" backend "Task 3" question "which endpoint shape?"
TRIGGER_Q=$("$MONITOR" "$MON_Q")
assert_eq "$(jq -r '.type' <<<"$TRIGGER_Q")" question "monitor-events.sh: a backlogged 'question' event produces a question trigger"
assert_eq "$(jq -r '.msg' <<<"$TRIGGER_Q")" "which endpoint shape?" "monitor-events.sh: question trigger carries the event's own message"

MON_B=$(mon_run)
assert_exit 0 "$EVENT" "$MON_B" backend "Task 4" blocked "need contract v1.0.1"
TRIGGER_B=$("$MONITOR" "$MON_B")
assert_eq "$(jq -r '.type' <<<"$TRIGGER_B")" blocked "monitor-events.sh: a backlogged 'blocked' event produces a blocked trigger"
assert_eq "$(jq -r '.lane' <<<"$TRIGGER_B")" backend "monitor-events.sh: blocked trigger names the lane"

MON_D=$(mon_run)
assert_exit 0 "$EVENT" "$MON_D" frontend "Task 5" "done" "nothing left this round"
TRIGGER_D=$("$MONITOR" "$MON_D")
assert_eq "$(jq -r '.type' <<<"$TRIGGER_D")" "done" "monitor-events.sh: a backlogged 'done' event produces a done trigger"

# task_start/task_done/progress are NOT triggers — the monitor must skip
# past them in the backlog and only fire on the real blocked event that
# follows.
MON_SKIP=$(mon_run)
assert_exit 0 "$EVENT" "$MON_SKIP" backend "Task 6" task_start "starting"
assert_exit 0 "$EVENT" "$MON_SKIP" backend "Task 6" progress "halfway"
assert_exit 0 "$EVENT" "$MON_SKIP" backend "Task 6" task_done "lane test passed"
assert_exit 0 "$EVENT" "$MON_SKIP" backend "Task 6" blocked "now blocked"
TRIGGER_SKIP=$("$MONITOR" "$MON_SKIP")
assert_eq "$(jq -r '.type' <<<"$TRIGGER_SKIP")" blocked \
  "monitor-events.sh: task_start/progress/task_done are skipped as non-triggers; the first real trigger in the backlog still fires"
assert_eq "$(jq -r '.msg' <<<"$TRIGGER_SKIP")" "now blocked" \
  "monitor-events.sh: the fired trigger is the blocked event, not an earlier informational one"

# ─── Invalid event line: malformed JSON, and well-formed JSON missing ──────
# required fields — both must be caught, by name, not silently skipped.

MON_INV1=$(mon_run)
printf 'not valid json\n' >>"${MON_INV1}/events.jsonl"
TRIGGER_INV1=$("$MONITOR" "$MON_INV1")
assert_eq "$(jq -r '.type' <<<"$TRIGGER_INV1")" invalid_event "monitor-events.sh: a line that isn't JSON at all produces an invalid_event trigger"
assert_contains "$(jq -r '.msg' <<<"$TRIGGER_INV1")" "not valid json" "monitor-events.sh: invalid_event's msg quotes the offending raw line"
assert_eq "$(jq -r '.lane' <<<"$TRIGGER_INV1")" null "monitor-events.sh: a line with no parseable lane names no lane"

MON_INV2=$(mon_run)
printf '{"lane":"backend","type":"waiting"}\n' >>"${MON_INV2}/events.jsonl"
TRIGGER_INV2=$("$MONITOR" "$MON_INV2")
assert_eq "$(jq -r '.type' <<<"$TRIGGER_INV2")" invalid_event "monitor-events.sh: valid JSON missing required fields (task, msg, ts) still fails the event schema"
assert_eq "$(jq -r '.lane' <<<"$TRIGGER_INV2")" backend "monitor-events.sh: when the lane field IS parseable, invalid_event still names it"

# ─── Live-follow: an event appended by ANOTHER process AFTER monitor ───────
# starts — proves the blocking `tail -F` path actually blocks and wakes,
# not just the backlog-drain path exercised above.

MON_LIVE=$(mon_run)
(
  sleep 1
  "$EVENT" "$MON_LIVE" backend "Task 7" "done" "arrived after monitor started"
) &
LIVE_BGPID=$!
TRIGGER_LIVE=$(MONITOR_LIVENESS_INTERVAL=5 MONITOR_MAX_WAIT=10 "$MONITOR" "$MON_LIVE")
wait "$LIVE_BGPID"
assert_eq "$(jq -r '.type' <<<"$TRIGGER_LIVE")" "done" "monitor-events.sh: an event appended after the monitor started is caught by the blocking tail -F, not just backlog drain"
assert_eq "$(jq -r '.msg' <<<"$TRIGGER_LIVE")" "arrived after monitor started" "monitor-events.sh: live-follow trigger carries the event's own message"

# ─── Startup race: an event appended in the window between "how far to ────
# resume from" and the tail attach itself must still be caught. This is the
# Task 10 review finding: an earlier version of this script snapshotted
# `wc -l` (the resume point), spent time on a `jq` LANES lookup, and only
# THEN attached `tail -n 0 -F` — a line appended in that gap landed past the
# snapshot's watermark AND before the attach, invisible to both, so a
# lane's own last event (blocked/waiting) could be lost and this call would
# idle out to `timeout`.
#
# MONITOR_TEST_DELAY_BEFORE_TAIL widens that exact window (it sleeps
# immediately before the real tail attach — see the script's own header) so
# the race is deterministic rather than a timing gamble: the background
# writer lands squarely inside the delay, not "probably before the script
# gets there." Against the pre-fix script (verified by hand, not shipped
# here — see the task's own report for the transcript) the same scenario,
# with an equivalent sleep inserted right after ITS `wc -l` snapshot,
# reliably produced `timeout`; the fix removes that snapshot entirely in
# favor of a single `tail -n +K -F` stream, so widening the delay here
# proves nothing is lost regardless of how long the gap is, not just that
# today's gap happens to be narrow.
MON_RACE=$(mon_run)
(
  sleep 0.3
  "$EVENT" "$MON_RACE" backend "Task 8" blocked "landed during the pre-tail delay"
) &
RACE_BGPID=$!
TRIGGER_RACE=$(MONITOR_TEST_DELAY_BEFORE_TAIL=1 MONITOR_LIVENESS_INTERVAL=2 MONITOR_MAX_WAIT=5 "$MONITOR" "$MON_RACE")
wait "$RACE_BGPID"
assert_eq "$(jq -r '.type' <<<"$TRIGGER_RACE")" blocked \
  "monitor-events.sh: an event written during the pre-attach delay is caught as a real trigger, not lost to timeout"
assert_eq "$(jq -r '.msg' <<<"$TRIGGER_RACE")" "landed during the pre-tail delay" \
  "monitor-events.sh: the startup-race trigger carries the event's own message, proving it was genuinely read (not a stale/default value)"

# ─── Vanished pane: capture-pane fails for the lane's surface_ref ──────────

MON_VANISHED=$(mon_run_with_surface)
CMUX_BIN_CRASH=$(mktemp -d)
cat >"${CMUX_BIN_CRASH}/cmux" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "${CMUX_BIN_CRASH}/cmux"
TRIGGER_VANISHED=$(PATH="${CMUX_BIN_CRASH}:${PATH}" MONITOR_LIVENESS_INTERVAL=1 MONITOR_MAX_WAIT=5 "$MONITOR" "$MON_VANISHED")
assert_eq "$(jq -r '.type' <<<"$TRIGGER_VANISHED")" vanished_pane "monitor-events.sh: capture-pane failing produces a vanished_pane trigger"
assert_eq "$(jq -r '.lane' <<<"$TRIGGER_VANISHED")" backend "monitor-events.sh: vanished_pane trigger names the lane"
assert_contains "$(jq -r '.msg' <<<"$TRIGGER_VANISHED")" "surface:1" "monitor-events.sh: vanished_pane trigger names the surface that failed"

# ─── Fatal signature: capture-pane succeeds but the NEW pane output ────────
# contains a known-fatal signature.

MON_FATAL=$(mon_run_with_surface)
CMUX_BIN_FATAL=$(mktemp -d)
cat >"${CMUX_BIN_FATAL}/cmux" <<'STUB'
#!/usr/bin/env bash
echo "some ordinary output"
echo "panic: something exploded"
exit 0
STUB
chmod +x "${CMUX_BIN_FATAL}/cmux"
TRIGGER_FATAL=$(PATH="${CMUX_BIN_FATAL}:${PATH}" MONITOR_LIVENESS_INTERVAL=1 MONITOR_MAX_WAIT=5 "$MONITOR" "$MON_FATAL")
assert_eq "$(jq -r '.type' <<<"$TRIGGER_FATAL")" fatal_signature "monitor-events.sh: a fatal signature in fresh pane output produces a fatal_signature trigger"
assert_eq "$(jq -r '.lane' <<<"$TRIGGER_FATAL")" backend "monitor-events.sh: fatal_signature trigger names the lane"
assert_contains "$(jq -r '.msg' <<<"$TRIGGER_FATAL")" "panic: something exploded" "monitor-events.sh: fatal_signature trigger quotes the matched line"

# ─── Bounded wait: nothing happens at all — must still emit a trigger ──────
# (never hang, never report success by silence) and this is the one path
# that exits nonzero.

MON_TIMEOUT=$(mktemp -d)
printf '{"workers":[]}\n' >"${MON_TIMEOUT}/manifest.json"
: >"${MON_TIMEOUT}/events.jsonl"
TIMEOUT_RC=0
TRIGGER_TIMEOUT=$(MONITOR_LIVENESS_INTERVAL=1 MONITOR_MAX_WAIT=2 "$MONITOR" "$MON_TIMEOUT") || TIMEOUT_RC=$?
assert_eq "$(jq -r '.type' <<<"$TRIGGER_TIMEOUT")" timeout "monitor-events.sh: exhausting MONITOR_MAX_WAIT with nothing to report still emits a trigger"
assert_contains "$(jq -r '.msg' <<<"$TRIGGER_TIMEOUT")" "timeout" "monitor-events.sh: timeout trigger's msg says timeout"
assert_eq "$TIMEOUT_RC" 1 "monitor-events.sh: the bound-exhausted timeout is the one trigger that exits nonzero"

# ═══════════════════════════════════════════════════════════════════════════
# reply.sh
# ═══════════════════════════════════════════════════════════════════════════

# reply_run — a 3-lane RUN_DIR (backend, frontend get a real surface_ref;
# review does not) wired entirely by hand — reply.sh only reads
# manifest.json's .contract.version/.workers[].lane and cmux/manifest.json's
# .workers[].name/.surface_ref, so it doesn't need a full init-run.sh run.
reply_run() {
  local d
  d=$(mktemp -d)
  mkdir -p "${d}/cmux" "${d}/lanes/backend" "${d}/lanes/frontend" "${d}/lanes/review"
  : >"${d}/lanes/backend/reply.md"
  : >"${d}/lanes/frontend/reply.md"
  : >"${d}/lanes/review/reply.md"
  printf '{"contract":{"version":"1.0.1"},"workers":[{"lane":"backend"},{"lane":"frontend"},{"lane":"review"}]}\n' >"${d}/manifest.json"
  printf '{"workers":[{"name":"backend","surface_ref":"surface:1"},{"name":"frontend","surface_ref":"surface:2"},{"name":"review","surface_ref":null}]}\n' >"${d}/cmux/manifest.json"
  printf '%s' "$d"
}

# cmux stub for the "every wake succeeds" side of the run — logs argv,
# always exits 0 (send-task.sh's own `cmux send` call succeeds).
CMUX_BIN_OK=$(mktemp -d)
cat >"${CMUX_BIN_OK}/cmux" <<'STUB'
#!/usr/bin/env bash
echo "cmux-stub: $*" >&2
exit 0
STUB
chmod +x "${CMUX_BIN_OK}/cmux"

# ─── --all across 3 lanes: two wake, one has no surface_ref (reported, ─────
# not swallowed) — this is exactly the "waiting forever" failure mode the
# team-lead flagged: a lane that emitted `waiting` and stopped by design
# must never be silently left unwoken.

RUN_R=$(reply_run)
REPLY_RC=0
REPLY_OUT=$(PATH="${CMUX_BIN_OK}:${PATH}" "$REPLY" "$RUN_R" --all "Contract 1.0.1 published" 2>/dev/null) || REPLY_RC=$?
assert_eq "$REPLY_RC" 1 "reply.sh --all: exits 1 when at least one of 3 lanes fails to wake"

assert_exit 0 grep -q 'Contract 1.0.1 published' "${RUN_R}/lanes/backend/reply.md"
assert_exit 0 grep -q 'Contract 1.0.1 published' "${RUN_R}/lanes/frontend/reply.md"
assert_exit 0 grep -q 'Contract 1.0.1 published' "${RUN_R}/lanes/review/reply.md"
assert_contains "$(cat "${RUN_R}/lanes/backend/reply.md")" "- Contract version: 1.0.1" "reply.sh: reply.md's structured header names the contract version"
assert_contains "$(cat "${RUN_R}/lanes/backend/reply.md")" "- Sent at:" "reply.sh: reply.md's structured header has a Sent-at timestamp"

REPLY_BACKEND=$(printf '%s\n' "$REPLY_OUT" | jq -c 'select(.lane=="backend")')
REPLY_FRONTEND=$(printf '%s\n' "$REPLY_OUT" | jq -c 'select(.lane=="frontend")')
REPLY_REVIEW=$(printf '%s\n' "$REPLY_OUT" | jq -c 'select(.lane=="review")')
assert_eq "$(jq -r '.woken' <<<"$REPLY_BACKEND")" true "reply.sh --all: backend (has a surface_ref) is woken"
assert_eq "$(jq -r '.woken' <<<"$REPLY_FRONTEND")" true "reply.sh --all: frontend (has a surface_ref) is woken"
assert_eq "$(jq -r '.woken' <<<"$REPLY_REVIEW")" false "reply.sh --all: review (no surface_ref) fails to wake"
assert_eq "$(jq -r '.reply_written' <<<"$REPLY_REVIEW")" true "reply.sh --all: reply.md is still written for review even though the wake itself failed"
assert_contains "$(jq -r '.detail' <<<"$REPLY_REVIEW")" "no surface_ref" "reply.sh --all: the wake failure names the exact reason, not a generic error"
assert_contains "$(jq -r '.detail' <<<"$REPLY_REVIEW")" "review" "reply.sh --all: the wake-failure detail names the failing lane"

# ─── send-task.sh itself failing (surface_ref present, but the wake call ───
# errors) is a DIFFERENT failure mode than "no surface_ref" and must be
# reported with its own distinguishable detail.

CMUX_BIN_FAIL=$(mktemp -d)
cat >"${CMUX_BIN_FAIL}/cmux" <<'STUB'
#!/usr/bin/env bash
echo "cmux-stub: send failed" >&2
exit 1
STUB
chmod +x "${CMUX_BIN_FAIL}/cmux"

RUN_R2=$(reply_run)
REPLY_RC2=0
REPLY_OUT2=$(PATH="${CMUX_BIN_FAIL}:${PATH}" "$REPLY" "$RUN_R2" backend "urgent update" 2>/dev/null) || REPLY_RC2=$?
assert_eq "$REPLY_RC2" 1 "reply.sh: a single-lane call where send-task.sh itself fails exits 1"
assert_eq "$(jq -r '.woken' <<<"$REPLY_OUT2")" false "reply.sh: send-task.sh's own failure is reported as woken:false"
assert_contains "$(jq -r '.detail' <<<"$REPLY_OUT2")" "send-task.sh failed" "reply.sh: the detail distinguishes 'send-task.sh failed' from 'no surface_ref'"

# ─── An unknown lane name is a usage error, not a silent no-op ────────────

RUN_R3=$(reply_run)
assert_exit 2 "$REPLY" "$RUN_R3" nonexistent-lane "hello"

# ═══════════════════════════════════════════════════════════════════════════
# validate-contract.sh
# ═══════════════════════════════════════════════════════════════════════════

# contract_run CWD VERSION PATH KIND VALCMD SHA — hand-assembles just the
# manifest.json fields validate-contract.sh actually reads (.cwd,
# .contract.*); it doesn't need a full run-state manifest.
contract_run() {
  local cwd="$1" version="$2" cpath="$3" kind="$4" valcmd="$5" sha="$6" d
  d=$(mktemp -d)/run
  mkdir -p "$d"
  jq -n --arg cwd "$cwd" --arg version "$version" --arg cpath "$cpath" \
    --arg kind "$kind" --arg valcmd "$valcmd" --arg sha "$sha" \
    '{cwd:$cwd, contract:{version:$version, path:$cpath, kind:$kind, validation_command:$valcmd, sha256:$sha}}' \
    >"${d}/manifest.json"
  printf '%s' "$d"
}
contract_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
ZERO_SHA=$(printf '0%.0s' $(seq 1 64))

# ─── 1. SHA mismatch fails ──────────────────────────────────────────────────

CT1_CWD=$(mktemp -d)
printf '{"type":"object"}\n' >"${CT1_CWD}/contract.schema.json"
CT1_RUN=$(contract_run "$CT1_CWD" "1.0.0" "contract.schema.json" "json-schema" "jq -e '.type' contract.schema.json" "$ZERO_SHA")
CT1_JSON=$("$VALIDATE_CONTRACT" "$CT1_RUN" --json) || true
assert_exit 1 "$VALIDATE_CONTRACT" "$CT1_RUN" --json
assert_eq "$(status_of "$CT1_JSON" contract-sha256-matches)" fail "validate-contract.sh: a sha256 mismatch fails contract-sha256-matches"
assert_contains "$(detail_of "$CT1_JSON" contract-sha256-matches)" "sha256 mismatch" "validate-contract.sh: the mismatch detail says so explicitly"
assert_eq "$(status_of "$CT1_JSON" contract-exists)" pass "validate-contract.sh: contract-exists is unaffected by a sha mismatch"

# ─── 2. version mismatch fails ──────────────────────────────────────────────

CT2_CWD=$(mktemp -d)
printf '{"type":"object","version":"9.9.9"}\n' >"${CT2_CWD}/contract.schema.json"
CT2_SHA=$(contract_sha256 "${CT2_CWD}/contract.schema.json")
CT2_RUN=$(contract_run "$CT2_CWD" "1.0.0" "contract.schema.json" "json-schema" "jq -e '.type' contract.schema.json" "$CT2_SHA")
CT2_JSON=$("$VALIDATE_CONTRACT" "$CT2_RUN" --json) || true
assert_exit 1 "$VALIDATE_CONTRACT" "$CT2_RUN" --json
assert_eq "$(status_of "$CT2_JSON" contract-version-matches)" fail "validate-contract.sh: an embedded version that disagrees with the manifest fails contract-version-matches"
assert_contains "$(detail_of "$CT2_JSON" contract-version-matches)" "9.9.9" "validate-contract.sh: the mismatch detail quotes the embedded version"
assert_contains "$(detail_of "$CT2_JSON" contract-version-matches)" "1.0.0" "validate-contract.sh: the mismatch detail quotes the manifest's declared version"
assert_eq "$(status_of "$CT2_JSON" contract-sha256-matches)" pass "validate-contract.sh: sha256 still matches — the version mismatch is isolated to its own item"

# A contract kind/shape with NO embedded version at all must pass, not fail
# by default — nothing to compare against.
CT2B_CWD=$(mktemp -d)
printf '{"type":"object"}\n' >"${CT2B_CWD}/contract.schema.json"
CT2B_SHA=$(contract_sha256 "${CT2B_CWD}/contract.schema.json")
CT2B_RUN=$(contract_run "$CT2B_CWD" "1.0.0" "contract.schema.json" "json-schema" "jq -e '.type' contract.schema.json" "$CT2B_SHA")
CT2B_JSON=$("$VALIDATE_CONTRACT" "$CT2B_RUN" --json)
assert_exit 0 "$VALIDATE_CONTRACT" "$CT2B_RUN" --json
assert_eq "$(status_of "$CT2B_JSON" contract-version-matches)" pass "validate-contract.sh: no readable version field in the contract passes — 'matches where readable', never fail-by-default"
assert_contains "$(detail_of "$CT2B_JSON" contract-version-matches)" "no readable version field" "validate-contract.sh: the pass detail says why — nothing was there to compare"

# ─── 3. a real linter (validation_command) failure fails ───────────────────

CT3_CWD=$(mktemp -d)
printf '{"type":"object"}\n' >"${CT3_CWD}/contract.schema.json"
CT3_SHA=$(contract_sha256 "${CT3_CWD}/contract.schema.json")
CT3_RUN=$(contract_run "$CT3_CWD" "1.0.0" "contract.schema.json" "json-schema" "jq -e '.bogusfield' contract.schema.json" "$CT3_SHA")
CT3_JSON=$("$VALIDATE_CONTRACT" "$CT3_RUN" --json) || true
assert_exit 1 "$VALIDATE_CONTRACT" "$CT3_RUN" --json
assert_eq "$(status_of "$CT3_JSON" contract-lint)" fail "validate-contract.sh: a real validation_command failure fails contract-lint"
assert_contains "$(detail_of "$CT3_JSON" contract-lint)" "validation_command failed" "validate-contract.sh: the fail detail says a real command failed, not a missing tool"

# ─── 4. a genuinely absent OpenAPI linter passes, honestly ─────────────────
# redocly and spectral are both genuinely absent from this machine's PATH
# (verified, not assumed) — no PATH trickery needed to exercise this path.

command -v redocly >/dev/null 2>&1 && echo "WARNING: redocly is installed — the 'absent linter' test below is no longer exercising the absent-linter path" >&2
command -v spectral >/dev/null 2>&1 && echo "WARNING: spectral is installed — the 'absent linter' test below is no longer exercising the absent-linter path" >&2

CT4_CWD=$(mktemp -d)
printf 'openapi: 3.0.0\ninfo:\n  version: 1.0.0\n' >"${CT4_CWD}/contract.yaml"
CT4_SHA=$(contract_sha256 "${CT4_CWD}/contract.yaml")
CT4_RUN=$(contract_run "$CT4_CWD" "1.0.0" "contract.yaml" "openapi" "true" "$CT4_SHA")
CT4_JSON=$("$VALIDATE_CONTRACT" "$CT4_RUN" --json)
assert_exit 0 "$VALIDATE_CONTRACT" "$CT4_RUN" --json
assert_eq "$(status_of "$CT4_JSON" contract-lint)" pass "validate-contract.sh: a genuinely absent OpenAPI linter (no redocly/spectral) records pass, not fail"
assert_contains "$(detail_of "$CT4_JSON" contract-lint)" "no OpenAPI linter" "validate-contract.sh: the pass detail says lint was skipped, not silently performed"
assert_contains "$(detail_of "$CT4_JSON" contract-lint)" "redocly" "validate-contract.sh: the pass detail names which linters it looked for"

# ─── 5. a real validation_command that succeeds passes (positive control ───
# for #3 above — a real command running is not itself sufficient evidence
# the pass/fail wiring is right without also seeing the success case).

CT5_CWD=$(mktemp -d)
printf '{"type":"object"}\n' >"${CT5_CWD}/contract.schema.json"
CT5_SHA=$(contract_sha256 "${CT5_CWD}/contract.schema.json")
CT5_RUN=$(contract_run "$CT5_CWD" "1.0.0" "contract.schema.json" "json-schema" "jq -e '.type' contract.schema.json" "$CT5_SHA")
CT5_JSON=$("$VALIDATE_CONTRACT" "$CT5_RUN" --json)
assert_exit 0 "$VALIDATE_CONTRACT" "$CT5_RUN" --json
assert_eq "$(status_of "$CT5_JSON" contract-lint)" pass "validate-contract.sh: a real validation_command that succeeds passes contract-lint"
assert_contains "$(detail_of "$CT5_JSON" contract-lint)" "validation_command succeeded" "validate-contract.sh: the pass detail says a real command ran and succeeded"

# ─── 6. an empty validation_command fails outright — `sh -c ""` exits 0 ────
# trivially, having checked nothing; that must never read as "succeeded".

CT6_CWD=$(mktemp -d)
printf '{"type":"object"}\n' >"${CT6_CWD}/contract.schema.json"
CT6_SHA=$(contract_sha256 "${CT6_CWD}/contract.schema.json")
CT6_RUN=$(contract_run "$CT6_CWD" "1.0.0" "contract.schema.json" "json-schema" "" "$CT6_SHA")
CT6_JSON=$("$VALIDATE_CONTRACT" "$CT6_RUN" --json) || true
assert_exit 1 "$VALIDATE_CONTRACT" "$CT6_RUN" --json
assert_eq "$(status_of "$CT6_JSON" contract-lint)" fail "validate-contract.sh: an empty validation_command fails contract-lint, not a silent pass"
assert_contains "$(detail_of "$CT6_JSON" contract-lint)" "empty or whitespace-only" "validate-contract.sh: the fail detail names exactly why — no runnable validation was declared"

# ─── 7. a whitespace-only validation_command fails the same way — `sh -c ` ──
# with only spaces/tabs is exactly as vacuous as an empty string.

CT7_CWD=$(mktemp -d)
printf '{"type":"object"}\n' >"${CT7_CWD}/contract.schema.json"
CT7_SHA=$(contract_sha256 "${CT7_CWD}/contract.schema.json")
CT7_RUN=$(contract_run "$CT7_CWD" "1.0.0" "contract.schema.json" "command" "$(printf '   \t  ')" "$CT7_SHA")
CT7_JSON=$("$VALIDATE_CONTRACT" "$CT7_RUN" --json) || true
assert_exit 1 "$VALIDATE_CONTRACT" "$CT7_RUN" --json
assert_eq "$(status_of "$CT7_JSON" contract-lint)" fail "validate-contract.sh: a whitespace-only validation_command fails contract-lint too — 'blank' is not just the empty string"
assert_contains "$(detail_of "$CT7_JSON" contract-lint)" "empty or whitespace-only" "validate-contract.sh: same diagnostic wording as the empty-string case"

# ─── 8. an OpenAPI linter present on PATH but not executable is reported ───
# distinctly from genuinely absent — `command -v` alone isn't proof of
# runnability under bash (unlike POSIX `sh`, it reports success for a PATH
# entry with no execute bit — verified directly against this machine's
# bash), so the pass detail must say which case it is, not conflate the two.

CT8_CWD=$(mktemp -d)
printf 'openapi: 3.0.0\ninfo:\n  version: 1.0.0\n' >"${CT8_CWD}/contract.yaml"
CT8_SHA=$(contract_sha256 "${CT8_CWD}/contract.yaml")
CT8_RUN=$(contract_run "$CT8_CWD" "1.0.0" "contract.yaml" "openapi" "true" "$CT8_SHA")
CT8_FAKEBIN=$(mktemp -d)
printf '#!/bin/sh\necho hi\n' >"${CT8_FAKEBIN}/redocly"
chmod -x "${CT8_FAKEBIN}/redocly"
CT8_JSON=$(PATH="${CT8_FAKEBIN}:${PATH}" "$VALIDATE_CONTRACT" "$CT8_RUN" --json)
assert_exit 0 env PATH="${CT8_FAKEBIN}:${PATH}" "$VALIDATE_CONTRACT" "$CT8_RUN" --json
assert_eq "$(status_of "$CT8_JSON" contract-lint)" pass "validate-contract.sh: a present-but-non-executable redocly still skips lint gracefully (pass, not fail)"
assert_contains "$(detail_of "$CT8_JSON" contract-lint)" "found on PATH but not executable" \
  "validate-contract.sh: the detail distinguishes present-but-not-executable from genuinely absent"

# ═══════════════════════════════════════════════════════════════════════════
# round-gate.sh
# ═══════════════════════════════════════════════════════════════════════════

# claude_stub_bin VERDICT — a bin dir whose `claude` ignores its args,
# reads (and discards) reviewer.sh's stdin, and emits a minimal review body
# ending in the one line round-gate.sh's parser looks for. Always shadows
# the real `claude` on PATH (prepended) so these tests never make a real
# network call.
claude_stub_bin() {
  local verdict="$1" d
  d=$(mktemp -d)
  cat >"${d}/claude" <<STUB
#!/usr/bin/env bash
cat >/dev/null
echo "Reviewed the diff against project conventions."
echo "VERDICT: ${verdict}"
STUB
  chmod +x "${d}/claude"
  printf '%s' "$d"
}

# new_run_with_plan PLAN REPO — same as the suite's own new_run helper,
# but for a caller-supplied PLAN rather than the fixed FIXTURE_PLAN (needed
# below to exercise a lane whose test_command genuinely fails).
new_run_with_plan() {
  local plan="$1" repo="$2" run_dir
  run_dir="$(mktemp -d)/run"
  "$INIT_RUN" "$plan" "$run_dir" "$repo" "surface:test" >/dev/null 2>&1 || true
  printf '%s' "$run_dir"
}

RG_CLAUDE_APPROVE=$(claude_stub_bin APPROVE)
RG_CLAUDE_REJECT=$(claude_stub_bin REQUEST_CHANGES)

# ─── Happy path: every stage genuinely runs and passes, round 1 ───────────

RG_REPO=$(new_repo)
RG_RUN=$(new_run "$RG_REPO")
RG_JSON=$(PATH="${RG_CLAUDE_APPROVE}:${PATH}" "$ROUND_GATE" "$RG_RUN" 1 --json)
assert_exit 0 env PATH="${RG_CLAUDE_APPROVE}:${PATH}" "$ROUND_GATE" "$RG_RUN" 1 --json
assert_eq "$(status_of "$RG_JSON" round-within-max-rounds)" pass "round-gate.sh: round 1 is within max_rounds"
assert_eq "$(jq -r '[.[] | select(.stage=="lane-tests")] | length' <<<"$RG_JSON")" 3 \
  "round-gate.sh: lane-tests runs one item per non-orchestrator lane (backend, frontend, review)"
assert_eq "$(jq -r '[.[] | select(.stage=="lane-tests" and .status=="pass")] | length' <<<"$RG_JSON")" 3 \
  "round-gate.sh: all 3 lane tests pass (fixture plan's test_command is \`true\`)"
assert_eq "$(status_of "$RG_JSON" contract-exists)" pass "round-gate.sh: the contract stage's own sub-items are merged in verbatim"
assert_eq "$(status_of "$RG_JSON" changed-files-within-union)" pass "round-gate.sh: the run-state stage's own sub-items are merged in verbatim"
assert_eq "$(status_of "$RG_JSON" light-review-verdict)" pass "round-gate.sh: the reviewer approved, via the stubbed claude"
assert_eq "$(jq -r '[.[] | select(.status=="skipped")] | length' <<<"$RG_JSON")" 0 \
  "round-gate.sh: on a clean happy path, nothing is skipped — every stage genuinely ran"

# ─── Short-circuit: a lane-test failure stops everything after it ─────────
# — contract, run-state and review must all show status:"skipped", not
# absent and not silently "pass".

RG_REPO_FAIL=$(new_repo)
RG_PLAN_DIR=$(mktemp -d)
sed "s/\`opus high\` | \`true\`/\`opus high\` | \`false\`/" "$FIXTURE_PLAN" >"${RG_PLAN_DIR}/plan.md"
cp -r "$(dirname "$FIXTURE_PLAN")/subplans" "${RG_PLAN_DIR}/"
cp "$(dirname "$FIXTURE_PLAN")/codeintel-status.json" "${RG_PLAN_DIR}/"
RG_RUN_FAIL=$(new_run_with_plan "${RG_PLAN_DIR}/plan.md" "$RG_REPO_FAIL")
RG_JSON_FAIL=$(PATH="${RG_CLAUDE_APPROVE}:${PATH}" "$ROUND_GATE" "$RG_RUN_FAIL" 1 --json) || true
assert_exit 1 env PATH="${RG_CLAUDE_APPROVE}:${PATH}" "$ROUND_GATE" "$RG_RUN_FAIL" 1 --json
assert_eq "$(jq -r '.[] | select(.stage=="lane-tests" and .item=="lane-test:backend") | .status' <<<"$RG_JSON_FAIL")" fail \
  "round-gate.sh: the doctored backend test_command (\`false\`) fails lane-test:backend by name"
assert_eq "$(jq -r '.[] | select(.stage=="contract") | .status' <<<"$RG_JSON_FAIL")" skipped \
  "round-gate.sh: contract never ran after the lane-test failure — status is skipped, not pass"
assert_eq "$(jq -r '.[] | select(.stage=="run-state") | .status' <<<"$RG_JSON_FAIL")" skipped \
  "round-gate.sh: run-state never ran after the lane-test failure"
assert_eq "$(jq -r '.[] | select(.stage=="review") | .status' <<<"$RG_JSON_FAIL")" skipped \
  "round-gate.sh: review (the most expensive stage) never ran after the lane-test failure"
assert_contains "$(jq -r '.[] | select(.stage=="contract") | .detail' <<<"$RG_JSON_FAIL")" "not run" \
  "round-gate.sh: the skipped stage's own detail says it was not run, not that it passed"

# ─── changed-files-within-union failure (the hard boundary) blocks at the ──
# run-state stage, and correctly skips review after it.

RG_REPO_BOUNDARY=$(new_repo)
RG_RUN_BOUNDARY=$(new_run "$RG_REPO_BOUNDARY")
mkdir -p "${RG_REPO_BOUNDARY}/rogue"
printf 'x\n' >"${RG_REPO_BOUNDARY}/rogue/file.txt"
printf 'rogue/file.txt\n' >>"${RG_RUN_BOUNDARY}/worker-backend.files.txt"
RG_JSON_BOUNDARY=$(PATH="${RG_CLAUDE_APPROVE}:${PATH}" "$ROUND_GATE" "$RG_RUN_BOUNDARY" 1 --json) || true
assert_exit 1 env PATH="${RG_CLAUDE_APPROVE}:${PATH}" "$ROUND_GATE" "$RG_RUN_BOUNDARY" 1 --json
assert_eq "$(jq -r '.[] | select(.stage=="run-state" and .item=="changed-files-within-union") | .status' <<<"$RG_JSON_BOUNDARY")" fail \
  "round-gate.sh: an unowned write outside every lane's union fails changed-files-within-union by name"
assert_eq "$(jq -r '.[] | select(.stage=="review") | .status' <<<"$RG_JSON_BOUNDARY")" skipped \
  "round-gate.sh: review is skipped after the boundary violation"

# ─── A warn-only run-state (post-done-writes-absent) does NOT block — the ──
# round proceeds to review and, with an approving reviewer, passes overall.

RG_REPO_WARN=$(new_repo)
RG_RUN_WARN=$(new_run "$RG_REPO_WARN")
assert_exit 0 "$EVENT" "$RG_RUN_WARN" backend "Task 9" "done" "nothing left this round"
printf 'more work after done\n' >>"${RG_REPO_WARN}/backend/service.sh"
printf 'backend/service.sh\n' >>"${RG_RUN_WARN}/worker-backend.files.txt"
RG_FUTURE_TS=$(date -v+1H +%Y%m%d%H%M.%S 2>/dev/null || date -d '+1 hour' +%Y%m%d%H%M.%S)
touch -t "$RG_FUTURE_TS" "${RG_REPO_WARN}/backend/service.sh"
RG_JSON_WARN=$(PATH="${RG_CLAUDE_APPROVE}:${PATH}" "$ROUND_GATE" "$RG_RUN_WARN" 1 --json)
assert_exit 0 env PATH="${RG_CLAUDE_APPROVE}:${PATH}" "$ROUND_GATE" "$RG_RUN_WARN" 1 --json
assert_eq "$(jq -r '.[] | select(.item=="post-done-writes-absent") | .status' <<<"$RG_JSON_WARN")" warn \
  "round-gate.sh: post-done-writes-absent is merged in as warn, exactly as validate-run-state.sh reported it"
assert_eq "$(status_of "$RG_JSON_WARN" light-review-verdict)" pass \
  "round-gate.sh: a warn-only run-state did not short-circuit — review still ran and approved"
assert_eq "$(jq -r '[.[] | select(.status=="fail")] | length' <<<"$RG_JSON_WARN")" 0 \
  "round-gate.sh: zero fail items — a warn never counts as a failure"

# ─── Reviewer non-approval (REQUEST_CHANGES) fails the review stage ───────

RG_REPO_REJECT=$(new_repo)
RG_RUN_REJECT=$(new_run "$RG_REPO_REJECT")
RG_JSON_REJECT=$(PATH="${RG_CLAUDE_REJECT}:${PATH}" "$ROUND_GATE" "$RG_RUN_REJECT" 1 --json) || true
assert_exit 1 env PATH="${RG_CLAUDE_REJECT}:${PATH}" "$ROUND_GATE" "$RG_RUN_REJECT" 1 --json
assert_eq "$(status_of "$RG_JSON_REJECT" light-review-verdict)" fail \
  "round-gate.sh: a REQUEST_CHANGES verdict fails light-review-verdict"
assert_contains "$(detail_of "$RG_JSON_REJECT" light-review-verdict)" "REQUEST_CHANGES" \
  "round-gate.sh: the fail detail quotes the actual verdict, not a generic message"

# ─── ROUND 4 is refused outright — an escalation record, every other ──────
# stage skipped, nothing (not even the cheap lane-tests stage) runs.

RG_REPO_R4=$(new_repo)
RG_RUN_R4=$(new_run "$RG_REPO_R4")
RG_JSON_R4=$("$ROUND_GATE" "$RG_RUN_R4" 4 --json) || true
assert_exit 1 "$ROUND_GATE" "$RG_RUN_R4" 4 --json
assert_eq "$(status_of "$RG_JSON_R4" round-within-max-rounds)" fail "round-gate.sh: ROUND 4 fails round-within-max-rounds (max_rounds=3)"
assert_contains "$(detail_of "$RG_JSON_R4" round-within-max-rounds)" "exceeds max_rounds=3" "round-gate.sh: the escalation record names the actual bound"
assert_contains "$(detail_of "$RG_JSON_R4" round-within-max-rounds)" "escalate" "round-gate.sh: the escalation record says this needs a human decision"
assert_eq "$(jq -r '.[] | select(.stage=="lane-tests") | .status' <<<"$RG_JSON_R4")" skipped \
  "round-gate.sh: round 4 refuses before even the cheap lane-tests stage runs"
assert_eq "$(jq -r '[.[] | select(.status=="skipped")] | length' <<<"$RG_JSON_R4")" 4 \
  "round-gate.sh: all 4 later stages (lane-tests, contract, run-state, review) are skipped, none silently omitted"

# ═══════════════════════════════════════════════════════════════════════════
# Task 11: SKILL.md, README.md, /deep-execute command
# ═══════════════════════════════════════════════════════════════════════════

assert_exit 0 test -f "$SKILL_MD"
assert_exit 0 test -f "$README_MD"
assert_exit 0 test -f "$COMMAND_MD"

# ─── Frontmatter ────────────────────────────────────────────────────────────

SKILL_MD_TEXT=$(cat "$SKILL_MD")
assert_contains "$SKILL_MD_TEXT" "name: deep-execute" "SKILL.md: frontmatter names the skill"
assert_contains "$SKILL_MD_TEXT" "description:" "SKILL.md: frontmatter has a description"

# ─── Every mechanism script is referenced by name ──────────────────────────

for script in init-run.sh monitor-events.sh reply.sh round-gate.sh board.sh \
  validate-contract.sh validate-run-state.sh; do
  assert_contains "$SKILL_MD_TEXT" "$script" "SKILL.md: references ${script}"
done

# ─── Required strings (brief step 1) ───────────────────────────────────────

assert_contains "$SKILL_MD_TEXT" "Monitor" "SKILL.md: mentions the Monitor tool"
assert_contains "$SKILL_MD_TEXT" "events.jsonl" "SKILL.md: mentions events.jsonl"
assert_contains "$SKILL_MD_TEXT" "reply.md" "SKILL.md: mentions reply.md"
assert_contains "$SKILL_MD_TEXT" "agents.allowlist" "SKILL.md: mentions agents.allowlist"
assert_contains "$SKILL_MD_TEXT" "max 3 rounds" "SKILL.md: states the default round cap as 'max 3 rounds'"

# ─── Fix: must-survive rules pinned so the line-count metric can't be ──────
# gamed by deleting judgement content (a line-count check alone would still
# pass if a rule got quietly dropped and the doc padded back to length —
# only pinning the rule's actual text catches that; see deep-plan's own
# identical fix for the same failure mode).

assert_contains "$SKILL_MD_TEXT" "the orchestrator is the sole committer, between rounds" \
  "SKILL.md: rule survives — workers never run git; the orchestrator commits between rounds"
assert_contains "$SKILL_MD_TEXT" "committed before fanout and are read-only afterwards" \
  "SKILL.md: rule survives — contract and shared files committed before fanout, read-only after"
assert_contains "$SKILL_MD_TEXT" "A failing \`round-gate.sh\` JSON is a hard gate" \
  "SKILL.md: rule survives — a failing round-gate.sh JSON is a hard gate"
assert_contains "$SKILL_MD_TEXT" "never advance" \
  "SKILL.md: rule survives — never advance on a failing gate"
assert_contains "$SKILL_MD_TEXT" "\`AskUserQuestion\` confirms it against \`agents.allowlist\`" \
  "SKILL.md: rule survives — the plan suggests an agent, AskUserQuestion confirms it"
assert_contains "$SKILL_MD_TEXT" "Round 1 gets orchestrator review before anything reaches the human" \
  "SKILL.md: rule survives — round 1 gets orchestrator review before the human sees it"
assert_contains "$SKILL_MD_TEXT" "After three rounds, stop and \`AskUserQuestion\`" \
  "SKILL.md: rule survives — after three rounds, stop and AskUserQuestion"

# ─── Honest attribution framing (never claims proof/authentication) ───────

assert_contains "$SKILL_MD_TEXT" "self-declared" "SKILL.md: attribution framed as self-declared"
assert_contains "$SKILL_MD_TEXT" "not authenticated" "SKILL.md: attribution framed as unauthenticated"
assert_contains "$SKILL_MD_TEXT" "computed from git only" \
  "SKILL.md: the one enforced boundary is described as computed from git only"
for FORBIDDEN in "proves who wrote" "prevents a worker" "cannot forge"; do
  assert_eq "$(printf '%s' "$SKILL_MD_TEXT" | grep -c -F "$FORBIDDEN" || true)" "0" \
    "SKILL.md: never overclaims attribution with '${FORBIDDEN}'"
done

# ─── Monitor filter covers failure signatures, not just the happy path ────

for TRIGGER in waiting blocked question "done" invalid_event vanished_pane fatal_signature timeout; do
  assert_contains "$SKILL_MD_TEXT" "$TRIGGER" "SKILL.md: Monitor filter names trigger type '${TRIGGER}'"
done

# ─── Contract-drift protocol spelled out ───────────────────────────────────

assert_contains "$SKILL_MD_TEXT" "bump" "SKILL.md: contract drift bumps the version"
assert_contains "$SKILL_MD_TEXT" "semantic version" "SKILL.md: contract drift names semantic versioning"
assert_contains "$SKILL_MD_TEXT" "reply.sh RUN_DIR --all" "SKILL.md: contract drift wakes every lane via reply.sh --all"

# ─── Resume is honest about what is/isn't recoverable ──────────────────────

assert_contains "$SKILL_MD_TEXT" "--resume RUN_DIR" "SKILL.md: documents --resume RUN_DIR"
assert_contains "$SKILL_MD_TEXT" "Not** reconstructible" "SKILL.md: resume names what cannot be recovered"
assert_contains "$SKILL_MD_TEXT" "mid-edit" "SKILL.md: resume names the specific unrecoverable state (a pane mid-edit)"

# ─── Judgement, not procedure: this doc must stay well short of the other ──
# slimmed deep-* skills' combined length (693 lines across deep-plan +
# deep-review + cmux-orchestrator) — a length ceiling alone doesn't prove
# judgement-only prose, but a doc that blows past every sibling's line
# count is a strong signal it re-derived procedure instead of naming scripts.

SKILL_MD_LINES=$(wc -l <"$SKILL_MD" | tr -d ' ')
assert_eq "$([ "$SKILL_MD_LINES" -le 250 ] && echo yes || echo no)" yes \
  "SKILL.md: stays at or under 250 lines (got ${SKILL_MD_LINES}) — judgement, not a restated procedure"

# ─── README.md documents the allowlist, protocol, round policy, resume, ───
# artifacts and the honest attribution limit (brief step 4)

README_MD_TEXT=$(cat "$README_MD")
assert_contains "$README_MD_TEXT" "agents.allowlist" "README.md: documents the agent allowlist"
assert_contains "$README_MD_TEXT" "event.sh" "README.md: documents the event protocol"
assert_contains "$README_MD_TEXT" "reply.sh" "README.md: documents the reply protocol"
assert_contains "$README_MD_TEXT" "max 3 rounds" "README.md: documents the round policy's default cap"
assert_contains "$README_MD_TEXT" "--resume RUN_DIR" "README.md: documents resume behavior"
assert_contains "$README_MD_TEXT" "self-declared and" "README.md: states the attribution limit honestly"
assert_contains "$README_MD_TEXT" "Artifacts produced" "README.md: documents the artifacts produced"

# ─── Command file delegates and does not restate the protocol ─────────────

COMMAND_MD_TEXT=$(cat "$COMMAND_MD")
assert_contains "$COMMAND_MD_TEXT" "description:" "deep-execute.md: frontmatter has a description"
# shellcheck disable=SC2088 # asserting literal doc text, not expanding a path
assert_contains "$COMMAND_MD_TEXT" "~/.claude/skills/deep-execute/SKILL.md" \
  "deep-execute.md: points at the skill"
assert_contains "$COMMAND_MD_TEXT" "--resume RUN_DIR" "deep-execute.md: argument grammar documents --resume"
assert_contains "$COMMAND_MD_TEXT" "--max-rounds N" "deep-execute.md: argument grammar documents --max-rounds"
assert_eq "$(printf '%s' "$COMMAND_MD_TEXT" | grep -c 'round-gate.sh\|monitor-events.sh\|init-run.sh' || true)" "0" \
  "deep-execute.md: does not restate the skill's protocol by naming its internal scripts"

assert_summary
