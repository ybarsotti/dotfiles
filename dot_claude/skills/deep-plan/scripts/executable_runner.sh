#!/usr/bin/env bash
# runner.sh — invoke a single agent (claude -p OR codex exec) with a prompt file.
#
# Usage: runner.sh <runner:claude|codex> <model> <prompt-file> [timeout-secs]
#
# stdout → final message (claude prints directly; codex captured via --output-last-message)
# stderr → progress + diagnostics

set -uo pipefail

RUNNER="$1"
MODEL="$2"
PROMPT_FILE="$3"
TIMEOUT="${4:-900}"

[ -f "$PROMPT_FILE" ] || { echo "runner.sh: prompt missing: $PROMPT_FILE" >&2; exit 1; }

if command -v gtimeout >/dev/null 2>&1; then
  run_with_timeout() { gtimeout "$@"; }
elif command -v timeout >/dev/null 2>&1; then
  run_with_timeout() { timeout "$@"; }
else
  run_with_timeout() {
    local secs="$1"; shift
    perl -e 'alarm shift @ARGV; exec @ARGV' "$secs" "$@"
  }
fi

LAST_MSG=$(mktemp)
trap 'rm -f "$LAST_MSG"' EXIT

case "$RUNNER" in
  claude)
    run_with_timeout "$TIMEOUT" \
      claude -p \
        --model "$MODEL" \
        --output-format text \
        --max-turns 8 \
        --dangerously-skip-permissions \
        < "$PROMPT_FILE"
    EXIT_CODE=$?
    ;;
  codex)
    run_with_timeout "$TIMEOUT" \
      codex exec \
        --skip-git-repo-check \
        --dangerously-bypass-approvals-and-sandbox \
        --color never \
        --output-last-message "$LAST_MSG" \
        - < "$PROMPT_FILE" >&2
    EXIT_CODE=$?
    if [ -s "$LAST_MSG" ]; then cat "$LAST_MSG"; fi
    ;;
  *)
    echo "runner.sh: unknown runner '$RUNNER'" >&2
    exit 1
    ;;
esac

exit "$EXIT_CODE"
