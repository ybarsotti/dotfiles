#!/usr/bin/env bash
# handle-findings.sh — parse /deep-review report.md, emit JSON list of
# findings classified by severity, with suggested TDD cycle per CRITICAL/HIGH.
#
# Usage:
#   handle-findings.sh <deep-review-run-dir>
#
# Looks for <run-dir>/report.md (the standard /deep-review output).
# Emits JSON to stdout. Always exits 0; absence of findings is not a failure.

set -uo pipefail

RUN_DIR="${1:-}"
if [ -z "$RUN_DIR" ]; then
  # Default: latest deep-review run dir.
  RUN_DIR=$(
    find "$HOME/.claude/deep-review-runs" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null \
      | xargs -0 stat -f '%m %N' 2>/dev/null \
      | sort -rn \
      | head -1 \
      | cut -d' ' -f2-
  )
  [ -z "$RUN_DIR" ] && { echo "handle-findings.sh: no deep-review runs found" >&2; echo "[]"; exit 0; }
fi

REPORT="${RUN_DIR}/report.md"
[ -f "$REPORT" ] || { echo "handle-findings.sh: missing $REPORT" >&2; echo "[]"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "handle-findings.sh: jq required" >&2; exit 2; }

# Heuristic parser: report.md typically has lines like
#   - **[CRITICAL]** <message> (file:line)
#   - **[HIGH]** <message>
#   - HIGH: <message>
#   - 🔴 CRITICAL — <message>
# We grep for severity tokens at line start (or after a bullet) and extract.

FINDINGS=()
while IFS= read -r line; do
  sev=$(echo "$line" | grep -oiE '(CRITICAL|HIGH|MEDIUM|LOW)' | head -1 | tr '[:lower:]' '[:upper:]')
  [ -z "$sev" ] && continue
  msg=$(echo "$line" | sed -E 's/^[-*[:space:]]*(\*\*)?\[?(CRITICAL|HIGH|MEDIUM|LOW)\]?(\*\*)?[:[:space:]—-]*//I' | sed 's/^[[:space:]]*//')
  file=$(echo "$msg" | awk -F'`' 'NF >= 3 && $2 ~ /\.[[:alpha:]]+$/ { print $2; exit }')
  FINDINGS+=("$(jq -n --arg s "$sev" --arg m "$msg" --arg f "$file" \
    '{severity:$s, message:$m, file:$f}')")
done < <(grep -iE '(CRITICAL|HIGH|MEDIUM|LOW)' "$REPORT")

if [ ${#FINDINGS[@]} -eq 0 ]; then
  echo "[]"
  exit 0
fi

ALL=$(printf '%s\n' "${FINDINGS[@]}" | jq -s '
  unique_by(.message) |
  sort_by(
    if   .severity == "CRITICAL" then 0
    elif .severity == "HIGH"     then 1
    elif .severity == "MEDIUM"   then 2
    else 3 end
  )
')

# For CRITICAL/HIGH, add suggested TDD cycle: failing-test name + target file.
ENRICHED=$(echo "$ALL" | jq '
  map(
    if .severity == "CRITICAL" or .severity == "HIGH" then
      . + {
        suggested_tdd: {
          step1: "write failing test asserting the inverse of: " + .message,
          step2: ("target file: " + (if .file != "" then .file else "<infer from message>" end)),
          step3: "implement minimal fix",
          step4: ("commit: fix(review): " + (.message | tostring | .[0:60]))
        }
      }
    else . end
  )
')

echo "$ENRICHED"
