#!/usr/bin/env bash
# reply.sh — publishes the orchestrator's reply for a lane; the publish is the wake.
#
# Usage:
#   reply.sh RUN_DIR LANE MESSAGE
#   reply.sh RUN_DIR --all MESSAGE
#
# Each reply is a new numbered file, lanes/<lane>/replies/<NNNNNN>.md, with a
# small header (contract version, time sent). The file is written in full
# under a temporary name and then hard-linked to its number, so the worker
# loop never reads half a reply, and two replies never overwrite each other:
# `ln` fails on an existing number and the next number is tried.
# worker-loop.sh delivers every reply above its consumed number on its next
# turn, also a reply that lands mid-turn or while the loop is down.
#
# The wake reaches a lane only while its loop runs. The loop writes its pid to
# lanes/<lane>/loop.pid, and `kill -0` checks it. A reply for a lane with no
# live loop stays on disk for the relaunch, and is reported as woken:false.
#
# `--all` replies to every worker lane in RUN_DIR/manifest.json. Every lane is
# attempted, one JSON line per lane ({lane, reply_written, woken, detail}), and
# the exit is 1 when any lane did not wake.
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
[ -f "$MANIFEST" ] || {
  echo "reply.sh: missing ${MANIFEST}" >&2
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

# publish LANE — writes the reply, prints its path.
publish() {
  local dir="${RUN_DIR}/lanes/$1/replies" tmp n last f
  mkdir -p "$dir"
  tmp=$(mktemp "${RUN_DIR}/lanes/$1/.reply.XXXXXX")
  {
    printf -- '- Contract version: %s\n' "$CONTRACT_VERSION"
    printf -- '- Sent at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '\n%s\n' "$MESSAGE"
  } >"$tmp"
  last=0
  while IFS= read -r f; do
    n=${f%.md}
    case "$n" in '' | *[!0-9]*) continue ;; esac
    [ $((10#$n)) -le "$last" ] || last=$((10#$n))
  done < <(ls "$dir")
  n=$((last + 1))
  until ln "$tmp" "${dir}/$(printf '%06d' "$n").md" 2>/dev/null; do
    n=$((n + 1))
  done
  rm -f "$tmp"
  printf '%s' "${dir}/$(printf '%06d' "$n").md"
}

FAILED=0
for lane in "${TARGET_LANES[@]}"; do
  FILE=$(publish "$lane")
  PID=$(cat "${RUN_DIR}/lanes/${lane}/loop.pid" 2>/dev/null || true)
  if [ -z "$PID" ]; then
    FAILED=1
    WOKEN=false
    DETAIL="no worker loop has started for lane '${lane}' — launch it; ${FILE} waits for it"
  elif kill -0 "$PID" 2>/dev/null; then
    WOKEN=true
    DETAIL="reply ${FILE} published; loop ${PID} is alive"
  else
    FAILED=1
    WOKEN=false
    DETAIL="loop ${PID} is gone — ${FILE} waits on disk until the lane is relaunched"
  fi
  jq -n --arg lane "$lane" --argjson woken "$WOKEN" --arg detail "$DETAIL" \
    '{lane: $lane, reply_written: true, woken: $woken, detail: $detail}'
done

if [ "$FAILED" -eq 1 ]; then
  echo "reply.sh: at least one lane did not wake — see the 'woken:false' line(s) above" >&2
  exit 1
fi
exit 0
