#!/usr/bin/env bash
# reply.sh — writes the orchestrator's reply for a lane and wakes it.
#
# Usage:
#   reply.sh RUN_DIR LANE MESSAGE
#   reply.sh RUN_DIR --all MESSAGE
#
# Writes `lanes/<lane>/reply.md` (overwritten, not appended — a reply is the
# current instruction for a waiting/blocked worker, not a running log; the
# run's real history already lives in events.jsonl) with a small structured
# header, then resolves the lane's `surface_ref` from
# `RUN_DIR/cmux/manifest.json` (cmux's own manifest — see init-run.sh's
# header note for why surface_ref lives there and not in this skill's own
# manifest.json) and wakes the pane through cmux-orchestrator's own
# send-task.sh, never a second hand-rolled `cmux send` call.
#
# `--all` writes and wakes every non-orchestrator lane listed in this
# skill's own `RUN_DIR/manifest.json` (already excludes the orchestrator
# lane — init-run.sh only ever records worker lanes there).
#
# Every lane is attempted even when an earlier one fails to wake — a lane
# worker that finishes early emits `waiting` and STOPS by design (see the
# worker system prompt), so a reply that silently never arrives strands
# that lane forever. One JSON line per lane is printed to stdout
# (`{lane, reply_written, woken, detail}`) so a failure is reported, not
# swallowed; the script exits 1 if ANY lane failed to wake, after every
# lane has been attempted.
set -eufo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: reply.sh RUN_DIR LANE|--all MESSAGE" >&2
  exit 2
fi

RUN_DIR="$1"
TARGET="$2"
MESSAGE="$3"

command -v jq >/dev/null 2>&1 || {
  echo "reply.sh: jq required" >&2
  exit 2
}
MANIFEST="${RUN_DIR}/manifest.json"
CMUX_MANIFEST="${RUN_DIR}/cmux/manifest.json"
[ -f "$MANIFEST" ] || {
  echo "reply.sh: missing ${MANIFEST}" >&2
  exit 2
}
[ -f "$CMUX_MANIFEST" ] || {
  echo "reply.sh: missing ${CMUX_MANIFEST}" >&2
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMUX_SCRIPTS="$(cd "${SCRIPT_DIR}/../../cmux-orchestrator/scripts" && pwd)"
SEND_TASK="${CMUX_SCRIPTS}/send-task.sh"
[ -f "$SEND_TASK" ] || SEND_TASK="${CMUX_SCRIPTS}/executable_send-task.sh"
[ -f "$SEND_TASK" ] || {
  echo "reply.sh: cannot find send-task.sh next to cmux-orchestrator's scripts" >&2
  exit 2
}

CONTRACT_VERSION=$(jq -r '.contract.version // ""' "$MANIFEST")

LANES=()
while IFS= read -r l; do
  [ -n "$l" ] && LANES+=("$l")
done < <(jq -r '.workers[]?.lane // empty' "$MANIFEST")

if [ "$TARGET" = "--all" ]; then
  TARGET_LANES=("${LANES[@]}")
else
  FOUND=0
  for l in "${LANES[@]}"; do
    [ "$l" = "$TARGET" ] && FOUND=1
  done
  [ "$FOUND" -eq 1 ] || {
    echo "reply.sh: lane '${TARGET}' is not a worker lane in ${MANIFEST}" >&2
    exit 2
  }
  TARGET_LANES=("$TARGET")
fi

[ ${#TARGET_LANES[@]} -ge 1 ] || {
  echo "reply.sh: no worker lanes to reply to" >&2
  exit 1
}

FAILED=0
for lane in "${TARGET_LANES[@]}"; do
  REPLY_DIR="${RUN_DIR}/lanes/${lane}"
  mkdir -p "$REPLY_DIR"
  REPLY_FILE="${REPLY_DIR}/reply.md"

  {
    printf -- '- Contract version: %s\n' "$CONTRACT_VERSION"
    printf -- '- Sent at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '\n%s\n' "$MESSAGE"
  } >"$REPLY_FILE"

  SURFACE=$(jq -r --arg n "$lane" '.workers[]? | select(.name == $n) | .surface_ref // empty' "$CMUX_MANIFEST")

  if [ -z "$SURFACE" ] || [ "$SURFACE" = "null" ]; then
    FAILED=1
    jq -n --arg lane "$lane" --arg detail "no surface_ref for lane '${lane}' in ${CMUX_MANIFEST}" \
      '{lane: $lane, reply_written: true, woken: false, detail: $detail}'
    continue
  fi

  # Invoked via `bash "$SEND_TASK"` rather than executing it directly: the
  # checked-out source tree does not always carry the executable bit on
  # every cross-skill script (chezmoi sets it from the `executable_` prefix
  # at `apply` time, not necessarily in the source checkout), and this
  # script has no business depending on that bit for a script it doesn't
  # own.
  if WAKE_OUT=$(bash "$SEND_TASK" "$SURFACE" "Read ${REPLY_FILE}, apply it, then continue your lane." 2>&1); then
    jq -n --arg lane "$lane" --arg detail "woken via ${SURFACE}: ${WAKE_OUT}" \
      '{lane: $lane, reply_written: true, woken: true, detail: $detail}'
  else
    FAILED=1
    jq -n --arg lane "$lane" --arg detail "send-task.sh failed for surface ${SURFACE}: ${WAKE_OUT}" \
      '{lane: $lane, reply_written: true, woken: false, detail: $detail}'
  fi
done

if [ "$FAILED" -eq 1 ]; then
  echo "reply.sh: at least one lane failed to wake — see the 'woken:false' line(s) above" >&2
  exit 1
fi
exit 0
