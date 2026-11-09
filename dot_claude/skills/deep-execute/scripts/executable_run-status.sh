#!/usr/bin/env bash
# run-status.sh — one status line for a run, then one line per lane loop.
#
# Usage:
#   run-status.sh RUN_DIR
#
# The first line gives the phase, the task completion and the elapsed time.
# Each lane line says whether its worker loop runs: `running` (pid alive),
# `stopped` (stop file), `dead` (pid file, no process — relaunch it with
# orca-launch.sh RUN_DIR LANE) or `not launched`. Resume reads this first.
set -eufo pipefail

RUN_DIR="${1:-}"
if [ -z "$RUN_DIR" ] || [ ! -d "$RUN_DIR" ]; then
  echo "run-status.sh: usage: run-status.sh RUN_DIR" >&2
  exit 2
fi

command -v jq >/dev/null 2>&1 || {
  echo "run-status.sh: jq required" >&2
  exit 2
}

MANIFEST="${RUN_DIR}/manifest.json"
STATUS="${RUN_DIR}/status.json"
if [ ! -f "$MANIFEST" ] || [ ! -f "$STATUS" ]; then
  echo "run-status.sh: run has no manifest.json or status.json" >&2
  exit 1
fi

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

snapshot | tail -1
while IFS= read -r lane; do
  [ -n "$lane" ] || continue
  dir="${RUN_DIR}/lanes/${lane}"
  pid=$(cat "${dir}/loop.pid" 2>/dev/null || true)
  if [ -f "${dir}/stop" ]; then
    state="stopped"
  elif [ -z "$pid" ]; then
    state="not launched"
  elif kill -0 "$pid" 2>/dev/null; then
    state="running (pid ${pid})"
  else
    state="dead (pid ${pid}) — relaunch: orca-launch.sh ${RUN_DIR} ${lane}"
  fi
  printf 'lane %s: %s\n' "$lane" "$state"
done < <(jq -r '.workers[]?.lane' "$MANIFEST")
