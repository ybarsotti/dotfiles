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
# header. **That write is the wake.** worker-loop.sh blocks on the file's mtime
# and resumes the lane's session when it moves, so nothing is typed into the
# worker. Wave has no way to type into a live block — there is no `wsh send` —
# which is why the transport is a file rather than a keystroke.
#
# The lane's `block_ref` is read from `RUN_DIR/wave/manifest.json` (the launch
# transport's own manifest, kept out of this skill's — see init-run.sh's header)
# only to check that the lane's loop is still alive. A reply written for a dead
# block is on disk with nobody to read it, which is a stranded lane.
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
WAVE_MANIFEST="${RUN_DIR}/wave/manifest.json"
[ -f "$MANIFEST" ] || {
  echo "reply.sh: missing ${MANIFEST}" >&2
  exit 2
}
[ -f "$WAVE_MANIFEST" ] || {
  echo "reply.sh: missing ${WAVE_MANIFEST}" >&2
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

  # The write above IS the wake: worker-loop.sh blocks on this file's mtime and
  # resumes the lane's session when it moves. Nothing is typed into the worker,
  # because Wave has no way to type into a block — see wave-launch.sh's header.
  #
  # A reply only reaches a lane whose loop is still alive, so the block is checked
  # too. A dead block means the reply landed on disk and nobody will read it, which
  # is the stranded-lane failure this script exists to report rather than swallow.
  BLOCK=$(jq -r --arg n "$lane" '.workers[]? | select(.name == $n) | .block_ref // empty' "$WAVE_MANIFEST")

  if [ -z "$BLOCK" ] || [ "$BLOCK" = "null" ]; then
    FAILED=1
    jq -n --arg lane "$lane" --arg detail "no block_ref for lane '${lane}' in ${WAVE_MANIFEST} — was it launched?" \
      '{lane: $lane, reply_written: true, woken: false, detail: $detail}'
    continue
  fi

  if ! command -v wsh >/dev/null 2>&1; then
    jq -n --arg lane "$lane" --arg detail "reply written for ${BLOCK}; wsh absent, so liveness is unverified" \
      '{lane: $lane, reply_written: true, woken: true, detail: $detail}'
  elif wsh blocks list 2>/dev/null | grep -qF "${BLOCK#block:}"; then
    jq -n --arg lane "$lane" --arg detail "reply written; ${BLOCK} is alive and watching" \
      '{lane: $lane, reply_written: true, woken: true, detail: $detail}'
  else
    FAILED=1
    jq -n --arg lane "$lane" --arg detail "${BLOCK} is gone — the reply is on disk with no loop to read it" \
      '{lane: $lane, reply_written: true, woken: false, detail: $detail}'
  fi
done

if [ "$FAILED" -eq 1 ]; then
  echo "reply.sh: at least one lane failed to wake — see the 'woken:false' line(s) above" >&2
  exit 1
fi
exit 0
