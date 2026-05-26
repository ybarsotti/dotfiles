#!/usr/bin/env bash
# dispatch-planners.sh — fan out Opus + Codex planner drafts in parallel.
#
# Usage: dispatch-planners.sh <run-dir> <task-description> [--no-codex]
#
# Writes:
#   <run-dir>/draft-opus.md
#   <run-dir>/draft-codex.md  (skipped if --no-codex)
#   <run-dir>/logs/planner-{opus,codex}.log

set -uo pipefail

RUN_DIR="$1"
TASK_DESC="$2"
NO_CODEX="${3:-}"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${SKILL_DIR}/templates/plan.md"
RUNNER="${SKILL_DIR}/scripts/runner.sh"
WP_GUIDANCE="${RUN_DIR}/writing-plans-guidance.md"

mkdir -p "${RUN_DIR}/logs"

build_prompt() {
  local persona_file="$1"
  cat "$persona_file"
  if [ -f "$WP_GUIDANCE" ]; then
    printf '\n\n---\n\n## superpowers:writing-plans guidance (follow strictly)\n\n'
    cat "$WP_GUIDANCE"
  fi
  printf '\n\n---\n\n## Task\n%s\n\n---\n\n## Target skeleton\n\n' "$TASK_DESC"
  cat "$TEMPLATE"
  printf '\n\n---\n\nWrite the full plan now. Output Markdown only. No commentary.\n'
}

# Opus planner
OPUS_PROMPT=$(mktemp)
build_prompt "${SKILL_DIR}/personas/planner-opus.md" > "$OPUS_PROMPT"
"$RUNNER" claude opus "$OPUS_PROMPT" 900 \
  > "${RUN_DIR}/draft-opus.md" \
  2> "${RUN_DIR}/logs/planner-opus.log" &
OPUS_PID=$!

# Codex planner (optional)
CODEX_PID=""
if [ "$NO_CODEX" != "--no-codex" ]; then
  CODEX_PROMPT=$(mktemp)
  build_prompt "${SKILL_DIR}/personas/planner-codex.md" > "$CODEX_PROMPT"
  "$RUNNER" codex "" "$CODEX_PROMPT" 900 \
    > "${RUN_DIR}/draft-codex.md" \
    2> "${RUN_DIR}/logs/planner-codex.log" &
  CODEX_PID=$!
fi

wait "$OPUS_PID"
OPUS_EXIT=$?
CODEX_EXIT=0
if [ -n "$CODEX_PID" ]; then
  wait "$CODEX_PID"
  CODEX_EXIT=$?
fi

echo "planners: opus=${OPUS_EXIT} codex=${CODEX_EXIT}" >&2

if [ "$OPUS_EXIT" -ne 0 ] && [ "$CODEX_EXIT" -ne 0 ]; then
  echo "dispatch-planners.sh: both planners failed" >&2
  exit 1
fi

exit 0
