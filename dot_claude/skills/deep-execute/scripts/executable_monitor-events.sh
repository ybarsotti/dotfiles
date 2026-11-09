#!/usr/bin/env bash
# monitor-events.sh — blocks until one trigger fires, prints ONE trigger JSON
# line, and exits. It never reports success by silence.
#
# Usage:
#   monitor-events.sh RUN_DIR             wait for the next trigger
#   monitor-events.sh RUN_DIR --ack SEQ   mark event line SEQ as handled
#
# Triggers:
#   question | waiting | blocked | done   an event line of that type
#   invalid_event                         a line that fails schemas/event.jq
#   vanished_pane                         a lane's worker loop is not running
#   fatal_signature                       a fatal pattern in a lane's worker.log
#   monitor_error                         the tail on events.jsonl ended (exit 1)
#   timeout                               MONITOR_MAX_WAIT passed (exit 1)
# Every other trigger exits 0, so callers branch on `.type`, never on the exit code.
#
# Output: {"type", "lane", "task", "msg", "seq", "run_dir"}. `seq` is the line
# number of the event in events.jsonl, or null for a trigger that is not a line.
#
# Read position and acknowledgement are separate. The watermark in
# RUN_DIR/.monitor-events-state/events.watermark is the last HANDLED line. An
# informational line (task_start, task_done, progress, decision) is handled
# when it is read. A trigger line is handled only when the orchestrator calls
# `--ack SEQ` after it acted on it. Until then every call reports the same
# trigger again, so a crash between the trigger and the reply loses nothing:
# resume replays every unacknowledged question, waiting and blocked event.
#
# Backlog and live events are ONE stream: `tail -n +K -F`, with K the line
# after the watermark. There is no count-then-attach seam in which a line can
# land unseen.
#
# Liveness runs on the wall clock: once at start (the resume probe) and then
# every MONITOR_LIVENESS_INTERVAL seconds, also while events keep arriving.
# For each lane with lanes/<lane>/loop.pid and no lanes/<lane>/stop file:
#   - a pid that `kill -0` cannot reach is `vanished_pane` (once per pid);
#   - a new line of lanes/<lane>/worker.log that matches FATAL_REGEX is
#     `fatal_signature` (each line is scanned once).
#
# Bounds (seconds): MONITOR_LIVENESS_INTERVAL (default 30), MONITOR_MAX_WAIT
# (default 1800, wall clock). MONITOR_TEST_DELAY_BEFORE_TAIL is test-only: it
# sleeps right before the tail attaches, to prove that the seam is gone.
set -eufo pipefail

FATAL_REGEX='panic|fatal|segmentation fault|killed|traceback|unhandled'

RUN_DIR="${1:-}"
if [ -z "$RUN_DIR" ]; then
  echo "Usage: monitor-events.sh RUN_DIR [--ack SEQ]" >&2
  exit 2
fi

MANIFEST="${RUN_DIR}/manifest.json"
EVENTS="${RUN_DIR}/events.jsonl"
EVENT_JQ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../schemas" && pwd)/event.jq"

[ -f "$MANIFEST" ] || {
  echo "monitor-events.sh: missing ${MANIFEST}" >&2
  exit 2
}
command -v jq >/dev/null 2>&1 || {
  echo "monitor-events.sh: jq required" >&2
  exit 2
}
[ -f "$EVENTS" ] || : >"$EVENTS"

STATE_DIR="${RUN_DIR}/.monitor-events-state"
mkdir -p "$STATE_DIR"
WATERMARK_FILE="${STATE_DIR}/events.watermark"
PREV_LINES=$(cat "$WATERMARK_FILE" 2>/dev/null || echo 0)
case "$PREV_LINES" in '' | *[!0-9]*) PREV_LINES=0 ;; esac

if [ "${2:-}" = "--ack" ]; then
  case "${3:-}" in
    '' | *[!0-9]*)
      echo "monitor-events.sh: --ack needs a line number" >&2
      exit 2
      ;;
  esac
  [ "$3" -le "$PREV_LINES" ] || printf '%s' "$3" >"$WATERMARK_FILE"
  jq -cn --argjson seq "$3" '{acked: $seq}'
  exit 0
fi

LIVENESS_INTERVAL="${MONITOR_LIVENESS_INTERVAL:-30}"
MAX_WAIT="${MONITOR_MAX_WAIT:-1800}"
[ "$LIVENESS_INTERVAL" -gt 0 ] 2>/dev/null || LIVENESS_INTERVAL=1

# emit TYPE LANE TASK MSG [SEQ] [EXIT_CODE] — prints the one trigger and exits.
emit() {
  jq -cn --arg type "$1" --arg lane "$2" --arg task "$3" --arg msg "$4" --arg seq "${5:-}" \
    --arg run_dir "$RUN_DIR" \
    '{type: $type, lane: (if $lane == "" then null else $lane end),
      task: (if $task == "" then null else $task end), msg: $msg,
      seq: (if $seq == "" then null else ($seq | tonumber) end), run_dir: $run_dir}'
  exit "${6:-0}"
}

# handle_line LINE SEQ — a trigger exits; an informational line returns 0.
handle_line() {
  local line="$1" seq="$2" type
  [ -z "$line" ] && return 0
  if ! jq -e -f "$EVENT_JQ" <<<"$line" >/dev/null 2>&1; then
    emit "invalid_event" "$(jq -r '.lane // empty' <<<"$line" 2>/dev/null || true)" "" "$line" "$seq"
  fi
  type=$(jq -r '.type' <<<"$line")
  case "$type" in
    question | waiting | blocked | done)
      emit "$type" "$(jq -r '.lane' <<<"$line")" "$(jq -r '.task' <<<"$line")" "$(jq -r '.msg' <<<"$line")" "$seq"
      ;;
  esac
  printf '%s' "$seq" >"$WATERMARK_FILE"
}

LANES=()
while IFS= read -r l; do
  [ -n "$l" ] && LANES+=("$l")
done < <(jq -r '.workers[]?.lane // empty' "$MANIFEST" 2>/dev/null)

do_liveness_check() {
  local lane dir pid log state total prev match
  for lane in "${LANES[@]+"${LANES[@]}"}"; do
    dir="${RUN_DIR}/lanes/${lane}"
    pid=$(cat "${dir}/loop.pid" 2>/dev/null || true)
    [ -n "$pid" ] || continue
    [ ! -f "${dir}/stop" ] || continue
    if ! kill -0 "$pid" 2>/dev/null; then
      state="${STATE_DIR}/vanished-${lane}"
      if [ "$(cat "$state" 2>/dev/null || true)" != "$pid" ]; then
        printf '%s' "$pid" >"$state"
        emit "vanished_pane" "$lane" "" "worker loop ${pid} of lane ${lane} is not running"
      fi
      continue
    fi
    log="${dir}/worker.log"
    [ -f "$log" ] || continue
    state="${STATE_DIR}/log-${lane}.lines"
    total=$(wc -l <"$log" | tr -d ' ')
    prev=$(cat "$state" 2>/dev/null || echo 0)
    case "$prev" in '' | *[!0-9]*) prev=0 ;; esac
    printf '%s' "$total" >"$state"
    if [ "$total" -gt "$prev" ]; then
      match=$(tail -n +"$((prev + 1))" "$log" | head -n "$((total - prev))" | grep -Ei "$FATAL_REGEX" | head -n 1 || true)
      [ -z "$match" ] || emit "fatal_signature" "$lane" "" "fatal signature: ${match}"
    fi
  done
}

do_liveness_check

if [ -n "${MONITOR_TEST_DELAY_BEFORE_TAIL:-}" ]; then
  sleep "$MONITOR_TEST_DELAY_BEFORE_TAIL"
fi
exec 3< <(tail -n "+$((PREV_LINES + 1))" -F "$EVENTS" 2>/dev/null)
TAIL_PID=$!
trap 'kill "$TAIL_PID" 2>/dev/null || true' EXIT

LINE_NO="$PREV_LINES"
DEADLINE=$((SECONDS + MAX_WAIT))
NEXT_CHECK=$((SECONDS + LIVENESS_INTERVAL))
while [ "$SECONDS" -lt "$DEADLINE" ]; do
  WAIT=$((NEXT_CHECK - SECONDS))
  [ "$WAIT" -ge 1 ] || WAIT=1
  # `rc=$?` lives inside the else: after a bare `fi`, $? is the if's own status.
  if IFS= read -r -t "$WAIT" -u 3 line; then
    LINE_NO=$((LINE_NO + 1))
    handle_line "$line" "$LINE_NO"
  else
    rc=$?
    # Below 128 is EOF: the tail process itself ended. That is a failure of the
    # monitor, never "nothing happened".
    [ "$rc" -ge 128 ] || emit "monitor_error" "" "" "tail -F on events.jsonl ended unexpectedly (fd closed)" "" 1
  fi
  if [ "$SECONDS" -ge "$NEXT_CHECK" ]; then
    do_liveness_check
    NEXT_CHECK=$((SECONDS + LIVENESS_INTERVAL))
  fi
done

emit "timeout" "" "" "timeout: no trigger fired within ${MAX_WAIT}s" "" 1
