#!/usr/bin/env bash
# aggregate-verdicts.sh — collect the 4 verdict JSON files for an iteration,
# print a consolidated summary, exit 0 if all APPROVED, 1 otherwise.
#
# Usage: aggregate-verdicts.sh <run-dir> <iter>

set -uo pipefail

RUN_DIR="$1"
ITER="$2"

PERSONAS=("architect" "project-developer" "flow-mapper" "qa")

ALL_APPROVED=1
SUMMARY=""

for persona in "${PERSONAS[@]}"; do
  f="${RUN_DIR}/verdict-${persona}-iter${ITER}.json"
  if [ ! -f "$f" ]; then
    SUMMARY+="- ${persona}: MISSING verdict file\n"
    ALL_APPROVED=0
    continue
  fi
  # Try to parse; tolerate malformed JSON by salvaging what we can.
  if ! jq -e . "$f" >/dev/null 2>&1; then
    SUMMARY+="- ${persona}: UNPARSEABLE verdict (treated as CHANGES_REQUESTED)\n"
    ALL_APPROVED=0
    continue
  fi
  verdict=$(jq -r '.verdict // "CHANGES_REQUESTED"' "$f")
  notes=$(jq -r '.notes // ""' "$f")
  SUMMARY+="- ${persona}: ${verdict} — ${notes}\n"
  if [ "$verdict" != "APPROVED" ]; then
    ALL_APPROVED=0
  fi
done

printf "## Review iteration %s\n\n" "$ITER"
printf "%b\n" "$SUMMARY"

if [ "$ALL_APPROVED" -eq 1 ]; then
  echo "verdict: ALL APPROVED"
  exit 0
fi

echo "verdict: CHANGES REQUESTED — consolidated edits:"
echo
for persona in "${PERSONAS[@]}"; do
  f="${RUN_DIR}/verdict-${persona}-iter${ITER}.json"
  [ -f "$f" ] || continue
  jq -e . "$f" >/dev/null 2>&1 || continue
  edits=$(jq -r '.proposed_edits // [] | length' "$f")
  [ "$edits" -eq 0 ] && continue
  echo "### From ${persona}"
  jq -r '.proposed_edits[] | "- **\(.section)**: \(.change)"' "$f"
  echo
done

exit 1
