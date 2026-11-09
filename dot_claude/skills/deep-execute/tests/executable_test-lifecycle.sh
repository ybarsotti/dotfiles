#!/usr/bin/env bash
# Lifecycle tests for one deep-execute run, driven end to end with stub agents.
#
# A stub `claude` and a stub `codex` sit first on PATH. Each call records its
# arguments and its prompt, then acts out the mode that the test wrote for that
# call: `ok`, `done` (emits a done event), `slow` (sleeps), `slow-done` or
# `fail`. No real agent starts. The tests cover the parts of the run that only
# show up when the processes run for real: the brief that a lane receives, the
# reply that arrives mid-turn or after `done`, a failing agent, the turn cap, a
# crash, resume, contract drift followed by a gate, a gate child that crashes,
# and the attribution logs.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
# shellcheck source=/dev/null
. "${ROOT}/dot_claude/skills/_shared/executable_assert.sh"

SKILLS="${ROOT}/dot_claude/skills"
SCRIPTS="${SKILLS}/deep-execute/scripts"
INIT_RUN="${SCRIPTS}/executable_init-run.sh"
WORKER_LOOP="${SCRIPTS}/executable_worker-loop.sh"
REPLY="${SCRIPTS}/executable_reply.sh"
MONITOR="${SCRIPTS}/executable_monitor-events.sh"
EVENT="${SCRIPTS}/executable_event.sh"
ROUND_GATE="${SCRIPTS}/executable_round-gate.sh"
VALIDATE_STATE="${SCRIPTS}/executable_validate-run-state.sh"
CONTRACT_BUMP="${SCRIPTS}/executable_contract-bump.sh"
PLAN_STAMP="${SKILLS}/_shared/executable_plan-stamp.sh"
FIXTURES="${SKILLS}/deep-execute/tests/fixtures"
FIXTURE_PLAN="${FIXTURES}/init-run-plan.md"

WORK=$(mktemp -d)
BG_PIDS=()
cleanup() {
  local p
  for p in "${BG_PIDS[@]}"; do kill -9 "$p" 2>/dev/null || true; done
  pkill -9 -f "${WORK}/stub" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# ─── Helpers ────────────────────────────────────────────────────────────────

new_repo() {
  local repo
  repo=$(mktemp -d "${WORK}/repo.XXXXXX")
  git -C "$repo" init --quiet -b main
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name "deep-execute lifecycle test"
  git -C "$repo" config commit.gpgsign false
  mkdir -p "$repo/backend" "$repo/frontend" "$repo/dot_claude/skills/deep-review"
  printf '{"type":"object"}\n' >"$repo/contract.schema.json"
  printf '# readme\n' >"$repo/README.md"
  printf '#!/usr/bin/env bash\n' >"$repo/backend/service.sh"
  printf '#!/usr/bin/env bash\n' >"$repo/frontend/app.sh"
  printf '#!/usr/bin/env bash\n' >"$repo/dot_claude/skills/deep-review/checklist.sh"
  git -C "$repo" add -A
  git -C "$repo" commit --quiet -m init
  printf '%s' "$repo"
}

# new_run REPO [PLAN] [FLAGS...] — a fresh RUN_DIR scaffolded by init-run.sh.
new_run() {
  local repo="$1" plan="${2:-$FIXTURE_PLAN}" run_dir
  shift 2 2>/dev/null || shift $#
  run_dir="$(mktemp -d "${WORK}/run.XXXXXX")/run"
  "$INIT_RUN" "$plan" "$run_dir" "$repo" "surface:test" "$@" >/dev/null 2>&1 || true
  printf '%s' "$run_dir"
}

# new_stub MODE... — a stub directory whose claude and codex act out MODE per call.
# The last mode repeats for every later call.
new_stub() {
  local d agent
  d=$(mktemp -d "${WORK}/stub.XXXXXX")
  printf '%s\n' "$@" >"${d}/modes"
  for agent in claude codex; do
    cat >"${d}/${agent}" <<'STUB'
#!/usr/bin/env bash
dir="$(cd "$(dirname "$0")" && pwd)"
n=$(( $(find "$dir" -name 'call.*.args' | wc -l) + 1 ))
printf '%s\n' "$@" >"${dir}/call.${n}.args"
printf '%s' "${@: -1}" >"${dir}/call.${n}.prompt"
printf '%s' "$$" >"${dir}/call.${n}.pid"
mode=$(sed -n "${n}p" "${dir}/modes")
[ -n "$mode" ] || mode=$(tail -n 1 "${dir}/modes")
case "$mode" in
  fail) echo "stub agent failed" >&2; exit 1 ;;
  slow) sleep "${STUB_SLOW:-2}" ;;
  done) "$STUB_EVENT" "$STUB_RUN" "$STUB_LANE" "$STUB_TASK" done "round finished" ;;
  slow-done) sleep "${STUB_SLOW:-2}"; "$STUB_EVENT" "$STUB_RUN" "$STUB_LANE" "$STUB_TASK" done "round finished" ;;
  git) git status >/dev/null 2>"${dir}/call.${n}.git.err"; printf '%s' "$?" >"${dir}/call.${n}.git.rc" ;;
esac
exit 0
STUB
    chmod +x "${d}/${agent}"
  done
  printf '%s' "$d"
}

calls() { find "$1" -name 'call.*.args' | wc -l | tr -d ' '; }
has_calls() { [ "$(calls "$1")" -ge "$2" ]; }
pid_dead() { ! kill -0 "$1" 2>/dev/null; }
last_event_type() { jq -r --arg l "$2" 'select(.lane == $l) | .type' "$1/events.jsonl" 2>/dev/null | tail -n 1; }
lane_event_is() { [ "$(last_event_type "$1" "$2")" = "$3" ]; }

# wait_until SECONDS CMD... — retries CMD every 0.1s until it succeeds or the bound passes.
wait_until() {
  local secs="$1" end
  shift
  end=$((SECONDS + secs))
  until "$@"; do
    [ "$SECONDS" -lt "$end" ] || return 1
    sleep 0.1
  done
}

# start_loop RUN LANE STUB [ENV=VALUE...] — runs worker-loop.sh in the background; sets LOOP_PID.
start_loop() {
  local run="$1" lane="$2" stub="$3"
  shift 3
  env PATH="${stub}:${PATH}" STUB_EVENT="$EVENT" STUB_RUN="$run" STUB_LANE="$lane" \
    STUB_TASK="2 - Implement the backend service" WORKER_LOOP_POLL_SECONDS=0.2 "$@" \
    bash "$WORKER_LOOP" "$run" "$lane" >>"${run}/loop-${lane}.out" 2>&1 &
  LOOP_PID=$!
  BG_PIDS+=("$LOOP_PID")
}

stop_loop() {
  : >"$1/lanes/$2/stop"
  wait_until 10 pid_dead "$3"
}

# ─── 1. Launch: the lane receives a fully rendered brief and the shared rules ─

REPO_A=$(new_repo)
RUN_A=$(new_run "$REPO_A")
LAUNCH_A="${RUN_A}/launch/manifest.json"
assert_exit 0 test -f "$LAUNCH_A"
SID_A=$(jq -r '.workers[] | select(.name == "backend") | .session_id' "$LAUNCH_A" 2>/dev/null)
assert_eq "$(printf '%s' "$SID_A" | grep -cE '^[0-9a-f-]{36}$')" 1 "launch manifest: backend has a session id fixed at init time"
assert_eq "$(jq -r '.workers[] | select(.name == "backend") | "\(.runner) \(.model) \(.effort)"' "$LAUNCH_A" 2>/dev/null)" \
  "claude opus high" "launch manifest: backend keeps the runner, model and effort of the plan"

BRIEF_A=$(cat "${RUN_A}/launch/worker-backend.prompt.md" 2>/dev/null || true)
for NEEDLE in "backend" "backend/**" "2 - Implement the backend service" "$RUN_A" \
  "${SCRIPTS}/executable_event.sh" "contract.schema.json" "test_command" "TDD"; do
  assert_contains "$BRIEF_A" "$NEEDLE" "brief: names '${NEEDLE}'"
done
assert_eq "$(printf '%s' "$BRIEF_A" | grep -cE '\{\{[A-Z_]+\}\}|<Detailed task' || true)" 0 \
  "brief: no unresolved placeholder is left"
assert_eq "$(printf '%s' "$BRIEF_A" | grep -c 'Done marker' || true)" 0 \
  "brief: no done-marker instruction that contradicts the event protocol"

STUB_A=$(new_stub "done" "ok")
start_loop "$RUN_A" backend "$STUB_A"
LOOP_A=$LOOP_PID
wait_until 10 has_calls "$STUB_A" 1
wait_until 10 lane_event_is "$RUN_A" backend "done"
ARGS_A1=$(cat "${STUB_A}/call.1.args" 2>/dev/null || true)
assert_contains "$ARGS_A1" "--session-id"$'\n'"$SID_A" "launch: the first turn pins the session id from the launch manifest"
assert_contains "$ARGS_A1" "--append-system-prompt" "launch: the shared worker rules go in as a system prompt"
assert_contains "$ARGS_A1" "Never run \`git\`" "launch: the system prompt is the worker rules file"
assert_contains "$ARGS_A1" "--disallowedTools"$'\n'"Bash(git:*)" "launch: git is a disallowed tool for a claude lane"
assert_contains "$ARGS_A1" "--model"$'\n'"opus" "launch: the model of the plan is passed"
assert_contains "$ARGS_A1" "--effort"$'\n'"high" "launch: the effort of the plan is passed"
assert_contains "$(cat "${STUB_A}/call.1.prompt" 2>/dev/null)" "2 - Implement the backend service" \
  "launch: the first prompt is the brief itself, not a pointer to a file"
assert_eq "$(cat "${RUN_A}/lanes/backend/loop.pid" 2>/dev/null)" "$LOOP_A" "launch: the loop writes its pid file"

# ─── 2. A reply sent after `done` wakes the lane ───────────────────────────

sleep 0.5
assert_exit 0 kill -0 "$LOOP_A"
REPLY_A=$("$REPLY" "$RUN_A" backend "Fix the review finding in backend/service.sh" 2>/dev/null)
assert_eq "$(jq -r '.woken' <<<"$REPLY_A" 2>/dev/null)" true "reply after done: the live loop counts as woken"
wait_until 10 has_calls "$STUB_A" 2
assert_contains "$(cat "${STUB_A}/call.2.prompt" 2>/dev/null)" "Fix the review finding in backend/service.sh" \
  "reply after done: the lane runs a new turn with the reply text"
assert_contains "$(cat "${STUB_A}/call.2.args" 2>/dev/null)" "--resume"$'\n'"$SID_A" \
  "reply after done: the new turn resumes the pinned session"
stop_loop "$RUN_A" backend "$LOOP_A"
wait "$LOOP_A"
assert_eq "$?" 0 "stop file: the loop exits 0"

# ─── 3. A reply sent mid-turn is consumed; two replies both arrive ─────────

REPO_B=$(new_repo)
RUN_B=$(new_run "$REPO_B")
STUB_B=$(new_stub "slow" "ok")
start_loop "$RUN_B" backend "$STUB_B" STUB_SLOW=2
LOOP_B=$LOOP_PID
wait_until 10 has_calls "$STUB_B" 1
"$REPLY" "$RUN_B" backend "first mid-turn note" >/dev/null 2>&1
"$REPLY" "$RUN_B" backend "second mid-turn note" >/dev/null 2>&1
wait_until 15 has_calls "$STUB_B" 2
PROMPT_B2=$(cat "${STUB_B}/call.2.prompt" 2>/dev/null || true)
assert_contains "$PROMPT_B2" "first mid-turn note" "mid-turn reply: the next turn carries it"
assert_contains "$PROMPT_B2" "second mid-turn note" "mid-turn reply: a second reply does not overwrite the first"
assert_eq "$(find "${RUN_B}/lanes/backend/replies" -type f 2>/dev/null | wc -l | tr -d ' ')" 2 "replies: each reply is its own numbered file"
stop_loop "$RUN_B" backend "$LOOP_B"

# ─── 4. A brief with an unresolved placeholder never launches ──────────────

REPO_C=$(new_repo)
RUN_C=$(new_run "$REPO_C")
printf '\n{{TASKS}}\n' >>"${RUN_C}/launch/worker-backend.prompt.md"
STUB_C=$(new_stub "ok")
PATH="${STUB_C}:${PATH}" bash "$WORKER_LOOP" "$RUN_C" backend >/dev/null 2>&1
assert_eq "$?" 2 "placeholder: worker-loop.sh refuses the brief"
assert_eq "$(calls "$STUB_C")" 0 "placeholder: no agent starts"

# ─── 5. Agent failure and turn cap write failure events ────────────────────

REPO_D=$(new_repo)
RUN_D=$(new_run "$REPO_D")
STUB_D=$(new_stub "fail")
PATH="${STUB_D}:${PATH}" WORKER_LOOP_POLL_SECONDS=0.2 bash "$WORKER_LOOP" "$RUN_D" backend >/dev/null 2>&1
assert_eq "$?" 1 "agent failure: worker-loop.sh exits 1"
D_LAST=$(jq -c 'select(.lane == "backend")' "${RUN_D}/events.jsonl" 2>/dev/null | tail -n 1)
assert_eq "$(jq -r '.type' <<<"$D_LAST" 2>/dev/null)" blocked "agent failure: a blocked event is written"
assert_eq "$(jq -r '.task' <<<"$D_LAST" 2>/dev/null)" "2 - Implement the backend service" \
  "agent failure: the event names the declared task of the lane"
assert_contains "$(jq -r '.msg' <<<"$D_LAST" 2>/dev/null)" "failed on turn 1" "agent failure: the message names the turn"

REPO_E=$(new_repo)
RUN_E=$(new_run "$REPO_E")
STUB_E=$(new_stub "ok")
start_loop "$RUN_E" backend "$STUB_E" WORKER_LOOP_MAX_TURNS=1
LOOP_E=$LOOP_PID
wait_until 10 has_calls "$STUB_E" 1
"$REPLY" "$RUN_E" backend "one more thing" >/dev/null 2>&1
wait_until 10 pid_dead "$LOOP_E"
wait "$LOOP_E"
assert_eq "$?" 1 "turn cap: worker-loop.sh exits 1"
assert_eq "$(last_event_type "$RUN_E" backend)" blocked "turn cap: a blocked event is written"
assert_contains "$(jq -r 'select(.lane == "backend") | .msg' "${RUN_E}/events.jsonl" 2>/dev/null | tail -n 1)" "cap" \
  "turn cap: the message names the cap"

# ─── 6. Crash: the liveness check detects it; resume continues the session ─

REPO_F=$(new_repo)
RUN_F=$(new_run "$REPO_F")
SID_F=$(jq -r '.workers[] | select(.name == "backend") | .session_id' "${RUN_F}/launch/manifest.json" 2>/dev/null)
STUB_F=$(new_stub "slow" "ok")
start_loop "$RUN_F" backend "$STUB_F" STUB_SLOW=30
LOOP_F=$LOOP_PID
wait_until 10 has_calls "$STUB_F" 1
kill -9 "$LOOP_F" 2>/dev/null
kill -9 "$(cat "${STUB_F}/call.1.pid" 2>/dev/null)" 2>/dev/null
wait_until 5 pid_dead "$LOOP_F"
CRASH=$(MONITOR_LIVENESS_INTERVAL=1 MONITOR_MAX_WAIT=5 "$MONITOR" "$RUN_F" 2>/dev/null)
assert_eq "$(jq -r '.type' <<<"$CRASH" 2>/dev/null)" vanished_pane "crash: the monitor reports the dead loop"
assert_eq "$(jq -r '.lane' <<<"$CRASH" 2>/dev/null)" backend "crash: the trigger names the lane"

DEAD_RC=0
DEAD_REPLY=$("$REPLY" "$RUN_F" backend "pick up where you stopped" 2>/dev/null) || DEAD_RC=$?
assert_eq "$DEAD_RC" 1 "crash: reply.sh exits 1 for a dead loop"
assert_eq "$(jq -r '.woken' <<<"$DEAD_REPLY" 2>/dev/null)" false "crash: reply.sh reports woken:false"

start_loop "$RUN_F" backend "$STUB_F"
LOOP_F2=$LOOP_PID
wait_until 10 has_calls "$STUB_F" 2
assert_contains "$(cat "${STUB_F}/call.2.args" 2>/dev/null)" "--resume"$'\n'"$SID_F" \
  "resume: the relaunched loop resumes the same session, never a new one"
assert_contains "$(cat "${STUB_F}/call.2.prompt" 2>/dev/null)" "pick up where you stopped" \
  "resume: the reply sent while the loop was down is delivered"
stop_loop "$RUN_F" backend "$LOOP_F2"

# ─── 7. Resume: an unacked question is replayed; init never runs twice ─────

REPO_G=$(new_repo)
RUN_G=$(new_run "$REPO_G")
"$EVENT" "$RUN_G" backend "2 - Implement the backend service" question "which endpoint shape?"
Q1=$(MONITOR_MAX_WAIT=3 "$MONITOR" "$RUN_G" 2>/dev/null)
Q2=$(MONITOR_MAX_WAIT=3 "$MONITOR" "$RUN_G" 2>/dev/null)
assert_eq "$(jq -r '.type' <<<"$Q2" 2>/dev/null)" question "resume: an unacked question is replayed"
assert_eq "$(jq -r '.seq' <<<"$Q2" 2>/dev/null)" "$(jq -r '.seq' <<<"$Q1" 2>/dev/null)" "resume: the replay is the same event"
assert_exit 0 "$MONITOR" "$RUN_G" --ack "$(jq -r '.seq' <<<"$Q1" 2>/dev/null)"
ACKED_RC=0
ACKED=$(MONITOR_LIVENESS_INTERVAL=1 MONITOR_MAX_WAIT=2 "$MONITOR" "$RUN_G" 2>/dev/null) || ACKED_RC=$?
assert_eq "$(jq -r '.type' <<<"$ACKED" 2>/dev/null)" timeout "ack: an acked question is not replayed"
assert_eq "$ACKED_RC" 1 "ack: the timeout still exits 1"

MANIFEST_SUM=$(shasum "${RUN_G}/manifest.json" "${RUN_G}/launch/manifest.json")
assert_exit 1 "$INIT_RUN" "$FIXTURE_PLAN" "$RUN_G" "$REPO_G" "surface:test"
assert_eq "$(shasum "${RUN_G}/manifest.json" "${RUN_G}/launch/manifest.json")" "$MANIFEST_SUM" \
  "resume: a second init-run.sh leaves both manifests untouched"

# ─── 8. Contract drift, then the gate passes after the drift procedure ─────

emit_round_done() {
  local run="$1" lane
  for lane in backend frontend review; do
    "$EVENT" "$run" "$lane" "round 1" "done" "round finished" >/dev/null
  done
}

REPO_H=$(new_repo)
RUN_H=$(new_run "$REPO_H")
NOT_DONE_RC=0
NOT_DONE=$("$ROUND_GATE" "$RUN_H" 1 --json 2>/dev/null) || NOT_DONE_RC=$?
assert_eq "$NOT_DONE_RC" 1 "gate: a round without done events from every lane fails"
assert_eq "$(jq -r '.[] | select(.item == "round-complete") | .status' <<<"$NOT_DONE" 2>/dev/null)" fail \
  "gate: round-complete names the missing lanes"
"$ROUND_GATE" "$RUN_H" 1 --json >/dev/null 2>&1
"$ROUND_GATE" "$RUN_H" 1 --json >/dev/null 2>&1
assert_contains "$("$ROUND_GATE" "$RUN_H" 1 --json 2>/dev/null)" "retry budget" \
  "gate: a fourth failed attempt on one round stops and asks for a human"

REPO_I=$(new_repo)
RUN_I=$(new_run "$REPO_I")
emit_round_done "$RUN_I"
assert_eq "$(jq -r '.round' <<<"$(tail -n 1 "${RUN_I}/events.jsonl")" 2>/dev/null)" 1 "event.sh: each event carries the round"
assert_exit 0 "$ROUND_GATE" "$RUN_I" 1 --json
printf '{"type":"object","title":"v2"}\n' >"${REPO_I}/contract.schema.json"
git -C "$REPO_I" commit --quiet -am "contract 1.1.0"
assert_exit 1 "$ROUND_GATE" "$RUN_I" 1 --json
assert_exit 0 "$CONTRACT_BUMP" "$RUN_I" 1.1.0
assert_eq "$(jq -r '.contract.version' "${RUN_I}/manifest.json")" 1.1.0 "drift: contract-bump.sh records the new version"
assert_eq "$(jq -r '.checkpoint_commit' "${RUN_I}/manifest.json")" "$(git -C "$REPO_I" rev-parse HEAD)" \
  "drift: contract-bump.sh records the approved checkpoint commit"
DRIFT_JSON=$("$ROUND_GATE" "$RUN_I" 1 --json 2>/dev/null)
assert_eq "$?" 0 "drift: the gate passes after the documented drift procedure"
assert_eq "$(jq -r '.[] | select(.item == "contract-untouched") | .status' <<<"$DRIFT_JSON" 2>/dev/null)" pass \
  "drift: contract-untouched compares against the checkpoint, not the original baseline"

# ─── 9. A gate child that crashes fails the gate ───────────────────────────

TREE="${WORK}/tree/skills"
mkdir -p "$TREE"
cp -R "${SKILLS}/deep-execute" "${SKILLS}/deep-plan" "${SKILLS}/_shared" "$TREE/"
printf '#!/usr/bin/env bash\nexit 3\n' >"${TREE}/deep-execute/scripts/executable_validate-run-state.sh"
REPO_J=$(new_repo)
RUN_J=$(new_run "$REPO_J")
emit_round_done "$RUN_J"
CRASH_RC=0
CRASH_JSON=$(bash "${TREE}/deep-execute/scripts/executable_round-gate.sh" "$RUN_J" 1 --json 2>/dev/null) || CRASH_RC=$?
assert_eq "$CRASH_RC" 1 "gate child crash: round-gate.sh exits 1"
assert_eq "$(jq -r '[.[] | select(.stage == "run-state" and .status == "fail")] | length' <<<"$CRASH_JSON" 2>/dev/null)" 1 \
  "gate child crash: a fail record names the run-state stage"

# ─── 10. Attribution: real log files, one lane logging a path twice ────────

REPO_K=$(new_repo)
RUN_K=$(new_run "$REPO_K")
printf 'echo one\n' >>"${REPO_K}/backend/service.sh"
"$EVENT" "$RUN_K" backend "2 - Implement the backend service" progress "first write" --files backend/service.sh
printf 'echo two\n' >>"${REPO_K}/backend/service.sh"
"$EVENT" "$RUN_K" backend "2 - Implement the backend service" progress "second write" --files backend/service.sh
K_JSON=$("$VALIDATE_STATE" "$RUN_K" --json 2>/dev/null)
assert_eq "$?" 0 "attribution: a path logged twice by its own lane passes"
assert_eq "$(jq -r '.[] | select(.item == "changed-files-attributed-once") | .status' <<<"$K_JSON")" pass \
  "attribution: (lane, path) pairs are deduplicated before counting"
assert_eq "$(jq -r '.[] | select(.item == "worker-file-logs-valid") | .status' <<<"$K_JSON")" pass \
  "attribution: the real log file is read"
printf 'echo unlogged\n' >>"${REPO_K}/frontend/app.sh"
printf 'outside/file.txt\n' >>"${RUN_K}/worker-frontend.files.txt"
K2_JSON=$("$VALIDATE_STATE" "$RUN_K" --json 2>/dev/null)
assert_eq "$?" 0 "attribution: advisory checks never block the gate"
assert_eq "$(jq -r '.[] | select(.item == "changed-files-attributed-once") | .status' <<<"$K2_JSON")" warn \
  "attribution: an unlogged write is a warning"
assert_contains "$(jq -r '.[] | select(.item == "changed-files-attributed-once") | .detail' <<<"$K2_JSON")" "frontend/app.sh" \
  "attribution: the warning names the unlogged path"
assert_eq "$(jq -r '.[] | select(.item == "worker-file-logs-valid") | .status' <<<"$K2_JSON")" warn \
  "attribution: a log entry outside the lane is a warning"

# ─── 11. The orchestrator may append deviations to the stamped plan ────────

REPO_L=$(new_repo)
mkdir -p "${REPO_L}/docs/plan"
cp -R "${FIXTURES}/." "${REPO_L}/docs/plan/"
mv "${REPO_L}/docs/plan/init-run-plan.md" "${REPO_L}/docs/plan/plan.md"
bash "$PLAN_STAMP" approve "${REPO_L}/docs/plan/plan.md" >/dev/null
git -C "$REPO_L" add -A
git -C "$REPO_L" commit --quiet -m "approved plan"
RUN_L=$(new_run "$REPO_L" "${REPO_L}/docs/plan/plan.md")
printf '\n## Deviations\n\n| D-001 | a | b | c | executor |\n' >>"${REPO_L}/docs/plan/plan.md"
L_JSON=$("$VALIDATE_STATE" "$RUN_L" --json 2>/dev/null)
assert_eq "$?" 0 "deviation: a deviation-only edit of the stamped plan passes"
assert_eq "$(jq -r '.[] | select(.item == "changed-files-within-union") | .status' <<<"$L_JSON")" pass \
  "deviation: the plan edit is not an unowned write"
sed -i.bak 's/Initialize lanes from valid plan/Initialize lanes from any plan/' "${REPO_L}/docs/plan/plan.md"
rm -f "${REPO_L}/docs/plan/plan.md.bak"
assert_exit 1 "$VALIDATE_STATE" "$RUN_L" --json

# ─── 12. Agent override, dry run, codex brief on every turn ────────────────

REPO_M=$(new_repo)
RUN_M=$(new_run "$REPO_M" "$FIXTURE_PLAN" --agent "backend=codex gpt-6-sol medium" --max-rounds 5)
assert_eq "$(jq -r '.workers[] | select(.name == "backend") | "\(.runner) \(.model) \(.effort)"' "${RUN_M}/launch/manifest.json" 2>/dev/null)" \
  "codex gpt-6-sol medium" "--agent: the override is persisted in the launch manifest"
assert_eq "$(jq -r '.workers[] | select(.lane == "backend") | .runner' "${RUN_M}/manifest.json" 2>/dev/null)" codex \
  "--agent: the run manifest records the confirmed runner"
assert_eq "$(jq -r '.max_rounds' "${RUN_M}/manifest.json" 2>/dev/null)" 5 "--max-rounds: init-run.sh records the cap"
assert_exit 1 "$INIT_RUN" "$FIXTURE_PLAN" "${WORK}/bad-agent/run" "$REPO_M" "surface:test" --agent "backend=gpt-9 low"

DRY_DIR="${WORK}/dry/run"
DRY_OUT=$("$INIT_RUN" "$FIXTURE_PLAN" "$DRY_DIR" "$REPO_M" "surface:test" --dry-run 2>/dev/null)
assert_eq "$?" 0 "--dry-run: exits 0"
assert_contains "$DRY_OUT" "backend" "--dry-run: lists the lanes"
assert_contains "$DRY_OUT" "contract.schema.json" "--dry-run: names the contract"
assert_contains "$DRY_OUT" "reviews" "--dry-run: states the expected review count"
assert_exit 1 test -e "$DRY_DIR"

STUB_N=$(new_stub "ok")
start_loop "$RUN_M" backend "$STUB_N"
LOOP_N=$LOOP_PID
wait_until 10 has_calls "$STUB_N" 1
"$REPLY" "$RUN_M" backend "codex follow-up" >/dev/null 2>&1
wait_until 10 has_calls "$STUB_N" 2
ARGS_N1=$(cat "${STUB_N}/call.1.args" 2>/dev/null || true)
assert_contains "$ARGS_N1" "exec" "codex: the lane runs codex exec"
assert_contains "$ARGS_N1" "model_reasoning_effort=medium" "codex: the effort is passed"
assert_contains "$ARGS_N1" "--sandbox"$'\n'"workspace-write" "codex: the lane runs in the workspace-write sandbox"
assert_contains "$ARGS_N1" "--add-dir"$'\n'"$RUN_M" "codex: the run directory is writable for event.sh"
assert_contains "$ARGS_N1" "approval_policy=never" "codex: the lane never waits for an approval"
assert_contains "$ARGS_N1" "sandbox_workspace_write.network_access=true" "codex: the lane keeps network access"
assert_eq "$(printf '%s' "$ARGS_N1" | grep -c 'dangerously' || true)" 0 "codex: the lane never bypasses the sandbox"
PROMPT_N2=$(cat "${STUB_N}/call.2.prompt" 2>/dev/null || true)
assert_contains "$PROMPT_N2" "Never run \`git\`" "codex: every stateless turn carries the worker rules"
assert_contains "$PROMPT_N2" "2 - Implement the backend service" "codex: every stateless turn carries the brief"
assert_contains "$PROMPT_N2" "codex follow-up" "codex: the follow-up turn carries the reply"
stop_loop "$RUN_M" backend "$LOOP_N"

# ─── 13. A lane that runs git hits the PATH shim, for both runners ─────────

for RUNNER_O in claude codex; do
  REPO_O=$(new_repo)
  if [ "$RUNNER_O" = codex ]; then
    RUN_O=$(new_run "$REPO_O" "$FIXTURE_PLAN" --agent "backend=codex gpt-6-sol medium")
  else
    RUN_O=$(new_run "$REPO_O")
  fi
  STUB_O=$(new_stub "git")
  start_loop "$RUN_O" backend "$STUB_O"
  LOOP_O=$LOOP_PID
  wait_until 10 test -f "${STUB_O}/call.1.git.rc"
  assert_eq "$(cat "${STUB_O}/call.1.git.rc" 2>/dev/null)" 1 "git shim (${RUNNER_O}): git status exits 1 inside a lane"
  assert_contains "$(cat "${STUB_O}/call.1.git.err" 2>/dev/null)" "workers never run git; the orchestrator commits" \
    "git shim (${RUNNER_O}): the shim names the rule"
  stop_loop "$RUN_O" backend "$LOOP_O"
done

# ─── 14. contract-bump.sh refuses to absorb other changes into the checkpoint ─

REPO_P=$(new_repo)
RUN_P=$(new_run "$REPO_P")
P_MANIFEST=$(shasum "${RUN_P}/manifest.json")
printf '# readme v2\n' >"${REPO_P}/README.md"
git -C "$REPO_P" commit --quiet -am "edit a shared file"
printf '{"type":"object","title":"v2"}\n' >"${REPO_P}/contract.schema.json"
git -C "$REPO_P" commit --quiet -am "contract 1.1.0"
P_RC=0
P_ERR=$("$CONTRACT_BUMP" "$RUN_P" 1.1.0 2>&1 >/dev/null) || P_RC=$?
assert_eq "$P_RC" 1 "bump: a changed shared_read_only file refuses the bump"
assert_contains "$P_ERR" "README.md" "bump: the refusal names the shared file"
assert_eq "$(shasum "${RUN_P}/manifest.json")" "$P_MANIFEST" "bump: a refused bump leaves the manifest untouched"

REPO_Q=$(new_repo)
RUN_Q=$(new_run "$REPO_Q")
Q_MANIFEST=$(shasum "${RUN_Q}/manifest.json")
printf '{"type":"object","title":"v2"}\n' >"${REPO_Q}/contract.schema.json"
printf 'echo smuggled\n' >>"${REPO_Q}/backend/service.sh"
git -C "$REPO_Q" commit --quiet -am "contract 1.1.0 and a lane file"
Q_RC=0
Q_ERR=$("$CONTRACT_BUMP" "$RUN_Q" 1.1.0 2>&1 >/dev/null) || Q_RC=$?
assert_eq "$Q_RC" 1 "bump: a contract commit that also touches another file refuses the bump"
assert_contains "$Q_ERR" "backend/service.sh" "bump: the refusal names the extra file"
assert_eq "$(shasum "${RUN_Q}/manifest.json")" "$Q_MANIFEST" "bump: a mixed-commit refusal leaves the manifest untouched"

REPO_R=$(new_repo)
RUN_R=$(new_run "$REPO_R")
printf 'echo lane work\n' >>"${REPO_R}/backend/service.sh"
git -C "$REPO_R" commit --quiet -am "round 1 lane work"
printf '{"type":"object","title":"v2"}\n' >"${REPO_R}/contract.schema.json"
git -C "$REPO_R" commit --quiet -am "contract 1.1.0"
assert_exit 0 "$CONTRACT_BUMP" "$RUN_R" 1.1.0
assert_eq "$(jq -r '.checkpoint_commit' "${RUN_R}/manifest.json")" "$(git -C "$REPO_R" rev-parse HEAD)" \
  "bump: lane commits and a contract-only commit pass"

assert_summary
