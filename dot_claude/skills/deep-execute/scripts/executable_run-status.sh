#!/usr/bin/env bash
set -eufo pipefail

RUN_DIR="${1:-}"
MODE="${2:-print}"

if [ -z "$RUN_DIR" ] || [ ! -d "$RUN_DIR" ]; then
  echo "run-status.sh: usage: run-status.sh RUN_DIR [--update-tab|--watch]" >&2
  exit 2
fi

case "$MODE" in
  print | --update-tab | --watch) ;;
  *)
    echo "run-status.sh: unknown mode '$MODE'" >&2
    exit 2
    ;;
esac

command -v jq >/dev/null 2>&1 || {
  echo "run-status.sh: jq required" >&2
  exit 2
}

MANIFEST="${RUN_DIR}/manifest.json"
STATUS="${RUN_DIR}/status.json"
[ -f "$MANIFEST" ] && [ -f "$STATUS" ] || {
  echo "run-status.sh: run has no manifest.json or status.json" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN=$(jq -r '.plan_path' "$MANIFEST")
ORCH=$(jq -r '.orchestrator_lane // "orchestrator"' "$STATUS")
PARSER="${SCRIPT_DIR}/../../deep-plan/scripts/plan-to-json.sh"
[ -f "$PARSER" ] || PARSER="${SCRIPT_DIR}/../../deep-plan/scripts/executable_plan-to-json.sh"

TOTAL=0
if [ -f "$PLAN" ] && [ -x "$PARSER" ]; then
  TOTAL=$($PARSER "$PLAN" 2>/dev/null | jq --arg orch "$ORCH" '[.tasks[] | select(.lane != $orch)] | length') || TOTAL=0
fi

snapshot() {
  local phase label started stage completed blocked percent elapsed elapsed_text title line events
  phase=$(jq -r '.phase' "$STATUS")
  label=$(jq -r '.task_label' "$STATUS")
  started=$(jq -r '.started_at' "$STATUS")

  case "$phase" in
    execution) stage=1 ;;
    review) stage=2 ;;
    qa) stage=3 ;;
    delivery) stage=4 ;;
    complete) stage=4 ;;
  esac

  events="${RUN_DIR}/events.jsonl"
  completed=0
  blocked=0
  if [ -s "$events" ]; then
    completed=$(jq -sr --arg orch "$ORCH" '
      def number: try (.task | capture("(?i)^(?:task[ ]*)?(?<n>[0-9]+)").n) catch "";
      map(select(.lane != $orch and number != ""))
      | group_by([.lane, number])
      | map(sort_by(.ts) | last)
      | [ .[] | select(.type == "done" or .type == "task_done") | number ]
      | unique | length
    ' "$events")
    blocked=$(jq -sr '
      group_by([.lane, .task]) | map(sort_by(.ts) | last)
      | [ .[] | select(.type == "blocked") ] | length
    ' "$events")
  fi

  if [ "$TOTAL" -gt 0 ]; then
    [ "$completed" -le "$TOTAL" ] || completed=$TOTAL
    percent=$((completed * 100 / TOTAL))
  else
    percent=0
  fi
  elapsed=$(jq -nr --arg started "$started" '((now - ($started | fromdateiso8601)) | floor)')
  [ "$elapsed" -ge 0 ] || elapsed=0
  if [ "$elapsed" -ge 3600 ]; then
    elapsed_text=$(printf '%dh%02dm' $((elapsed / 3600)) $(((elapsed % 3600) / 60)))
  else
    elapsed_text=$(printf '%dm%02ds' $((elapsed / 60)) $((elapsed % 60)))
  fi

  if [ "$phase" = "execution" ]; then
    title="${label} · exec ${completed}/${TOTAL} ${percent}% · ${elapsed_text}"
  else
    title="${label} · ${phase} ${stage}/4 · tasks ${percent}% · ${elapsed_text}"
  fi
  line="phase ${stage}/4: ${phase} | tasks ${completed}/${TOTAL} (${percent}%) | elapsed ${elapsed_text}"
  [ "$blocked" -eq 0 ] || line="${line} | blocked ${blocked}"

  printf '%s\n%s\n' "$title" "$line"
}

update_tab() {
  local output title phase blocked
  output=$(snapshot)
  title=${output%%$'\n'*}
  printf '%s\n' "${output#*$'\n'}"
  command -v wsh >/dev/null 2>&1 || return 0
  [ -n "${WAVETERM_TABID:-}" ] || return 0
  [ -z "${WAVETERM_BLOCKID:-}" ] || \
    wsh setmeta -b "${WAVETERM_BLOCKID}" "frame:title=${title}" >/dev/null 2>&1 || true
  phase=$(jq -r '.phase' "$STATUS")
  blocked=0
  [ -s "${RUN_DIR}/events.jsonl" ] && blocked=$(jq -sr '
    group_by([.lane, .task]) | map(sort_by(.ts) | last)
    | [ .[] | select(.type == "blocked") ] | length
  ' "${RUN_DIR}/events.jsonl")
  if [ "$blocked" -gt 0 ]; then
    wsh badge triangle-exclamation --color red -b tab >/dev/null 2>&1 || true
  elif [ "$phase" = "complete" ]; then
    wsh badge circle-check --color green -b tab >/dev/null 2>&1 || true
  else
    wsh badge spinner --color cyan -b tab >/dev/null 2>&1 || true
  fi
}

if [ "$MODE" = "print" ]; then
  snapshot | tail -1
  exit 0
fi

if [ "$MODE" = "--update-tab" ]; then
  update_tab
  exit 0
fi

PID_FILE="${RUN_DIR}/status-watcher.pid"
if [ -s "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE")
  case "$OLD_PID" in
    *[!0-9]* | "") ;;
    *) kill -0 "$OLD_PID" 2>/dev/null && exit 0 ;;
  esac
fi
printf '%s\n' "$$" >"$PID_FILE"
trap ': >"$PID_FILE"' EXIT

while :; do
  update_tab
  [ "$(jq -r '.phase' "$STATUS")" != "complete" ] || exit 0
  sleep 5
done
