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
CODEX_MODEL="${DEEP_REVIEW_CODEX_MODEL:-gpt-6-sol}"
CODEX_EFFORT="${DEEP_REVIEW_CODEX_EFFORT:-medium}"

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
OUT_FILE=$(mktemp)
trap 'rm -f "$INPUT_PIPE" "$LAST_MSG" "$OUT_FILE"' EXIT

{
  cat "$PROMPT_FILE"
  echo
  echo "---"
  echo
  cat "$CONTEXT_FILE"
} > "$INPUT_PIPE"

case "$RUNNER" in
  claude)
    # Headless print mode. Reviewers always run on Sonnet; --max-turns caps runaway sessions
    # while leaving enough room to explore a real multi-file diff before rendering a verdict.
    run_with_timeout "$TIMEOUT" \
      claude -p \
        --model sonnet \
        --output-format text \
        --max-turns "${DEEP_REVIEW_MAX_TURNS:-20}" \
        --dangerously-skip-permissions \
        < "$INPUT_PIPE" > "$OUT_FILE"
    EXIT_CODE=$?
    ;;
  codex)
    # Non-interactive. `-` reads prompt from stdin; --output-last-message captures only
    # the final answer (codex's stdout otherwise contains lots of progress noise).
    # We discard codex's noisy stdout/stderr (sent to caller's log via outer redirection)
    # and emit only the final message on our stdout.
    # Codex filters the environment of its shell commands (shell_environment_policy), so
    # DEEP_REVIEW_FINDINGS must be set again for them, or record.sh has no findings file.
    CODEX_ENV=()
    [ -n "${DEEP_REVIEW_FINDINGS:-}" ] \
      && CODEX_ENV=(-c "shell_environment_policy.set.DEEP_REVIEW_FINDINGS=\"${DEEP_REVIEW_FINDINGS}\"")
    run_with_timeout "$TIMEOUT" \
      codex exec \
        --model "$CODEX_MODEL" \
        -c model_reasoning_effort="$CODEX_EFFORT" \
        ${CODEX_ENV[@]+"${CODEX_ENV[@]}"} \
        --skip-git-repo-check \
        --dangerously-bypass-approvals-and-sandbox \
        --color never \
        --output-last-message "$LAST_MSG" \
        - < "$INPUT_PIPE" >&2
    EXIT_CODE=$?
    [ -s "$LAST_MSG" ] && cp "$LAST_MSG" "$OUT_FILE"
    ;;
  *)
    echo "reviewer.sh: unknown runner '$RUNNER'" >&2
    exit 1
    ;;
esac

cat "$OUT_FILE"

# In record mode the reviewer ends with `done: <n> finding(s)`. A missing line, or fewer
# findings in the run's file than the reviewer claims, means its findings went elsewhere.
# Fail the reviewer so the report lists it, instead of counting it as a clean review.
if [ "$EXIT_CODE" -eq 0 ] && [ -n "${DEEP_REVIEW_FINDINGS:-}" ]; then
  CLAIMED=$(sed -nE 's/.*done: ([0-9]+) finding.*/\1/p' "$OUT_FILE" | tail -1)
  RECORDED=0
  [ -s "$DEEP_REVIEW_FINDINGS" ] \
    && RECORDED=$(jq -s --arg p "$PERSONA" '[.[] | select(.persona == $p)] | length' "$DEEP_REVIEW_FINDINGS")
  if [ -z "$CLAIMED" ]; then
    echo "reviewer.sh: FAIL: no 'done: <n> finding(s)' line in the final message" >&2
    EXIT_CODE=3
  elif [ "$CLAIMED" -gt "$RECORDED" ]; then
    echo "reviewer.sh: FAIL: reported ${CLAIMED} finding(s), recorded ${RECORDED}" >&2
    EXIT_CODE=3
  fi
fi

ELAPSED=$(( $(date +%s) - START_TS ))
echo "reviewer.sh: ${PERSONA} (${RUNNER}) finished in ${ELAPSED}s with exit ${EXIT_CODE}" >&2
exit "$EXIT_CODE"
