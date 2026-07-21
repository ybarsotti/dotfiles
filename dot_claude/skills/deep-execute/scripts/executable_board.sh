#!/usr/bin/env bash
# board.sh — renders RUN_DIR/events.jsonl as a Markdown status table.
#
# Usage:
#   board.sh RUN_DIR [--lane LANE]
#
# Folds the append-only event log down to the LATEST event per (lane, task)
# pair and prints it as a `lane | task | status | message` Markdown table.
# This is the only run-state surface workers are given — the worker system
# prompt tells them to read state only through this command and never parse
# events.jsonl themselves — so the output stays plain Markdown, not JSON.

set -eufo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: board.sh RUN_DIR [--lane LANE]" >&2
  exit 2
fi

RUN_DIR="$1"
shift

FILTER_LANE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --lane)
      [ $# -ge 2 ] || {
        echo "board.sh: --lane requires a LANE argument" >&2
        exit 2
      }
      FILTER_LANE="$2"
      shift 2
      ;;
    *)
      echo "board.sh: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  echo "board.sh: jq required" >&2
  exit 2
}

EVENTS="${RUN_DIR}/events.jsonl"

echo "| lane | task | status | message |"
echo "|---|---|---|---|"

# An absent or empty log is a legitimate state (a run that hasn't started
# emitting events yet) — the header-only table is the correct rendering,
# not an error.
[ -s "$EVENTS" ] || exit 0

jq -sr --arg lane "$FILTER_LANE" '
  (if $lane == "" then . else map(select(.lane == $lane)) end)
  | group_by([.lane, .task])
  | map(sort_by(.ts) | last)
  | sort_by([.lane, .task])
  | .[]
  | [.lane, .task, .type, .msg]
  | @tsv
' "$EVENTS" |
  while IFS=$'\t' read -r lane task status msg; do
    printf '| %s | %s | %s | %s |\n' "$lane" "$task" "$status" "$msg"
  done
