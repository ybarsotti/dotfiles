#!/usr/bin/env bash
# tick-checklist.sh — re-write `[ ]` → `[x]` in the plan's `## Checklist`
# section for every item that validate-plan.sh reports as `pass`. Items that
# fail stay `[ ]`. The LLM never edits checkboxes directly; it always calls
# this script after writing/modifying the plan.
#
# Usage:
#   tick-checklist.sh <plan.md> [--root|--subplan]
#
# Exit 0 if all items pass after ticking; 1 if any remain `[ ]`.

set -uo pipefail

PLAN="$1"; shift
MODE_FLAG="--root"
[ "${1:-}" = "--subplan" ] && MODE_FLAG="--subplan"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATE="${SKILL_DIR}/scripts/validate-plan.sh"

[ -f "$PLAN" ] || { echo "tick-checklist.sh: missing $PLAN" >&2; exit 2; }
[ -x "$VALIDATE" ] || { echo "tick-checklist.sh: validate-plan.sh not executable: $VALIDATE" >&2; exit 2; }

# Run validation, get JSON results.
RESULTS=$("$VALIDATE" "$PLAN" "$MODE_FLAG" --json) || true

# For each passed item, flip `[ ] item-name` → `[x] item-name` inside the Checklist section.
# macOS awk rejects newlines in -v values, so pass the list via a temp file.
PASS_FILE=$(mktemp)
TMP=$(mktemp)
trap 'rm -f "$PASS_FILE" "$TMP"' EXIT
echo "$RESULTS" | jq -r '.[] | select(.status == "pass") | .item' > "$PASS_FILE"

# Edit only lines inside `## Checklist` section.
awk -v passfile="$PASS_FILE" '
  BEGIN {
    while ((getline line < passfile) > 0) ok[line] = 1
    close(passfile)
    in_section = 0
  }
  /^## Checklist/ { in_section = 1; print; next }
  /^## / && in_section { in_section = 0 }
  in_section && /^- \[ \] / {
    for (item in ok) {
      if (index($0, "[ ] " item) > 0) {
        sub(/\[ \]/, "[x]")
        break
      }
    }
    print; next
  }
  { print }
' "$PLAN" > "$TMP"

mv "$TMP" "$PLAN"

# Re-validate to determine exit code (some items may still be `[ ]`).
FAILS=$(echo "$RESULTS" | jq '[.[] | select(.status == "fail")] | length')
PASSES=$(echo "$RESULTS" | jq '[.[] | select(.status == "pass")] | length')
echo "tick-checklist: $PASSES passed, $FAILS failed" >&2
[ "$FAILS" -eq 0 ] && exit 0 || exit 1
