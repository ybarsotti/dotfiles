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
WORKER_PROMPT="${ROOT}/dot_claude/skills/deep-execute/templates/worker-system-prompt.txt"
FIXTURE_PLAN="${ROOT}/dot_claude/skills/deep-execute/tests/fixtures/init-run-plan.md"

assert_exit 0 test -f "$EVENT"
assert_exit 0 test -f "$BOARD"
assert_exit 0 test -f "$INIT_RUN"
assert_exit 0 test -f "$VALIDATE_STATE"
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

assert_summary
