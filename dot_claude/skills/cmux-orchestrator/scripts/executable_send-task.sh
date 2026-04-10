#!/usr/bin/env bash
# send-task.sh — Send a task to an existing idle worker pane
#
# Usage:
#   send-task.sh <surface_ref> <prompt_text>
#   send-task.sh <surface_ref> --file <prompt_file>
#
# Automatically appends \n so the text auto-submits (Enter key sent).
#
# Examples:
#   send-task.sh surface:12 "Fix the bug in auth.go"
#   send-task.sh surface:12 --file /tmp/cmux-orchestrator/run-123/worker-fix.prompt.md

set -euo pipefail

SURFACE="$1"
shift

if [ "$1" = "--file" ]; then
  PROMPT_FILE="$2"
  if [ ! -f "$PROMPT_FILE" ]; then
    echo "Error: ${PROMPT_FILE} not found" >&2
    exit 1
  fi
  cmux send --surface "${SURFACE}" -- "Read and execute the task described at ${PROMPT_FILE} — start immediately.\n"
else
  PROMPT="$*"
  cmux send --surface "${SURFACE}" -- "${PROMPT}\n"
fi

echo "Task sent to ${SURFACE}"
