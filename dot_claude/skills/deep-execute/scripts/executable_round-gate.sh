#!/usr/bin/env bash
# round-gate.sh — decides whether a deep-execute round may advance.
#
# Usage:
#   round-gate.sh RUN_DIR ROUND [--json]
#
# Runs, in this FIXED order, short-circuiting on the first failure:
#   1. round-bound    — ROUND must be <= manifest.json's max_rounds, and the
#                       failed-attempt budget of the round must not be spent
#   2. round-complete — every worker lane emitted `done` in ROUND (each event
#                       carries the round that event.sh read from the manifest)
#   3. lane-tests     — every worker lane's own `test_command` passes
#   4. acceptance     — every runnable requirement command passes
#   5. contract       — validate-contract.sh --json
#   6. run-state      — validate-run-state.sh --json
#
# Cheapest checks first. Once one stage fails, every later stage records one
# `skipped` item: the JSON always shows which stage failed and which never
# ran, and never reports a skipped stage as passed.
#
# A child validator that exits nonzero without a fail record, or prints no
# parseable result, is itself a failure — a crash never reads as a pass.
#
# Retry budget. Each failed gate of a round is counted in
# RUN_DIR/gate/round-<N>.fails. After ROUND_GATE_MAX_FAILS failures (default
# 3) the gate refuses the round and asks for a human, so a round that never
# converges cannot loop below the max_rounds cap forever.
#
# There is no LLM review stage: the /deep-review that closes each round is the
# review, and it reads the round's commits plus untracked files.
set -uo pipefail

RESULTS=()
record() {
  local stage="$1" item="$2" status="$3" detail="$4"
  RESULTS+=("$(jq -n --arg st "$stage" --arg i "$item" --arg s "$status" --arg d "$detail" \
    '{stage:$st, item:$i, status:$s, detail:$d}')")
}

# short_circuit STAGE [REASON] — every later stage records `skipped` with this reason.
short_circuit() {
  STOP=1
  SKIP_REASON="short-circuited: '$1' failed${2:+ ($2)}"
}

if [ $# -lt 2 ]; then
  echo "Usage: round-gate.sh RUN_DIR ROUND [--json]" >&2
  exit 2
fi
RUN_DIR="$1"
ROUND="$2"
shift 2
JSON_OUT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON_OUT=1; shift ;;
    *)
      echo "round-gate.sh: unknown flag '$1'" >&2
      exit 2
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  echo "round-gate.sh: jq required" >&2
  exit 2
}

MANIFEST="${RUN_DIR}/manifest.json"
if [ ! -f "$MANIFEST" ] || ! jq -e . "$MANIFEST" >/dev/null 2>&1; then
  echo "round-gate.sh: missing or invalid JSON: ${MANIFEST}" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEEP_PLAN_SCRIPTS="$(cd "${SCRIPT_DIR}/../../deep-plan/scripts" && pwd)"

PARSER="${DEEP_PLAN_SCRIPTS}/plan-to-json.sh"
[ -f "$PARSER" ] || PARSER="${DEEP_PLAN_SCRIPTS}/executable_plan-to-json.sh"
VALIDATE_CONTRACT="${SCRIPT_DIR}/validate-contract.sh"
[ -f "$VALIDATE_CONTRACT" ] || VALIDATE_CONTRACT="${SCRIPT_DIR}/executable_validate-contract.sh"
VALIDATE_STATE="${SCRIPT_DIR}/validate-run-state.sh"
[ -f "$VALIDATE_STATE" ] || VALIDATE_STATE="${SCRIPT_DIR}/executable_validate-run-state.sh"

CWD=$(jq -r '.cwd' "$MANIFEST")
PLAN_PATH=$(jq -r '.plan_path' "$MANIFEST")
MAX_ROUNDS=$(jq -r '.max_rounds' "$MANIFEST")

STOP=0
SKIP_REASON=""

# ─── Stage 1: round-bound ───────────────────────────────────────────────────
GATE_DIR="${RUN_DIR}/gate"
FAILS_FILE="${GATE_DIR}/round-${ROUND}.fails"
MAX_FAILS="${ROUND_GATE_MAX_FAILS:-3}"
PRIOR_FAILS=$(cat "$FAILS_FILE" 2>/dev/null || echo 0)
case "$PRIOR_FAILS" in '' | *[!0-9]*) PRIOR_FAILS=0 ;; esac
if ! [[ "$ROUND" =~ ^[0-9]+$ ]]; then
  record "round-bound" "round-within-max-rounds" "fail" "ROUND '${ROUND}' is not a non-negative integer"
  short_circuit "round-bound" "malformed ROUND"
elif ! [[ "$MAX_ROUNDS" =~ ^[1-9][0-9]*$ ]]; then
  record "round-bound" "round-within-max-rounds" "fail" "manifest max_rounds is '${MAX_ROUNDS}', not a positive integer — refusing to gate"
  short_circuit "round-bound" "no max_rounds"
elif [ "$ROUND" -gt "$MAX_ROUNDS" ]; then
  record "round-bound" "round-within-max-rounds" "fail" "round ${ROUND} exceeds max_rounds=${MAX_ROUNDS} (from ${MANIFEST}) — refusing to gate; escalate to a human decision"
  short_circuit "round-bound" "round ${ROUND} > max_rounds ${MAX_ROUNDS}"
elif [ "$PRIOR_FAILS" -ge "$MAX_FAILS" ]; then
  record "round-bound" "round-retry-budget" "fail" "the retry budget of round ${ROUND} is spent: ${PRIOR_FAILS} failed gates of ${MAX_FAILS} — escalate to a human decision"
  short_circuit "round-bound" "retry budget spent"
else
  record "round-bound" "round-within-max-rounds" "pass" "round ${ROUND} is within max_rounds=${MAX_ROUNDS}; ${PRIOR_FAILS} of ${MAX_FAILS} failed gates used"
fi

# ─── Stage 1b: round-complete ───────────────────────────────────────────────
if [ "$STOP" -eq 1 ]; then
  record "round-complete" "round-complete" "skipped" "not run: ${SKIP_REASON}"
else
  MISSING_DONE=$(jq -rn --argjson r "$ROUND" --slurpfile m "$MANIFEST" '
    [inputs | select(type == "object" and .type == "done" and .round == $r) | .lane] as $done
    | [$m[0].workers[]?.lane | select(. as $l | $done | index($l) | not)] | join(", ")' \
    "${RUN_DIR}/events.jsonl" 2>/dev/null || echo "events.jsonl unreadable")
  if [ -z "$MISSING_DONE" ]; then
    record "round-complete" "round-complete" "pass" "every worker lane emitted done in round ${ROUND}"
  else
    record "round-complete" "round-complete" "fail" "no done event in round ${ROUND} from: ${MISSING_DONE}"
    short_circuit "round-complete"
  fi
fi

# ─── Stage 2: lane-tests ─────────────────────────────────────────────────────
PLAN_JSON=""
if [ "$STOP" -eq 0 ] && [ -f "$PLAN_PATH" ]; then
  PLAN_JSON=$("$PARSER" "$PLAN_PATH" 2>/dev/null) || PLAN_JSON=""
fi
if [ "$STOP" -eq 1 ]; then
  record "lane-tests" "lane-tests" "skipped" "not run: ${SKIP_REASON}"
elif [ ! -f "$PLAN_PATH" ]; then
  record "lane-tests" "lane-tests" "fail" "plan_path from manifest does not exist: ${PLAN_PATH}"
  short_circuit "lane-tests" "missing plan"
elif [ -z "$PLAN_JSON" ]; then
  record "lane-tests" "lane-tests" "fail" "plan-to-json.sh could not parse ${PLAN_PATH}"
  short_circuit "lane-tests" "plan did not parse"
else
  LANE_FAIL=0
  while IFS= read -r lane; do
    [ -z "$lane" ] && continue
    TEST_CMD=$(jq -r --arg n "$lane" '.lanes[]? | select(.name == $n) | .test_command // empty' <<<"$PLAN_JSON")
    if [ -z "$TEST_CMD" ]; then
      record "lane-tests" "lane-test:${lane}" "fail" "no test_command declared for lane '${lane}' in ${PLAN_PATH}"
      LANE_FAIL=1
      continue
    fi
    if TEST_OUT=$(cd "$CWD" && sh -c "$TEST_CMD" 2>&1); then
      record "lane-tests" "lane-test:${lane}" "pass" "test_command succeeded: ${TEST_CMD}"
    else
      # Truncate to a bounded tail: a full failing suite's output (e.g.
      # 1000+ pytest error lines) overflows ARG_MAX when passed to
      # `jq --arg d`, which silently drops the whole record and makes the
      # gate report "no result" instead of "failed". A tail is enough to
      # diagnose; the full log is on the worker's own pane.
      TEST_TAIL=$(printf '%s\n' "$TEST_OUT" | tail -40)
      record "lane-tests" "lane-test:${lane}" "fail" "test_command failed: ${TEST_CMD}: ...(tail)... ${TEST_TAIL}"
      LANE_FAIL=1
    fi
  done < <(jq -r '.workers[]?.lane // empty' "$MANIFEST")
  [ "$LANE_FAIL" -eq 0 ] || short_circuit "lane-tests" "see lane-test:<lane> items"
fi

# ─── Stage 2b: acceptance ───────────────────────────────────────────────────
# Runs the requirements matrix. Until now "requirement satisfied" was an agent's
# claim that nothing compared against reality: the matrix carried a `verification`
# column, and no script had ever read it.
#
# A cell holding exactly one backticked span is a command and gets executed. Prose
# is recorded `warn`, never `fail` — plenty of criteria are genuinely observed
# rather than run (a screenshot, a human looking at a screen), and failing those
# would push planners to write a fake command to silence the gate, which is worse
# than the prose it replaced. A plan with NO runnable criterion at all is still a
# passing plan; it just says so out loud, once, instead of implying it verified
# something.
if [ "$STOP" -eq 1 ]; then
  record "acceptance" "acceptance" "skipped" "not run: ${SKIP_REASON}"
elif [ -z "$PLAN_JSON" ]; then
  record "acceptance" "acceptance" "skipped" "not run: plan did not parse"
else
  ACCEPT_FAIL=0
  RUNNABLE=0
  PROSE=0
  while IFS=$'\t' read -r req cmd; do
    [ -z "$req" ] && continue
    if [ -z "$cmd" ]; then
      PROSE=$((PROSE + 1))
      continue
    fi
    RUNNABLE=$((RUNNABLE + 1))
    if ACC_OUT=$(cd "$CWD" && sh -c "$cmd" 2>&1); then
      record "acceptance" "acceptance:${req}" "pass" "verification command succeeded: ${cmd}"
    else
      # Same bounded tail as lane-tests, for the same reason: a full failing suite
      # overflows ARG_MAX and silently drops the record.
      ACC_TAIL=$(printf '%s\n' "$ACC_OUT" | tail -40)
      record "acceptance" "acceptance:${req}" "fail" "verification command failed: ${cmd}: ...(tail)... ${ACC_TAIL}"
      ACCEPT_FAIL=1
    fi
  done < <(jq -r '.requirements[]? | "\(.requirement)\t\(.command // "")"' <<<"$PLAN_JSON")

  if [ "$PROSE" -gt 0 ]; then
    record "acceptance" "acceptance-not-machine-checked" "warn" \
      "${PROSE} requirement(s) carry prose rather than a runnable command, so nothing verified them — only ${RUNNABLE} of $((PROSE + RUNNABLE)) is checked by a script"
  elif [ "$RUNNABLE" -eq 0 ]; then
    record "acceptance" "acceptance" "warn" "the plan declares no requirements matrix rows to check"
  fi
  [ "$ACCEPT_FAIL" -eq 0 ] || short_circuit "acceptance" "see acceptance:<requirement> items"
fi

# run_child STAGE CMD... — merges the child's records; a nonzero exit without
# a fail record, or output that is not a JSON array, records its own failure.
run_child() {
  local stage="$1" out rc=0 item
  shift
  out=$("$@" 2>/dev/null) || rc=$?
  if jq -e 'type == "array"' <<<"$out" >/dev/null 2>&1; then
    while IFS= read -r item; do
      record "$stage" "$(jq -r '.item' <<<"$item")" "$(jq -r '.status' <<<"$item")" "$(jq -r '.detail' <<<"$item")"
    done < <(jq -c '.[]' <<<"$out")
    if [ "$rc" -ne 0 ] && ! jq -e 'any(.[]; .status == "fail")' <<<"$out" >/dev/null; then
      record "$stage" "${stage}-exit" "fail" "$(basename "$1") exited ${rc} without a fail record"
    fi
  else
    [ "$rc" -ne 0 ] || rc=1
    record "$stage" "${stage}-exit" "fail" "$(basename "$1") exited ${rc} with no parseable result"
  fi
  [ "$rc" -eq 0 ] || short_circuit "$stage" "see ${stage} items"
}

# ─── Stage 3: contract ──────────────────────────────────────────────────────
if [ "$STOP" -eq 1 ]; then
  record "contract" "contract" "skipped" "not run: ${SKIP_REASON}"
else
  run_child "contract" "$VALIDATE_CONTRACT" "$RUN_DIR" --json
fi

# ─── Stage 4: run-state ─────────────────────────────────────────────────────
# validate-run-state.sh exits nonzero only on `fail`; its `warn` records merge
# here verbatim and never block.
if [ "$STOP" -eq 1 ]; then
  record "run-state" "run-state" "skipped" "not run: ${SKIP_REASON}"
else
  run_child "run-state" "$VALIDATE_STATE" "$RUN_DIR" --json
fi

# ─── Output ─────────────────────────────────────────────────────────────
ALL_JSON=$(printf '%s\n' "${RESULTS[@]}" | jq -s '.')
FAILS=$(echo "$ALL_JSON" | jq '[.[] | select(.status == "fail")] | length')

if [ "$JSON_OUT" -eq 1 ]; then
  echo "$ALL_JSON"
else
  printf "## round-gate: %s (round %s)\n\n" "$RUN_DIR" "$ROUND"
  echo "$ALL_JSON" | jq -r '.[] | "- [" + (if .status == "pass" then "x" elif .status == "skipped" then "-" elif .status == "warn" then "~" else " " end) + "] " + .stage + ":" + .item + " — " + .detail'
  echo
  if [ "$FAILS" -eq 0 ] && [ "$STOP" -eq 0 ]; then
    echo "verdict: ROUND ${ROUND} MAY ADVANCE"
  else
    echo "verdict: $FAILS FAIL — ROUND ${ROUND} BLOCKED"
  fi
fi

if [ "$FAILS" -eq 0 ] && [ "$STOP" -eq 0 ]; then
  exit 0
fi
if [[ "$ROUND" =~ ^[0-9]+$ ]]; then
  mkdir -p "$GATE_DIR"
  printf '%s\n' "$((PRIOR_FAILS + 1))" >"$FAILS_FILE"
fi
exit 1
