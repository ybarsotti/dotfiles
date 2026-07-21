#!/usr/bin/env bash
# event.sh — atomic append-only writer for events.jsonl.
#
# Usage:
#   event.sh RUN_DIR LANE TASK TYPE MSG [--files PATH...]
#
# Writes exactly one compact JSON object per line to RUN_DIR/events.jsonl via
# a single O_APPEND write. POSIX guarantees a write() under PIPE_BUF (4096
# bytes on every platform this runs on) to an O_APPEND-opened file descriptor
# is atomic — concurrent lanes appending at once can never interleave a
# partial line. That guarantee is the whole reason this script exists rather
# than every caller appending by hand: an oversized event, or one with an
# embedded CR/LF, would either blow past PIPE_BUF (interleaving becomes
# possible again) or inject a stray line break (corrupting the one-line-per-
# event contract board.sh and validate-run-state.sh both depend on) — so
# both are rejected loudly here, before anything is written, rather than
# silently truncated or split.

set -eufo pipefail

if [ $# -lt 5 ]; then
  echo "Usage: event.sh RUN_DIR LANE TASK TYPE MSG [--files PATH...]" >&2
  exit 2
fi

RUN_DIR="$1"
LANE="$2"
TASK="$3"
TYPE="$4"
MSG="$5"
shift 5

case "$TYPE" in
  task_start | task_done | progress | question | waiting | blocked | done) ;;
  *)
    printf 'event.sh: unknown event type "%s" (want one of: task_start task_done progress question waiting blocked done)\n' "$TYPE" >&2
    exit 1
    ;;
esac

case "$MSG" in
  *$'\n'* | *$'\r'*)
    echo "event.sh: msg must not contain a newline or carriage return (breaks the one-line-per-event contract)" >&2
    exit 1
    ;;
esac

command -v jq >/dev/null 2>&1 || {
  echo "event.sh: jq required" >&2
  exit 2
}
[ -d "$RUN_DIR" ] || {
  echo "event.sh: no such run directory: $RUN_DIR" >&2
  exit 2
}

LINE=$(jq -cn \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg lane "$LANE" \
  --arg task "$TASK" \
  --arg type "$TYPE" \
  --arg msg "$MSG" \
  '{ts:$ts, lane:$lane, task:$task, type:$type, msg:$msg}')

BYTES=$(printf '%s\n' "$LINE" | wc -c | tr -d ' ')
[ "$BYTES" -lt 4096 ] || {
  printf 'event.sh: event is %s bytes; limit is 4095 (PIPE_BUF safety margin for atomic concurrent appends)\n' "$BYTES" >&2
  exit 1
}

printf '%s\n' "$LINE" >>"${RUN_DIR}/events.jsonl"

# --files PATH... — append each path to worker-<lane>.files.txt in the same
# invocation, so a worker never has a write step it did but forgot to log.
if [ $# -gt 0 ]; then
  [ "$1" = "--files" ] || {
    echo "event.sh: unknown argument '$1' (expected --files)" >&2
    exit 2
  }
  shift
  [ $# -gt 0 ] || {
    echo "event.sh: --files requires at least one PATH" >&2
    exit 2
  }
  FILES_LOG="${RUN_DIR}/worker-${LANE}.files.txt"
  for p in "$@"; do
    printf '%s\n' "$p" >>"$FILES_LOG"
  done
fi
