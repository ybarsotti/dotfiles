#!/usr/bin/env bash
# round-gate.sh — decides whether a deep-execute round may advance.
#
# Usage:
#   round-gate.sh RUN_DIR ROUND [--json]
#
# Runs, in this FIXED order, short-circuiting on the first failure:
#   1. round-bound   — ROUND must be <= manifest.json's max_rounds
#   2. lane-tests     — every worker lane's own `test_command` (from the
#                        plan) must pass
#   3. contract       — validate-contract.sh --json
#   4. run-state      — validate-run-state.sh --json
#   5. review         — one light reviewer pass (deep-review's
#                        project-patterns persona) must APPROVE
#
# The order is deliberate: cheapest/fastest checks first, the reviewer (an
# LLM call) last, so a lane-test failure never pays for a contract check,
# a run-state check, or a reviewer call that a later stage would have made
# irrelevant anyway. Once STOP is set, every later stage records exactly one
# `skipped` item instead of running — the emitted JSON always shows which
# stage failed and which never ran; it never claims a stage passed when it
# was skipped, and never silently omits a stage from the report.
#
# Every record carries {stage, item, status, detail} — `stage` groups the
# many sub-items validate-contract.sh / validate-run-state.sh each already
# emit under the one round-gate stage that ran them.
#
# ROUND > max_rounds is refused outright (an escalation record: the
# round-bound item fails, every other stage is skipped) — max_rounds lives
# in manifest.json (not hardcoded here a second time) so a plan that sets a
# different ceiling is honored without editing this script.
#
# The reviewer step reuses deep-review's reviewer.sh and its
# project-patterns persona verbatim, but that persona (like every
# deep-review persona) has no fixed output contract of its own — dispatch.sh
# normally appends one. Since this is a single ad hoc reviewer call, not a
# full dispatch.sh run, the same minimal addition is made here: the copied
# persona file gets one short "required output format" section appended
# (asking for a single trailing `VERDICT: APPROVE|REQUEST_CHANGES|REJECT`
# line) so this script can determine approval deterministically instead of
# guessing at prose. A reviewer response with no such line, or a
# non-APPROVE verdict, both fail the item.
set -uo pipefail

RESULTS=()
record() {
  local stage="$1" item="$2" status="$3" detail="$4"
  RESULTS+=("$(jq -n --arg st "$stage" --arg i "$item" --arg s "$status" --arg d "$detail" \
    '{stage:$st, item:$i, status:$s, detail:$d}')")
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
DEEP_REVIEW_DIR="$(cd "${SCRIPT_DIR}/../../deep-review" && pwd)"

PARSER="${DEEP_PLAN_SCRIPTS}/plan-to-json.sh"
[ -f "$PARSER" ] || PARSER="${DEEP_PLAN_SCRIPTS}/executable_plan-to-json.sh"
VALIDATE_CONTRACT="${SCRIPT_DIR}/validate-contract.sh"
[ -f "$VALIDATE_CONTRACT" ] || VALIDATE_CONTRACT="${SCRIPT_DIR}/executable_validate-contract.sh"
VALIDATE_STATE="${SCRIPT_DIR}/validate-run-state.sh"
[ -f "$VALIDATE_STATE" ] || VALIDATE_STATE="${SCRIPT_DIR}/executable_validate-run-state.sh"
REVIEWER="${DEEP_REVIEW_DIR}/scripts/reviewer.sh"
[ -f "$REVIEWER" ] || REVIEWER="${DEEP_REVIEW_DIR}/scripts/executable_reviewer.sh"
PERSONA_FILE="${DEEP_REVIEW_DIR}/personas/project-patterns.md"

CWD=$(jq -r '.cwd' "$MANIFEST")
BASELINE_COMMIT=$(jq -r '.baseline_commit' "$MANIFEST")
PLAN_PATH=$(jq -r '.plan_path' "$MANIFEST")
MAX_ROUNDS=$(jq -r '.max_rounds' "$MANIFEST")

STOP=0
SKIP_REASON=""

# ─── Stage 1: round-bound ───────────────────────────────────────────────────
if ! [[ "$ROUND" =~ ^[0-9]+$ ]]; then
  record "round-bound" "round-within-max-rounds" "fail" "ROUND '${ROUND}' is not a non-negative integer"
  STOP=1
  SKIP_REASON="short-circuited: 'round-bound' failed (malformed ROUND)"
elif [ "$ROUND" -gt "$MAX_ROUNDS" ]; then
  record "round-bound" "round-within-max-rounds" "fail" "round ${ROUND} exceeds max_rounds=${MAX_ROUNDS} (from ${MANIFEST}) — refusing to gate; escalate to a human decision"
  STOP=1
  SKIP_REASON="short-circuited: 'round-bound' failed (round ${ROUND} > max_rounds ${MAX_ROUNDS})"
else
  record "round-bound" "round-within-max-rounds" "pass" "round ${ROUND} is within max_rounds=${MAX_ROUNDS}"
fi

# ─── Stage 2: lane-tests ─────────────────────────────────────────────────────
if [ "$STOP" -eq 1 ]; then
  record "lane-tests" "lane-tests" "skipped" "not run: ${SKIP_REASON}"
else
  if [ ! -f "$PLAN_PATH" ]; then
    record "lane-tests" "lane-tests" "fail" "plan_path from manifest does not exist: ${PLAN_PATH}"
    STOP=1
    SKIP_REASON="short-circuited: 'lane-tests' failed (missing plan)"
  else
    PLAN_JSON=$("$PARSER" "$PLAN_PATH" 2>/dev/null) || PLAN_JSON=""
    if [ -z "$PLAN_JSON" ]; then
      record "lane-tests" "lane-tests" "fail" "plan-to-json.sh could not parse ${PLAN_PATH}"
      STOP=1
      SKIP_REASON="short-circuited: 'lane-tests' failed (plan did not parse)"
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
          record "lane-tests" "lane-test:${lane}" "fail" "test_command failed: ${TEST_CMD}: ${TEST_OUT}"
          LANE_FAIL=1
        fi
      done < <(jq -r '.workers[]?.lane // empty' "$MANIFEST")
      if [ "$LANE_FAIL" -eq 1 ]; then
        STOP=1
        SKIP_REASON="short-circuited: 'lane-tests' failed (see lane-test:<lane> items)"
      fi
    fi
  fi
fi

# ─── Stage 3: contract ──────────────────────────────────────────────────────
if [ "$STOP" -eq 1 ]; then
  record "contract" "contract" "skipped" "not run: ${SKIP_REASON}"
else
  CONTRACT_JSON=$("$VALIDATE_CONTRACT" "$RUN_DIR" --json) || CONTRACT_RC=$?
  CONTRACT_RC="${CONTRACT_RC:-0}"
  if [ -n "${CONTRACT_JSON:-}" ]; then
    while IFS= read -r item; do
      [ -z "$item" ] && continue
      record "contract" "$(jq -r '.item' <<<"$item")" "$(jq -r '.status' <<<"$item")" "$(jq -r '.detail' <<<"$item")"
    done < <(jq -c '.[]' <<<"$CONTRACT_JSON")
  fi
  if [ "$CONTRACT_RC" -ne 0 ]; then
    STOP=1
    SKIP_REASON="short-circuited: 'contract' failed (see contract:* items)"
  fi
fi

# ─── Stage 4: run-state ─────────────────────────────────────────────────────
if [ "$STOP" -eq 1 ]; then
  record "run-state" "run-state" "skipped" "not run: ${SKIP_REASON}"
else
  STATE_JSON=$("$VALIDATE_STATE" "$RUN_DIR" --json) || STATE_RC=$?
  STATE_RC="${STATE_RC:-0}"
  if [ -n "${STATE_JSON:-}" ]; then
    while IFS= read -r item; do
      [ -z "$item" ] && continue
      # validate-run-state.sh's own exit code already treats `warn` as
      # non-blocking (see that script's header) — its records are merged
      # here verbatim, `warn` included, and STOP below follows ITS exit
      # code rather than re-deriving pass/fail from these items by hand.
      record "run-state" "$(jq -r '.item' <<<"$item")" "$(jq -r '.status' <<<"$item")" "$(jq -r '.detail' <<<"$item")"
    done < <(jq -c '.[]' <<<"$STATE_JSON")
  fi
  if [ "$STATE_RC" -ne 0 ]; then
    STOP=1
    SKIP_REASON="short-circuited: 'run-state' failed (see run-state:* items)"
  fi
fi

# ─── Stage 5: review (one reviewer, reused from deep-review) ───────────────
if [ "$STOP" -eq 1 ]; then
  record "review" "review" "skipped" "not run: ${SKIP_REASON}"
else
  REVIEWER_DIR="${RUN_DIR}/light-review/round-${ROUND}"
  mkdir -p "${REVIEWER_DIR}/reviewers"
  if [ -f "$PERSONA_FILE" ]; then
    cp "$PERSONA_FILE" "${REVIEWER_DIR}/reviewers/deep-execute-round.prompt.md"
    {
      printf '\n## Required output format\n\n'
      printf 'End your entire response with exactly one line, and nothing after it:\n\n'
      # shellcheck disable=SC2016 # literal backticked text in the printed prompt, not a command substitution
      printf '`VERDICT: APPROVE` or `VERDICT: REQUEST_CHANGES` or `VERDICT: REJECT`\n'
    } >>"${REVIEWER_DIR}/reviewers/deep-execute-round.prompt.md"
    git -C "$CWD" diff --no-ext-diff "${BASELINE_COMMIT}" -- >"${REVIEWER_DIR}/context.md" 2>/dev/null || : >"${REVIEWER_DIR}/context.md"

    RESULT_FILE="${REVIEWER_DIR}/result.md"
    REVIEWER_RC=0
    # Invoked via `bash "$REVIEWER"` rather than executing it directly — see
    # reply.sh's identical note on send-task.sh: this script has no business
    # depending on another skill's source-tree executable bit.
    bash "$REVIEWER" claude deep-execute-round "$REVIEWER_DIR" 600 >"$RESULT_FILE" 2>"${REVIEWER_DIR}/reviewer.log" || REVIEWER_RC=$?

    VERDICT_LINE=$(grep -oE '^VERDICT: (APPROVE|REQUEST_CHANGES|REJECT)$' "$RESULT_FILE" 2>/dev/null | tail -n1 || true)
    VERDICT="${VERDICT_LINE#VERDICT: }"

    if [ "$REVIEWER_RC" -ne 0 ] && [ -z "$VERDICT" ]; then
      record "review" "light-review-verdict" "fail" "reviewer.sh exited ${REVIEWER_RC} and produced no VERDICT line — see ${REVIEWER_DIR}/reviewer.log"
      STOP=1
    elif [ -z "$VERDICT" ]; then
      record "review" "light-review-verdict" "fail" "no VERDICT line found in reviewer output — see ${RESULT_FILE}"
      STOP=1
    elif [ "$VERDICT" = "APPROVE" ]; then
      record "review" "light-review-verdict" "pass" "reviewer approved — see ${RESULT_FILE}"
    else
      record "review" "light-review-verdict" "fail" "reviewer verdict: ${VERDICT} — see ${RESULT_FILE}"
      STOP=1
    fi
  else
    record "review" "light-review-verdict" "fail" "missing reviewer persona: ${PERSONA_FILE}"
    STOP=1
  fi
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
  if [ "$FAILS" -eq 0 ]; then
    echo "verdict: ROUND ${ROUND} MAY ADVANCE"
  else
    echo "verdict: $FAILS FAIL — ROUND ${ROUND} BLOCKED"
  fi
fi

[ "$FAILS" -eq 0 ] && exit 0 || exit 1
