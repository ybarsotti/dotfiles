#!/usr/bin/env bash
set -eufo pipefail

RUN_DIR="${1:-}"
PHASE="${2:-}"

if [ -z "$RUN_DIR" ] || [ ! -d "$RUN_DIR" ]; then
  echo "set-phase.sh: usage: set-phase.sh RUN_DIR execution|review|qa|delivery|complete" >&2
  exit 2
fi

case "$PHASE" in
  execution | review | qa | delivery | complete) ;;
  *)
    echo "set-phase.sh: invalid phase '$PHASE'" >&2
    exit 2
    ;;
esac

command -v jq >/dev/null 2>&1 || {
  echo "set-phase.sh: jq required" >&2
  exit 2
}

STATUS="${RUN_DIR}/status.json"
[ -f "$STATUS" ] || {
  echo "set-phase.sh: missing ${STATUS}" >&2
  exit 1
}

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TMP=$(mktemp)
jq --arg phase "$PHASE" --arg now "$NOW" \
  '.phase = $phase | .phase_started_at = $now' "$STATUS" >"$TMP"
mv "$TMP" "$STATUS"

echo "phase: ${PHASE}"
