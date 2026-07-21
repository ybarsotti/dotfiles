#!/usr/bin/env bash
# monitor-workers.sh — Blocks until exactly one of the following fires for
# some worker in RUN_DIR/manifest.json, then prints ONE trigger JSON to
# stdout and exits: a done marker (`done` or `blocked: <reason>`), a
# vanished pane (`cmux capture-pane` fails), or NEW pane-log output (since
# the previous liveness check) containing a fatal signature. If none of
# those fire before the bound below, it still emits a trigger —
# {"type":"failed","reason":"timeout: ..."} — rather than hang or return
# silently; a caller must never mistake "no output yet" for "still
# working", and must never see a `done` the worker didn't earn.
#
# WARNING: done/blocked/crashed/failed-via-fatal-signature — all four REAL
# triggers — exit 0. Only the bound-exhausted timeout path exits nonzero.
# Never guard a call with `if monitor-workers.sh; then` — that treats a
# crash as success. Callers MUST branch on the JSON `.type` field, not the
# exit code, to tell the four triggers apart.
#
# Usage:
#   monitor-workers.sh RUN_DIR
#
# Bounds (seconds, overridable via env for tests / tuning):
#   MONITOR_POLL_INTERVAL     how often done markers are re-checked (default 5)
#   MONITOR_LIVENESS_INTERVAL how often pane liveness + fatal-signature are
#                              re-checked — coarser than the done-marker
#                              check since capture-pane is a real cmux round
#                              trip, not a stat() (default 30)
#   MONITOR_MAX_WAIT          absolute bound on total wait before emitting
#                              the timeout trigger (default 1800 = 30m)
#
# Fatal-signature scanning is INCREMENTAL and NARROW, on purpose:
# - Incremental: only pane-log lines new since the previous liveness check
#   for that worker (per-worker watermark persisted under
#   RUN_DIR/.monitor-liveness-state/) are scanned. A line already seen —
#   whether it matched or not — is never rescanned. The caller re-invokes
#   this script in a loop for the next event, each invocation a fresh
#   process with no memory of its own; without a persisted watermark, one
#   benign line sitting in scrollback would be rescanned and re-fire on
#   every future invocation for the rest of the run.
# - Narrow: the regex only lists signatures that genuinely indicate a dead
#   agent (panic, fatal, segmentation fault, killed, traceback, unhandled).
#   `command not found` / `permission denied` were deliberately dropped —
#   both are routine output when a worker probes for an optional tool or
#   checks a permission, not evidence the agent died. The vanished-pane
#   check above remains the backstop for an actually-dead worker.
#
# set -e is deliberately NOT used: an individual check failing for a
# transient reason (one worker's capture-pane call erroring) must not abort
# the whole loop and every other worker's chance to report. Only the bound
# above, or a real trigger firing, ends the loop — every command whose
# failure is meaningful is checked explicitly instead.
set -uo pipefail

FATAL_REGEX='panic|fatal|segmentation fault|killed|traceback|unhandled'

RUN_DIR="${1:-}"
if [ -z "$RUN_DIR" ]; then
  echo "Usage: monitor-workers.sh RUN_DIR" >&2
  exit 2
fi

MANIFEST="${RUN_DIR}/manifest.json"
if [ ! -f "$MANIFEST" ]; then
  echo "monitor-workers.sh: missing ${MANIFEST}" >&2
  exit 2
fi

# Per-worker watermark (lines already scanned for a fatal signature),
# persisted across separate invocations of this script — see the
# "Incremental" note in the header.
STATE_DIR="${RUN_DIR}/.monitor-liveness-state"
mkdir -p "$STATE_DIR"

POLL_INTERVAL="${MONITOR_POLL_INTERVAL:-5}"
LIVENESS_INTERVAL="${MONITOR_LIVENESS_INTERVAL:-30}"
MAX_WAIT="${MONITOR_MAX_WAIT:-1800}"
# A zero poll interval would never advance ELAPSED below, turning the bound
# into a lie — clamp it so the loop can never spin forever on its own sleep.
if [ "$POLL_INTERVAL" -le 0 ] 2>/dev/null; then
  POLL_INTERVAL=1
fi

# emit TYPE WORKER REASON [EXIT_CODE] — prints the one trigger JSON and
# exits. EXIT_CODE defaults to 0: detecting done/blocked/crashed/failed is
# the script doing its job, so it succeeds even when the news is bad — the
# caller reads `.type`, not the exit code, to decide what happened. Only
# the bound-exceeded call at the bottom of this script passes a nonzero
# code, because that path is the one genuine failure of the monitor itself
# (it detected nothing at all).
emit() {
  local type="$1" worker="$2" reason="$3" code="${4:-0}"
  jq -n \
    --arg type "$type" \
    --arg worker "$worker" \
    --arg reason "$reason" \
    --arg run_dir "$RUN_DIR" \
    '{type: $type, worker: (if $worker == "" then null else $worker end), reason: $reason, run_dir: $run_dir}'
  exit "$code"
}

NAMES=()
DONE_MARKERS=()
SURFACE_REFS=()
while IFS=$'\t' read -r wname wdone wsurface; do
  NAMES+=("$wname")
  DONE_MARKERS+=("$wdone")
  SURFACE_REFS+=("$wsurface")
done < <(jq -r '.workers[] | [.name, .done_marker, (.surface_ref // "")] | @tsv' "$MANIFEST")

if [ "${#NAMES[@]}" -eq 0 ]; then
  echo "monitor-workers.sh: manifest has no workers" >&2
  exit 2
fi

ELAPSED=0
SINCE_LIVENESS="$LIVENESS_INTERVAL" # force a liveness check on the first pass

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  # ─── Cheap check every cycle: done markers (a stat + a read, no cmux call) ─
  for i in "${!NAMES[@]}"; do
    marker="${DONE_MARKERS[$i]}"
    [ -f "$marker" ] || continue
    content=$(cat "$marker" 2>/dev/null || echo "")
    case "$content" in
      blocked*)
        emit "blocked" "${NAMES[$i]}" "${content#blocked: }"
        ;;
      *)
        emit "done" "${NAMES[$i]}" "$content"
        ;;
    esac
  done

  # ─── Coarser check: pane liveness + fatal signature, only every ───────────
  # LIVENESS_INTERVAL seconds — capture-pane is a real cmux round trip, not
  # worth doing on every POLL_INTERVAL tick.
  if [ "$SINCE_LIVENESS" -ge "$LIVENESS_INTERVAL" ]; then
    for i in "${!NAMES[@]}"; do
      [ -f "${DONE_MARKERS[$i]}" ] && continue # already reported, skip
      surface="${SURFACE_REFS[$i]}"
      [ -n "$surface" ] || continue # not launched yet, nothing to capture

      if ! PANE_LOG=$(cmux capture-pane --surface "$surface" 2>&1); then
        emit "crashed" "${NAMES[$i]}" "pane vanished: capture-pane failed for ${surface}"
      fi

      # ─── Incremental scan: only NEW lines (since this worker's last ──────
      # liveness check) are examined — see the header's "Incremental" note.
      # The watermark is written unconditionally, before the match check, so
      # it's persisted even on the branch that emits and exits.
      STATE_FILE="${STATE_DIR}/${NAMES[$i]}.lines"
      TOTAL_LINES=$(printf '%s\n' "$PANE_LOG" | wc -l | tr -d ' ')
      PREV_LINES=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
      case "$PREV_LINES" in '' | *[!0-9]*) PREV_LINES=0 ;; esac
      printf '%s\n' "$TOTAL_LINES" >"$STATE_FILE"

      if [ "$TOTAL_LINES" -gt "$PREV_LINES" ]; then
        NEW_LOG=$(printf '%s\n' "$PANE_LOG" | tail -n +"$((PREV_LINES + 1))")
        if printf '%s\n' "$NEW_LOG" | grep -qEi "$FATAL_REGEX"; then
          MATCH=$(printf '%s\n' "$NEW_LOG" | grep -Ei "$FATAL_REGEX" | head -n1)
          emit "failed" "${NAMES[$i]}" "fatal signature: ${MATCH}"
        fi
      fi
    done
    SINCE_LIVENESS=0
  fi

  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))
  SINCE_LIVENESS=$((SINCE_LIVENESS + POLL_INTERVAL))
done

# Bound reached with no trigger — never report success by silence.
emit "failed" "" "timeout: no trigger fired within ${MAX_WAIT}s" 1
