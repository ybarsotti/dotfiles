#!/usr/bin/env bash
# ci-and-copilot-watch.sh — poll gh pr checks until settled, fetch Copilot comments.
#
# Usage: ci-and-copilot-watch.sh <pr-url> [--max-iter 5] [--poll-secs 30]
#
# Emits JSON to stdout: {ci: {state, failed_checks: [...]}, copilot: {comments: [...]}}

set -uo pipefail

PR_URL="$1"; shift
MAX_ITER=60   # 60 * 30s = 30 min default ceiling
POLL_SECS=30

while [ $# -gt 0 ]; do
  case "$1" in
    --max-iter)  MAX_ITER="$2"; shift 2 ;;
    --poll-secs) POLL_SECS="$2"; shift 2 ;;
    *) echo "ci-and-copilot-watch.sh: unknown flag '$1'" >&2; exit 1 ;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "gh not installed" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq not installed" >&2; exit 1; }

PR_NUM=$(echo "$PR_URL" | grep -oE '[0-9]+$')
[ -n "$PR_NUM" ] || { echo "ci-and-copilot-watch.sh: cannot parse PR number from '$PR_URL'" >&2; exit 1; }

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

i=0
while [ $i -lt "$MAX_ITER" ]; do
  CHECKS_JSON=$(gh pr checks "$PR_NUM" --json state,name,link 2>/dev/null || echo '[]')
  PENDING=$(echo "$CHECKS_JSON" | jq '[.[] | select(.state == "PENDING" or .state == "IN_PROGRESS" or .state == "QUEUED")] | length')
  if [ "$PENDING" -eq 0 ]; then
    break
  fi
  echo "ci-watch: ${PENDING} check(s) pending; sleeping ${POLL_SECS}s (iter $((i+1))/${MAX_ITER})" >&2
  sleep "$POLL_SECS"
  i=$((i+1))
done

# Final state
CHECKS_JSON=$(gh pr checks "$PR_NUM" --json state,name,link 2>/dev/null || echo '[]')
FAILED=$(echo "$CHECKS_JSON" | jq '[.[] | select(.state == "FAILURE" or .state == "ERROR")]')
OVERALL="success"
if [ "$(echo "$FAILED" | jq 'length')" -gt 0 ]; then OVERALL="failure"; fi

# Copilot review comments. Copilot posts as a user with login matching "copilot-pull-request-reviewer[bot]" or similar.
COMMENTS=$(gh api "/repos/${REPO}/pulls/${PR_NUM}/comments" --paginate 2>/dev/null | \
  jq '[.[] | select(.user.login | test("copilot"; "i")) | {path, line, body, html_url}]' \
  || echo '[]')

jq -n \
  --argjson ci_failed "$FAILED" \
  --arg ci_state "$OVERALL" \
  --argjson cp "$COMMENTS" \
  '{ci: {state: $ci_state, failed_checks: $ci_failed}, copilot: {comments: $cp}}'
