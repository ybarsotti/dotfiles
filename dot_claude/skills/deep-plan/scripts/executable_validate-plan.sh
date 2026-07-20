#!/usr/bin/env bash
# validate-plan.sh — deterministic validation of a deep-plan plan.md.
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

# 4.4. Code-intel bootstrapped (marker file from bootstrap-codeintel.sh)
if [ "$MODE" = "root" ]; then
  MARKER="${PLAN_DIR}/codeintel-status.json"
  if [ -f "$MARKER" ] && jq -e '.timestamp' "$MARKER" >/dev/null 2>&1; then
    GN=$(jq -r '.gitnexus' "$MARKER")
    GR=$(jq -r '.graphify' "$MARKER")
    record "code-intel-bootstrapped" "pass" "gitnexus=${GN} graphify=${GR}"
  else
    record "code-intel-bootstrapped" "fail" "missing $MARKER (run bootstrap-codeintel.sh)"
  fi
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

# 4.6. superpowers:writing-plans task format — `### Task N:` blocks with Files/Interfaces
# and bite-sized checkbox steps. Placeholder task titles (`### Task 1: <Component Name>`)
# don't count: an unedited template must fail.
TASK_TITLES=$(grep -cE '^### Task [0-9]+: [^<]' "$PLAN")
if [ "$TASK_TITLES" -ge 1 ]; then
  record "tasks-≥1" "pass" "$TASK_TITLES task block(s)"
else
  record "tasks-≥1" "fail" "no '### Task N: <name>' blocks (superpowers:writing-plans format required)"
fi

# Every task block must declare Files + Interfaces, and carry ≥4 checkbox steps
# (failing test → run it → implement → run it again; commit makes 5).
TASK_ISSUES=$(awk '
  /^### Task [0-9]+:/ {
    if (title != "") check()
    title = $0; files = 0; ifaces = 0; steps = 0; next
  }
  /^## / && title != "" { check(); title = "" }
  title != "" && /^\*\*Files:\*\*/      { files = 1 }
  title != "" && /^\*\*Interfaces:\*\*/ { ifaces = 1 }
  title != "" && /^- \[[ x]\] \*\*Step/ { steps++ }
  END { if (title != "") check() }
  function check(   miss) {
    miss = ""
    if (!files)  miss = miss " no-Files-block"
    if (!ifaces) miss = miss " no-Interfaces-block"
    if (steps < 4) miss = miss " only-" steps "-steps"
    if (miss != "") { gsub(/^### /, "", title); print title ":" miss }
  }
' "$PLAN")
if [ -z "$TASK_ISSUES" ] && [ "$TASK_TITLES" -ge 1 ]; then
  record "tasks-have-files-and-interfaces" "pass" "all tasks declare Files + Interfaces"
  record "tasks-have-tdd-steps" "pass" "all tasks have ≥4 bite-sized steps"
else
  DETAIL=$(echo "$TASK_ISSUES" | tr '\n' ';' | cut -c1-300)
  [ "$TASK_TITLES" -lt 1 ] && DETAIL="no task blocks"
  if echo "$TASK_ISSUES" | grep -q 'no-Files-block\|no-Interfaces-block' || [ "$TASK_TITLES" -lt 1 ]; then
    record "tasks-have-files-and-interfaces" "fail" "$DETAIL"
  else
    record "tasks-have-files-and-interfaces" "pass" "all tasks declare Files + Interfaces"
  fi
  if echo "$TASK_ISSUES" | grep -q 'only-' || [ "$TASK_TITLES" -lt 1 ]; then
    record "tasks-have-tdd-steps" "fail" "$DETAIL (need ≥4 '- [ ] **Step N:' per task)"
  else
    record "tasks-have-tdd-steps" "pass" "all tasks have ≥4 bite-sized steps"
  fi
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
  # 5.5 superpowers:writing-plans document header (title + worker sub-skill line + Goal/Architecture/Tech Stack)
  HEADER_MISS=()
  grep -qE '^# .+ Implementation Plan$' "$PLAN" || HEADER_MISS+=("title-not-'# X Implementation Plan'")
  grep -qE 'REQUIRED SUB-SKILL' "$PLAN"          || HEADER_MISS+=("no-agentic-worker-line")
  grep -qE '^\*\*Goal:\*\* *[^<[:space:]]' "$PLAN"         || HEADER_MISS+=("no-Goal")
  grep -qE '^\*\*Architecture:\*\* *[^<[:space:]]' "$PLAN" || HEADER_MISS+=("no-Architecture")
  grep -qE '^\*\*Tech Stack:\*\* *[^<[:space:]]' "$PLAN"   || HEADER_MISS+=("no-Tech-Stack")
  if [ ${#HEADER_MISS[@]} -eq 0 ]; then
    record "writing-plans-header" "pass" "header matches superpowers:writing-plans"
  else
    record "writing-plans-header" "fail" "missing: ${HEADER_MISS[*]}"
  fi

  # 5.6 Global Constraints section filled (writing-plans: every task inherits it)
  GC_LINES=$(section_body "Global Constraints" | grep -cE '^- [^<]')
  if [ "$GC_LINES" -ge 1 ]; then
    record "global-constraints-present" "pass" "$GC_LINES constraint(s)"
  else
    record "global-constraints-present" "fail" "'## Global Constraints' has no filled bullets (write the spec's project-wide rules verbatim)"
  fi

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
  PATHS=$(section_body "Affected files" | awk -F'`' 'NF >= 3 { for (i = 2; i <= NF; i += 2) print $i }' | head -20)
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

  # 9.5 Rationale & key decisions present (feeds the PR description)
  RAT_LINES=$(section_body "Rationale & key decisions" | grep -cE '\S')
  if [ "$RAT_LINES" -ge 1 ]; then
    record "rationale-present" "pass" "$RAT_LINES line(s) of rationale"
  else
    record "rationale-present" "fail" "empty '## Rationale & key decisions' section"
  fi

  # 9.6 Mocking policy stated in the TDD section (mock only outer boundaries)
  TDD_SECTION=$(section_body "TDD test list")
  if echo "$TDD_SECTION" | grep -qiE 'mock' && \
     echo "$TDD_SECTION" | grep -qiE 'outer|boundar|external|3rd-party|third-party|network'; then
    record "mocking-policy-stated" "pass" "TDD section states outer-boundary-only mocking"
  else
    record "mocking-policy-stated" "fail" "TDD section must state: mock only outermost boundaries; inner services/repos run real"
  fi

  # 9.65 Documentation impact listed (docs often hold logic; must be addressed)
  DOCS_LINES=$(section_body "Documentation impact" | grep -cE '\S')
  if [ "$DOCS_LINES" -ge 1 ]; then
    record "docs-impact-listed" "pass" "$DOCS_LINES line(s) in documentation impact"
  else
    record "docs-impact-listed" "fail" "empty '## Documentation impact' — list affected docs or write 'none — no docs describe this logic'"
  fi

  # 9.7 QA / test-execution flag set (yes/no)
  QA_FLAG=$(section_body "QA / test-execution" | grep -ciE '\b(yes|no)\b')
  if [ "$QA_FLAG" -ge 1 ]; then
    record "qa-flag-set" "pass" "QA flag present"
  else
    record "qa-flag-set" "fail" "'## QA / test-execution' must answer yes/no (changes flows or adds screens?)"
  fi

  # 10. Superpowers all invoked (planning-phase skills only; execution skills run after handoff)
  REQUIRED_SP=("grill-with-docs" "brainstorming" "writing-plans")
  SP_BODY=$(section_body "Superpowers invoked")
  MISSING_SP=()
  for sp in "${REQUIRED_SP[@]}"; do
    if ! echo "$SP_BODY" | grep -qE "\[x\][^\n]*${sp}"; then
      MISSING_SP+=("$sp")
    fi
  done
  if [ ${#MISSING_SP[@]} -eq 0 ]; then
    record "superpowers-all-invoked" "pass" "all ${#REQUIRED_SP[@]} required superpowers checked"
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
