#!/usr/bin/env bash
# validate-plan.sh — deterministic validation of a deepplan plan.md.
#
# Usage:
#   validate-plan.sh <plan.md> [--root|--subplan] [--json]
#
# Checks every required item, emits JSON {item, status:pass|fail, detail}.
# Exit 0 if all pass, 1 if any fail.

set -uo pipefail

PLAN="$1"; shift
MODE="root"
JSON_OUT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --root)    MODE="root"; shift ;;
    --subplan) MODE="subplan"; shift ;;
    --json)    JSON_OUT=1; shift ;;
    *) echo "validate-plan.sh: unknown flag '$1'" >&2; exit 2 ;;
  esac
done

[ -f "$PLAN" ] || { echo "validate-plan.sh: missing $PLAN" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "validate-plan.sh: jq required" >&2; exit 2; }

PLAN_DIR=$(dirname "$PLAN")
RESULTS=()

record() {
  local item="$1" status="$2" detail="$3"
  RESULTS+=("$(jq -n --arg i "$item" --arg s "$status" --arg d "$detail" \
    '{item:$i, status:$s, detail:$d}')")
}

section_body() {
  awk -v h="$1" 'BEGIN{flag=0} $0 ~ "^## " h "$" {flag=1; next} /^## / {flag=0} flag' "$PLAN"
}

# ─── Universal checks (both root and subplan) ─────────────────────────────

# 1. Mermaid present
if grep -q '^```mermaid' "$PLAN"; then
  record "mermaid-present" "pass" "mermaid block found"
else
  record "mermaid-present" "fail" "no \`\`\`mermaid block in plan"
fi

# 2. Mermaid has entry + exit (heuristic: ≥2 actors/participants + ≥3 arrows)
MERMAID=$(awk '/^```mermaid$/{flag=1; next} /^```$/{flag=0} flag' "$PLAN")
ACTORS=$(echo "$MERMAID" | grep -cE '(participant |actor |->|-->|==>)')
ARROWS=$(echo "$MERMAID" | grep -cE '(->|-->)')
if [ "$ACTORS" -ge 2 ] && [ "$ARROWS" -ge 3 ]; then
  record "mermaid-has-entry-and-exit" "pass" "actors=$ACTORS arrows=$ARROWS"
else
  record "mermaid-has-entry-and-exit" "fail" "actors=$ACTORS arrows=$ARROWS (need ≥2 actors, ≥3 arrows)"
fi

# 3. TDD test list ≥3 bullets
TDD_BULLETS=$(section_body "TDD test list" | grep -cE '^- ')
if [ "$TDD_BULLETS" -ge 3 ]; then
  record "tdd-list-≥3" "pass" "$TDD_BULLETS tests listed"
else
  record "tdd-list-≥3" "fail" "only $TDD_BULLETS tests (need ≥3)"
fi

# 4. Edge cases ≥4 bullets
EDGE_BULLETS=$(section_body "Edge cases & failure modes" | grep -cE '^- ')
if [ "$EDGE_BULLETS" -ge 4 ]; then
  record "edges-≥4" "pass" "$EDGE_BULLETS edge cases listed"
else
  record "edges-≥4" "fail" "only $EDGE_BULLETS edges (need ≥4)"
fi

# 4.5. Clarifying questions asked (≥1 Q/A pair OR explicit `_no ambiguity_` marker)
# Reject template placeholder lines like `### Q: <question text>` / `### A: <user answer>`.
CLARIFY_BODY=$(section_body "Clarifying questions")
QPAIRS=$(echo "$CLARIFY_BODY" | grep -cE '^### Q: [^<]' || true)
APAIRS=$(echo "$CLARIFY_BODY" | grep -cE '^### A: [^<]' || true)
NO_AMBIG=0
echo "$CLARIFY_BODY" | grep -qE '^_no ambiguity_$' && NO_AMBIG=1
if [ "$NO_AMBIG" -eq 1 ]; then
  record "clarifying-questions-asked" "pass" "marked _no ambiguity_"
elif [ "$QPAIRS" -ge 1 ] && [ "$APAIRS" -ge 1 ] && [ "$QPAIRS" -eq "$APAIRS" ]; then
  record "clarifying-questions-asked" "pass" "$QPAIRS Q/A pair(s)"
else
  record "clarifying-questions-asked" "fail" "Q=$QPAIRS A=$APAIRS (need ≥1 matched non-placeholder pair or '_no ambiguity_')"
fi

# 5. No TBD/placeholders
if grep -qE '(TBD|TODO|<placeholder>|<TBD>|XXX-)' "$PLAN"; then
  HITS=$(grep -nE '(TBD|TODO|<placeholder>|<TBD>|XXX-)' "$PLAN" | head -3 | tr '\n' ';')
  record "no-tbd-placeholders" "fail" "found: $HITS"
else
  record "no-tbd-placeholders" "pass" "no placeholders found"
fi

# ─── Root-only checks ─────────────────────────────────────────────────────

if [ "$MODE" = "root" ]; then
  # 6. Adapter decision log ≥1 row
  ROWS=$(section_body "Abstractions decision log" | grep -cE '^\|.+\|.+\|')
  # Subtract header + separator rows (2)
  DATA_ROWS=$(( ROWS - 2 ))
  [ $DATA_ROWS -lt 0 ] && DATA_ROWS=0
  if [ "$DATA_ROWS" -ge 1 ]; then
    record "adapter-decision-log-≥1-row" "pass" "$DATA_ROWS data row(s)"
  else
    record "adapter-decision-log-≥1-row" "fail" "no data rows in decision log table"
  fi

  # 7. Affected files: at least one path exists (or under existing dir)
  PATHS=$(section_body "Affected files" | grep -oE '`[^`]+`' | tr -d '`' | head -20)
  PATHS_OK=0
  for p in $PATHS; do
    if [ -e "$p" ] || [ -d "$(dirname "$p")" ]; then
      PATHS_OK=$(( PATHS_OK + 1 ))
    fi
  done
  if [ "$PATHS_OK" -ge 1 ]; then
    record "affected-files-paths-exist" "pass" "$PATHS_OK valid path(s)"
  else
    record "affected-files-paths-exist" "fail" "no affected-file path resolves on disk"
  fi

  # 8. Subplans section non-empty
  SUBPLAN_LINKS=$(section_body "Subplans" | grep -cE '\[.+\]\(subplans/.+\.md\)')
  if [ "$SUBPLAN_LINKS" -ge 1 ]; then
    record "subplans-section-non-empty" "pass" "$SUBPLAN_LINKS subplan link(s)"
  else
    record "subplans-section-non-empty" "fail" "no subplans/*.md links found"
  fi

  # 9. Each subplan file exists + has flow + tdd
  MISSING_FILES=()
  MISSING_CONTENT=()
  while IFS= read -r link; do
    [ -z "$link" ] && continue
    if [ ! -f "$PLAN_DIR/$link" ]; then
      MISSING_FILES+=("$link")
    else
      grep -q '^```mermaid' "$PLAN_DIR/$link" || MISSING_CONTENT+=("$link:no-mermaid")
      grep -q '^## TDD test list' "$PLAN_DIR/$link" || MISSING_CONTENT+=("$link:no-tdd")
    fi
  done < <(section_body "Subplans" | grep -oE 'subplans/[^)]+\.md')

  if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    record "each-subplan-file-exists" "fail" "missing: ${MISSING_FILES[*]}"
  else
    record "each-subplan-file-exists" "pass" "all subplan files present"
  fi
  if [ ${#MISSING_CONTENT[@]} -gt 0 ]; then
    record "each-subplan-has-flow-and-tdd" "fail" "${MISSING_CONTENT[*]}"
  else
    record "each-subplan-has-flow-and-tdd" "pass" "all subplans complete"
  fi

  # 10. Superpowers all invoked (4 required)
  REQUIRED_SP=("brainstorming" "writing-plans" "test-driven-development" "verification-before-completion")
  SP_BODY=$(section_body "Superpowers invoked")
  MISSING_SP=()
  for sp in "${REQUIRED_SP[@]}"; do
    if ! echo "$SP_BODY" | grep -qE "\[x\][^\n]*${sp}"; then
      MISSING_SP+=("$sp")
    fi
  done
  if [ ${#MISSING_SP[@]} -eq 0 ]; then
    record "superpowers-all-invoked" "pass" "all 4 superpowers checked"
  else
    record "superpowers-all-invoked" "fail" "missing: ${MISSING_SP[*]}"
  fi
fi

# ─── Output ───────────────────────────────────────────────────────────────

ALL_JSON=$(printf '%s\n' "${RESULTS[@]}" | jq -s '.')
FAILS=$(echo "$ALL_JSON" | jq '[.[] | select(.status == "fail")] | length')

if [ "$JSON_OUT" -eq 1 ]; then
  echo "$ALL_JSON"
else
  printf "## validate-plan: %s\n\n" "$PLAN"
  echo "$ALL_JSON" | jq -r '.[] | "- [" + (if .status == "pass" then "x" else " " end) + "] " + .item + " — " + .detail'
  echo
  if [ "$FAILS" -eq 0 ]; then
    echo "verdict: ALL PASS"
  else
    echo "verdict: $FAILS FAIL"
  fi
fi

[ "$FAILS" -eq 0 ] && exit 0 || exit 1
