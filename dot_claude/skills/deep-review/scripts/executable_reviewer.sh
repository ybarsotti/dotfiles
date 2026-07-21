#!/usr/bin/env bash
# reviewer.sh — runs a single reviewer (claude -p OR codex exec).
#
# Usage: reviewer.sh <runner:claude|codex> <persona-id> <run-dir> [timeout-secs]
#
# Reads:
#   <run-dir>/reviewers/<persona-id>.prompt.md   (the per-reviewer prompt)
#   <run-dir>/context.md                          (shared diff context)
# Writes:
#   stdout → caller redirects to <run-dir>/results/<persona-id>.md
#   stderr → caller redirects to <run-dir>/logs/<persona-id>.log

set -uo pipefail   # NOT -e: we need to inspect exit codes ourselves

RUNNER="$1"
PERSONA="$2"
RUN_DIR="$3"
TIMEOUT="${4:-600}"

# Codex reviewers run on the strongest reasoning tier available. Override per-run with
# DEEP_REVIEW_CODEX_MODEL / DEEP_REVIEW_CODEX_EFFORT (efforts: none|minimal|low|medium|high|xhigh|max).
CODEX_MODEL="${DEEP_REVIEW_CODEX_MODEL:-gpt-5.6-sol}"
CODEX_EFFORT="${DEEP_REVIEW_CODEX_EFFORT:-xhigh}"

PROMPT_FILE="${RUN_DIR}/reviewers/${PERSONA}.prompt.md"
CONTEXT_FILE="${RUN_DIR}/context.md"

[ -f "$PROMPT_FILE" ]  || { echo "reviewer.sh: prompt missing: $PROMPT_FILE" >&2; exit 1; }
[ -f "$CONTEXT_FILE" ] || { echo "reviewer.sh: context missing: $CONTEXT_FILE" >&2; exit 1; }

# macOS ships without `timeout` by default. Prefer gtimeout (coreutils),
# fall back to GNU timeout, then to a perl one-liner that exists everywhere.
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

START_TS=$(date +%s)

# Combined input: persona prompt + shared diff context. File pipeline avoids quoting issues.
INPUT_PIPE=$(mktemp)
LAST_MSG=$(mktemp)
trap 'rm -f "$INPUT_PIPE" "$LAST_MSG"' EXIT

{
  cat "$PROMPT_FILE"
  echo
  echo "---"
  echo
  cat "$CONTEXT_FILE"
} > "$INPUT_PIPE"

case "$RUNNER" in
  claude)
    # Headless print mode. Reviewers always run on Sonnet; --max-turns 4 prevents runaway sessions.
    run_with_timeout "$TIMEOUT" \
      claude -p \
        --model sonnet \
        --output-format text \
        --max-turns 4 \
        --dangerously-skip-permissions \
        < "$INPUT_PIPE"
    EXIT_CODE=$?
    ;;
  codex)
    # Non-interactive. `-` reads prompt from stdin; --output-last-message captures only
    # the final answer (codex's stdout otherwise contains lots of progress noise).
    # We discard codex's noisy stdout/stderr (sent to caller's log via outer redirection)
    # and emit only the final message on our stdout.
    run_with_timeout "$TIMEOUT" \
      codex exec \
        --model "$CODEX_MODEL" \
        -c model_reasoning_effort="$CODEX_EFFORT" \
        --skip-git-repo-check \
        --dangerously-bypass-approvals-and-sandbox \
        --color never \
        --output-last-message "$LAST_MSG" \
        - < "$INPUT_PIPE" >&2
    EXIT_CODE=$?
    if [ -s "$LAST_MSG" ]; then
      cat "$LAST_MSG"
    fi
    ;;
  *)
    echo "reviewer.sh: unknown runner '$RUNNER'" >&2
    exit 1
    ;;
esac

ELAPSED=$(( $(date +%s) - START_TS ))
echo "reviewer.sh: ${PERSONA} (${RUNNER}) finished in ${ELAPSED}s with exit ${EXIT_CODE}" >&2
exit "$EXIT_CODE"
