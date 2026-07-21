#!/usr/bin/env bash
# monitor-events.sh — Blocks until exactly one of the following fires, then
# prints ONE trigger JSON to stdout and exits: a `question`, `waiting`,
# `blocked` or `done` event landing in RUN_DIR/events.jsonl, a line in that
# file that fails the event schema (`invalid_event`), a worker pane that
# vanishes (`vanished_pane`), a fatal signature appearing in a worker's pane
# log (`fatal_signature`), the events log's own tail process dying
# unexpectedly (`monitor_error`), or the bound below being exhausted
# (`timeout`). Never returns silently and never guesses past what it
# actually observed — see the header note in validate-run-state.sh for why
# this skill treats "reported success by silence" as a bug class.
#
# WARNING: every trigger except `timeout` (and `monitor_error`) exits 0 —
# detecting `blocked`, an invalid line, a vanished pane or a fatal signature
# is this script doing its job, not failing at it, exactly like
# cmux-orchestrator's monitor-workers.sh. Callers MUST branch on the JSON
# `.type` field, never on the exit code, to tell triggers apart.
#
# Usage:
#   monitor-events.sh RUN_DIR
#
# Output shape: {"type":..., "lane":..., "task":..., "msg":..., "run_dir":...}
# `lane`/`task` are null when the trigger isn't about one specific lane/task
# (an invalid line whose JSON couldn't even be parsed for a lane, or the
# bound-exhausted timeout).
#
# Bounds (seconds, overridable via env for tests / tuning):
#   MONITOR_LIVENESS_INTERVAL  how often, at most, a pane-health check
#                               (vanished pane + fatal signature scan) runs
#                               while waiting for the next event (default 30)
#   MONITOR_MAX_WAIT           absolute bound on total wait before emitting
#                               the timeout trigger (default 1800 = 30m)
#
# ── How blocking works, and why `tail -n 0 -F` alone is not enough ────────
# `events.jsonl` can already hold unprocessed lines the moment this script
# starts (a worker emitted `waiting` a heartbeat before the orchestrator got
# around to calling this script again for the next trigger) — a bare
# `tail -n 0 -F`, which only shows content appended AFTER it attaches, would
# silently skip that backlog and then sit blocked on lines that already
# arrived. So every invocation first drains any backlog since the last
# invocation's watermark (persisted under RUN_DIR/.monitor-events-state/,
# same technique as monitor-workers.sh's per-worker liveness watermark, and
# for the same reason: without it, a re-invoked script has no memory of what
# it already reported). Only once the backlog is fully drained with no
# trigger does it attach `tail -n 0 -F` and wait for genuinely new content —
# at that point "new" and "unprocessed" are the same thing.
#
# Combining a blocking tail with a bounded, periodic pane-health check (no
# model polling — this is a plain shell timer) is done with `read -t`
# against the tail's output, not two independent loops: each iteration
# either processes a new event line the instant it arrives, or times out
# after MONITOR_LIVENESS_INTERVAL seconds of silence and runs exactly one
# pane-health check before waiting again. Only time spent with NOTHING
# happening (no event, no health-check trigger) counts against
# MONITOR_MAX_WAIT; draining a backlog of ordinary progress events costs
# nothing against that bound.
#
# Fatal-signature scanning reuses monitor-workers.sh's own regex verbatim
# (not re-derived) and the same incremental/per-lane-watermark technique —
# see that script's header for why it is narrow (only genuine
# dead-agent signatures) and incremental (a line already scanned, matching
# or not, is never rescanned).
set -eufo pipefail

FATAL_REGEX='panic|fatal|segmentation fault|killed|traceback|unhandled'

RUN_DIR="${1:-}"
if [ -z "$RUN_DIR" ]; then
  echo "Usage: monitor-events.sh RUN_DIR" >&2
  exit 2
fi

MANIFEST="${RUN_DIR}/manifest.json"
CMUX_MANIFEST="${RUN_DIR}/cmux/manifest.json"
EVENTS="${RUN_DIR}/events.jsonl"

[ -f "$MANIFEST" ] || {
  echo "monitor-events.sh: missing ${MANIFEST}" >&2
  exit 2
}
command -v jq >/dev/null 2>&1 || {
  echo "monitor-events.sh: jq required" >&2
  exit 2
}
[ -f "$EVENTS" ] || : >"$EVENTS"

LIVENESS_INTERVAL="${MONITOR_LIVENESS_INTERVAL:-30}"
MAX_WAIT="${MONITOR_MAX_WAIT:-1800}"
# A non-positive interval would make `read -t` either error or busy-poll
# without ever advancing ELAPSED below — clamp so the bound can never be
# turned into a lie by a caller passing 0.
if [ "$LIVENESS_INTERVAL" -le 0 ] 2>/dev/null; then
  LIVENESS_INTERVAL=1
fi

STATE_DIR="${RUN_DIR}/.monitor-events-state"
mkdir -p "$STATE_DIR"
WATERMARK_FILE="${STATE_DIR}/events.watermark"

# emit TYPE LANE TASK MSG [EXIT_CODE] — prints the one trigger JSON and
# exits. See the header WARNING: only the caller of this function for the
# timeout/monitor_error paths passes a nonzero EXIT_CODE.
emit() {
  local type="$1" lane="$2" task="$3" msg="$4" code="${5:-0}"
  jq -n \
    --arg type "$type" \
    --arg lane "$lane" \
    --arg task "$task" \
    --arg msg "$msg" \
    --arg run_dir "$RUN_DIR" \
    '{type: $type, lane: (if $lane == "" then null else $lane end), task: (if $task == "" then null else $task end), msg: $msg, run_dir: $run_dir}'
  exit "$code"
}

# event_line_valid LINE — same schema check validate-run-state.sh applies to
# every line of events.jsonl (kept in sync by hand — both read the same
# schemas/run-state.schema.json `event` definition).
event_line_valid() {
  jq -e '
    (.ts | type == "string") and (.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    (.lane | type == "string" and length > 0) and
    (.task | type == "string" and length > 0) and
    (.type == "task_start" or .type == "task_done" or .type == "progress" or .type == "question" or .type == "waiting" or .type == "blocked" or .type == "done") and
    (.msg | type == "string") and (.msg | test("^[^\r\n]*$")) and (.msg | length <= 3000) and
    ((keys_unsorted - ["ts","lane","task","type","msg"]) == [])
  ' <<<"$1" >/dev/null 2>&1
}

# handle_line LINE — the one decision every event line goes through,
# whether seen during backlog drain or the live follow loop: invalid line ->
# invalid_event trigger; question/waiting/blocked/done -> that trigger;
# task_start/task_done/progress -> not a trigger, falls through so the
# caller keeps going.
handle_line() {
  local line="$1" lane_guess type l t m
  [ -z "$line" ] && return 0
  if ! event_line_valid "$line"; then
    lane_guess=$(jq -r '.lane // empty' <<<"$line" 2>/dev/null || true)
    emit "invalid_event" "$lane_guess" "" "$line"
  fi
  type=$(jq -r '.type' <<<"$line")
  case "$type" in
    question | waiting | blocked | done)
      l=$(jq -r '.lane' <<<"$line")
      t=$(jq -r '.task' <<<"$line")
      m=$(jq -r '.msg' <<<"$line")
      emit "$type" "$l" "$t" "$m"
      ;;
  esac
}

# ─── Backlog drain: everything since the persisted watermark ──────────────
PREV_LINES=$(cat "$WATERMARK_FILE" 2>/dev/null || echo 0)
case "$PREV_LINES" in '' | *[!0-9]*) PREV_LINES=0 ;; esac
TOTAL_LINES=$(wc -l <"$EVENTS" 2>/dev/null | tr -d ' ')
case "$TOTAL_LINES" in '' | *[!0-9]*) TOTAL_LINES=0 ;; esac

if [ "$TOTAL_LINES" -gt "$PREV_LINES" ]; then
  LINE_NO=0
  while IFS= read -r line || [ -n "$line" ]; do
    LINE_NO=$((LINE_NO + 1))
    [ "$LINE_NO" -le "$PREV_LINES" ] && continue
    # Watermark advances before the trigger check — same "unconditional,
    # before the match" ordering monitor-workers.sh uses, so a line that
    # DOES trigger (and ends this whole process via emit's `exit`) is still
    # recorded as processed for the NEXT invocation.
    printf '%s' "$LINE_NO" >"$WATERMARK_FILE"
    handle_line "$line"
  done <"$EVENTS"
fi
# LINE_NO must reflect "lines processed so far" even when the backlog loop
# above never ran (nothing new since the last invocation) — the live-follow
# loop below keeps counting from here, and `set -u` would otherwise trip on
# a LINE_NO that was never assigned.
LINE_NO="$TOTAL_LINES"

# ─── Lane / surface lookups for pane-health checks ─────────────────────────
LANES=()
while IFS= read -r l; do
  [ -n "$l" ] && LANES+=("$l")
done < <(jq -r '.workers[]?.lane // empty' "$MANIFEST" 2>/dev/null)

# do_liveness_check — one pass over every lane: vanished pane (capture-pane
# fails) or a fatal signature in NEW pane-log output since that lane's own
# watermark. Silently skipped (not an error) when cmux isn't available or
# the cmux manifest doesn't exist yet — this script's primary job is
# watching events.jsonl; pane health is a supplementary signal layered on
# top, same relationship monitor-workers.sh has to done markers vs. panes.
do_liveness_check() {
  command -v cmux >/dev/null 2>&1 || return 0
  [ -f "$CMUX_MANIFEST" ] || return 0
  local lane surface pane_log state_file total prev new match
  for lane in "${LANES[@]}"; do
    surface=$(jq -r --arg n "$lane" '.workers[]? | select(.name == $n) | .surface_ref // empty' "$CMUX_MANIFEST" 2>/dev/null)
    [ -n "$surface" ] && [ "$surface" != "null" ] || continue

    if ! pane_log=$(cmux capture-pane --surface "$surface" 2>&1); then
      emit "vanished_pane" "$lane" "" "pane vanished: capture-pane failed for ${surface}"
    fi

    state_file="${STATE_DIR}/pane-${lane}.lines"
    total=$(printf '%s\n' "$pane_log" | wc -l | tr -d ' ')
    prev=$(cat "$state_file" 2>/dev/null || echo 0)
    case "$prev" in '' | *[!0-9]*) prev=0 ;; esac
    printf '%s' "$total" >"$state_file"

    if [ "$total" -gt "$prev" ]; then
      new=$(printf '%s\n' "$pane_log" | tail -n +"$((prev + 1))")
      if printf '%s\n' "$new" | grep -qEi "$FATAL_REGEX"; then
        match=$(printf '%s\n' "$new" | grep -Ei "$FATAL_REGEX" | head -n1)
        emit "fatal_signature" "$lane" "" "fatal signature: ${match}"
      fi
    fi
  done
}

# ─── Live follow: from here on, "appended" and "unprocessed" coincide ─────
exec 3< <(tail -n 0 -F "$EVENTS" 2>/dev/null)
TAIL_PID=$!
trap 'kill "$TAIL_PID" 2>/dev/null || true' EXIT

ELAPSED=0
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  # NOTE: `rc=$?` MUST live inside the `else` — POSIX says an `if` with no
  # `else` taken has ITS OWN exit status 0 regardless of the condition's
  # real exit code, so capturing "$?" after a bare `fi` would always read 0
  # and every timeout would be misread as EOF. The `else` is what makes
  # `$?` here the read builtin's actual exit status.
  if IFS= read -r -t "$LIVENESS_INTERVAL" -u 3 line; then
    LINE_NO=$((LINE_NO + 1))
    printf '%s' "$LINE_NO" >"$WATERMARK_FILE"
    handle_line "$line"
    # An informational event (task_start/task_done/progress) isn't a
    # trigger — loop again immediately. Only silence counts against
    # MAX_WAIT, so this costs nothing against the bound.
    continue
  else
    rc=$?
  fi
  if [ "$rc" -ge 128 ]; then
    # `read -t` timed out: MONITOR_LIVENESS_INTERVAL seconds passed with no
    # new event line. Run one bounded pane-health check, then keep waiting.
    do_liveness_check
    ELAPSED=$((ELAPSED + LIVENESS_INTERVAL))
    continue
  fi
  # EOF on the tail's fd, not a timeout: the backgrounded `tail -F` process
  # itself ended (killed, or the file it's following was removed out from
  # under it in a way tail couldn't recover from). This is a failure of the
  # monitor's own blocking mechanism, not of anything it's watching — never
  # mistake "nothing left to read" for "nothing happened".
  emit "monitor_error" "" "" "tail -F on events.jsonl ended unexpectedly (fd closed)" 1
done

# Bound reached with no trigger — never report success by silence.
emit "timeout" "" "" "timeout: no trigger fired within ${MAX_WAIT}s" 1
