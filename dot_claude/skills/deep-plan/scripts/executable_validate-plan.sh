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
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
RESULTS=()

# task_title_count / task_body_issues — shared with validate-draft.sh via
# task-body-lib.sh (see that file for why).
# shellcheck source=./task-body-lib.sh disable=SC1091 # sourced at runtime; CI shellcheck doesn't pass -x
. "$(dirname "$0")/task-body-lib.sh"

record() {
  local item="$1" status="$2" detail="$3"
  RESULTS+=("$(jq -n --arg i "$item" --arg s "$status" --arg d "$detail" \
    '{item:$i, status:$s, detail:$d}')")
}

# section_body HEADING — the body of a `## HEADING` section, up to the next
# `## `. Fence-aware: a fenced illustrative example elsewhere in the plan
# (e.g. showing another section's exact format) that happens to contain a
# line matching `## HEADING` must never be mistaken for the real section
# boundary, and content while inside any fence is never collected as body.
section_body() {
  awk -v h="$1" '
    /^```/ { infence = !infence; next }
    infence { next }
    $0 ~ "^## " h "$" { flag=1; next }
    /^## / { flag=0 }
    flag
  ' "$PLAN"
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
# don't count: an unedited template must fail. Fence-aware: a task's own body may show an
# illustrative `### Task N:` example inside a ``` block (as Task 3's own real-plan body
# does) — that must never be counted as a real task title.
# Shared with validate-draft.sh's `draft-tasks-complete` via task-body-lib.sh (see that
# file for why) so the two scripts can't quietly diverge on what "complete" means.
TASK_TITLES=$(task_title_count "$PLAN")
if [ "$TASK_TITLES" -ge 1 ]; then
  record "tasks-≥1" "pass" "$TASK_TITLES task block(s)"
else
  record "tasks-≥1" "fail" "no '### Task N: <name>' blocks (superpowers:writing-plans format required)"
fi

# Every task block must declare Files + Interfaces, and carry ≥4 checkbox steps
# (failing test → run it → implement → run it again; commit makes 5).
TASK_ISSUES=$(task_body_issues "$PLAN")
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

  # 10. Superpowers all invoked — every `- [ ]` line under the REQUIRED
  # (planning-phase) part of `## Superpowers invoked` must be either a
  # receipted `[x]` tick or an explicit declination containing the words
  # `not invoked` (e.g. `- [ ] <skill> — not invoked; <reason>` or
  # `- [ ] <skill> — not invoked as a skill; <reason>` — both real forms seen
  # in practice; no semicolon or exact phrasing is required beyond those two
  # words). The template's own `### Handoff` subsection is explicitly NOT
  # required here — its skills run during execution, after plan approval —
  # so the body used for this check stops at the first `## ` OR `### `
  # heading, unlike `superpowers-ticks-have-receipts` below, which must keep
  # seeing ticks anywhere in the section (Handoff included) so a forged tick
  # there still gets caught. Fence-aware: an illustrative fenced example
  # elsewhere in the plan must never be mistaken for this section's body.
  # A tick with no receipt is a separate failure, caught below by
  # `superpowers-ticks-have-receipts`.
  SP_REQUIRED_BODY=$(awk '
    /^```/ { infence = !infence; next }
    infence { next }
    /^## Superpowers invoked/ { inside=1; next }
    inside && (/^## / || /^### /) { inside=0 }
    inside
  ' "$PLAN")
  UNRESOLVED_SP=$(printf '%s\n' "$SP_REQUIRED_BODY" |
    sed -n 's/^- \[ \] \([a-z0-9-]*\)\(.*\)/\1\t\2/p' |
    awk -F'\t' '$2 !~ /(^|[^A-Za-z])not invoked([^A-Za-z]|$)/ {print $1}')
  if [ -z "$UNRESOLVED_SP" ]; then
    record "superpowers-all-invoked" "pass" "every required (planning-phase) skill ticked-with-receipt or explicitly declined"
  else
    record "superpowers-all-invoked" "fail" "unresolved (bare, unannotated): $(echo "$UNRESOLVED_SP" | tr '\n' ',' | sed 's/,$//')"
  fi

  # ─── Execution shape / API contract / lane-identity validators ──────────
  # 21 deterministic checks from the plan's `## Validator contract` section.
  # plan-to-json.sh is the sole source of lanes, contract, affected paths,
  # and task-to-lane tags — never re-derive any of this by hand here.

  # owns_match / valid_owns_pattern / owns_overlap — shared with
  # subplan-fanout.sh via owns-lib.sh (see that file for behavior notes).
  # shellcheck source=./owns-lib.sh disable=SC1091 # sourced at runtime; CI shellcheck doesn't pass -x
  . "$(dirname "$0")/owns-lib.sh"

  PARSER="$(dirname "$0")/plan-to-json.sh"
  [ -f "$PARSER" ] || PARSER="$(dirname "$0")/executable_plan-to-json.sh"

  PARSE_FAILED=0
  if ! PLAN_JSON=$("$PARSER" "$PLAN" 2>/dev/null); then
    record "execution-shape-present" "fail" "plan-to-json.sh could not parse execution metadata"
    PLAN_JSON='{}'
    PARSE_FAILED=1
  fi

  MODE_VAL=$(jq -r 'if .mode == null then "" else .mode end' <<<"$PLAN_JSON")
  ORCH_LANE=$(jq -r '.orchestrator_lane // ""' <<<"$PLAN_JSON")
  LANE_COUNT=$(jq '.lanes | length' <<<"$PLAN_JSON")
  KNOWN_LANES_CSV=$(jq -r '[.lanes[].name] | join(",")' <<<"$PLAN_JSON")

  # SERIAL exempts all 20 execution-shape/lane-identity items with an `n/a —
  # serial plan` pass. That exemption must key off actual ABSENCE of an
  # execution shape, not merely off the `Mode:` value on its own: gating on
  # "MODE_VAL is empty or serial" let one deleted `- Mode: `parallel`` line
  # (with the lane table left fully intact) silently exempt a real 4-lane
  # plan from every lane-safety check — lanes-own-paths-disjoint,
  # lane-names-unique, depends-on-acyclic, all of it — reporting `pass —
  # n/a` instead of checking anything.
  #
  # Gating purely on `LANE_COUNT == 0` fixes that repro but breaks a
  # different, subtler case: a plan that explicitly declares `Mode:
  # parallel` with a lane table present, but whose table header row is
  # itself malformed/missing (so the parser finds zero lanes) would then
  # ALSO get silently exempted — masking the exact "declares lanes but the
  # table doesn't parse" failure `execution-shape-present` exists to catch.
  #
  # So SERIAL is true iff EITHER of two genuinely-absent-shape signals hold:
  #   - MODE_VAL is empty (no `- Mode:` line found) AND LANE_COUNT is 0 (no
  #     lanes parsed either) — this is what a plan with no `## Execution
  #     shape` section at all looks like, and it's the only way to get here
  #     without an explicit, parseable Mode declaration;
  #   - MODE_VAL is explicitly `serial` — an intentional, well-formed serial
  #     declaration, regardless of what else is in the section.
  # A plan that declares `Mode: parallel` (or anything else non-empty,
  # non-serial) is NEVER exempted, even with zero parsed lanes — that's
  # exactly the "declared but broken" case `execution-shape-present` (and
  # `exec-mode-valid`) must fail loudly on, not wave through as `n/a`.
  SERIAL=0
  if [ "$PARSE_FAILED" -eq 0 ]; then
    if { [ -z "$MODE_VAL" ] && [ "$LANE_COUNT" -eq 0 ]; } || [ "$MODE_VAL" = "serial" ]; then
      SERIAL=1
    fi
  fi

  ITEMS_1_20=(
    execution-shape-present exec-mode-valid "lanes->=2-if-parallel"
    lanes-own-paths-disjoint affected-files-covered-by-exactly-one-lane
    lane-agent-in-allowlist lane-test-command-present contract-present-if-parallel
    contract-endpoints-complete contract-no-placeholders contract-version-present
    tasks-tagged-with-lane every-lane-has-1-task lane-task-files-subset-of-lane-owns
    lane-names-unique exactly-one-orchestrator-lane lane-name-grammar-safe
    depends-on-lanes-known depends-on-no-self depends-on-acyclic
  )

  if [ "$PARSE_FAILED" -eq 1 ]; then
    for item in "${ITEMS_1_20[@]:1}"; do
      record "$item" "fail" "plan-to-json.sh could not parse execution metadata"
    done
  elif [ "$SERIAL" -eq 1 ]; then
    for item in "${ITEMS_1_20[@]}"; do
      record "$item" "pass" "n/a — serial plan"
    done
  else
    # 1. execution-shape-present
    if [ "$LANE_COUNT" -gt 0 ]; then
      record "execution-shape-present" "pass" "lane table present with $LANE_COUNT lane(s)"
    else
      record "execution-shape-present" "fail" "'## Execution shape' present but the lane table is missing or empty"
    fi

    # 2. exec-mode-valid
    if [ "$MODE_VAL" = "parallel" ] || [ "$MODE_VAL" = "serial" ]; then
      record "exec-mode-valid" "pass" "mode=$MODE_VAL"
    else
      record "exec-mode-valid" "fail" "mode='$MODE_VAL' is neither parallel nor serial"
    fi

    # 3. lanes->=2-if-parallel
    if [ "$MODE_VAL" = "parallel" ]; then
      WORKER_COUNT=$(jq --arg orch "$ORCH_LANE" '[.lanes[] | select(.name != $orch)] | length' <<<"$PLAN_JSON")
      if [ "$WORKER_COUNT" -ge 2 ]; then
        record "lanes->=2-if-parallel" "pass" "$WORKER_COUNT non-orchestrator lane(s)"
      else
        record "lanes->=2-if-parallel" "fail" "$WORKER_COUNT non-orchestrator lane(s) (need >=2)"
      fi
    else
      record "lanes->=2-if-parallel" "pass" "not a parallel plan (mode=$MODE_VAL)"
    fi

    # Ownership entries, flattened across all lanes — shared by items 4, 5, 14.
    LANE_ARR=()
    PATTERN_ARR=()
    while IFS=$'\t' read -r lname pat; do
      [ -z "$pat" ] && continue
      LANE_ARR+=("$lname")
      PATTERN_ARR+=("$pat")
    done < <(jq -r '.lanes[] | .name as $n | .owns[] | "\($n)\t\(.)"' <<<"$PLAN_JSON")
    OWNS_N=${#PATTERN_ARR[@]}

    # 4. lanes-own-paths-disjoint
    OWNS_BAD=""
    i=0
    while [ "$i" -lt "$OWNS_N" ]; do
      valid_owns_pattern "${PATTERN_ARR[$i]}" || OWNS_BAD="${OWNS_BAD}${OWNS_BAD:+, }${LANE_ARR[$i]}:${PATTERN_ARR[$i]}"
      i=$((i + 1))
    done
    OWNS_OVERLAP=""
    i=0
    while [ "$i" -lt "$OWNS_N" ]; do
      j=$((i + 1))
      while [ "$j" -lt "$OWNS_N" ]; do
        if [ "${LANE_ARR[$i]}" != "${LANE_ARR[$j]}" ] && owns_overlap "${PATTERN_ARR[$i]}" "${PATTERN_ARR[$j]}"; then
          OWNS_OVERLAP="${OWNS_OVERLAP}${OWNS_OVERLAP:+, }${LANE_ARR[$i]}:${PATTERN_ARR[$i]} vs ${LANE_ARR[$j]}:${PATTERN_ARR[$j]}"
        fi
        j=$((j + 1))
      done
      i=$((i + 1))
    done
    if [ -n "$OWNS_BAD" ]; then
      record "lanes-own-paths-disjoint" "fail" "invalid ownership syntax: ${OWNS_BAD}"
    elif [ -n "$OWNS_OVERLAP" ]; then
      record "lanes-own-paths-disjoint" "fail" "overlapping ownership: ${OWNS_OVERLAP}"
    else
      record "lanes-own-paths-disjoint" "pass" "$OWNS_N ownership entries valid and pairwise disjoint"
    fi

    # 5. affected-files-covered-by-exactly-one-lane
    AF_BAD=""
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      cnt=0
      matched=""
      i=0
      while [ "$i" -lt "$OWNS_N" ]; do
        if owns_match "$p" "${PATTERN_ARR[$i]}"; then
          cnt=$((cnt + 1))
          matched="${matched}${matched:+,}${LANE_ARR[$i]}"
        fi
        i=$((i + 1))
      done
      [ "$cnt" -ne 1 ] && AF_BAD="${AF_BAD}${AF_BAD:+; }${p}(matches=${cnt}:${matched:-none})"
    done < <(jq -r '.affected_files[]' <<<"$PLAN_JSON")
    if [ -z "$AF_BAD" ]; then
      record "affected-files-covered-by-exactly-one-lane" "pass" "every affected path matches exactly one lane"
    else
      record "affected-files-covered-by-exactly-one-lane" "fail" "$AF_BAD"
    fi

    # 6. lane-agent-in-allowlist
    ALLOWLIST="$(dirname "$0")/../../deep-execute/agents.allowlist"
    AGENT_BAD=""
    while IFS= read -r agent; do
      [ -z "$agent" ] && continue
      [ "$agent" = "orchestrator" ] && continue
      if [ -f "$ALLOWLIST" ] && grep -qxF "$agent" "$ALLOWLIST"; then
        continue
      fi
      AGENT_BAD="${AGENT_BAD}${AGENT_BAD:+, }${agent}"
    done < <(jq -r '.lanes[].agent' <<<"$PLAN_JSON")
    if [ -z "$AGENT_BAD" ]; then
      record "lane-agent-in-allowlist" "pass" "every lane agent is orchestrator or allowlisted"
    else
      record "lane-agent-in-allowlist" "fail" "not in allowlist: ${AGENT_BAD}"
    fi

    # 7. lane-test-command-present
    TC_BAD=""
    while IFS=$'\t' read -r lname tc; do
      [ -z "$lname" ] && continue
      { [ -z "$tc" ] || [ "$tc" = "none" ]; } && TC_BAD="${TC_BAD}${TC_BAD:+, }${lname}"
    done < <(jq -r '.lanes[] | "\(.name)\t\(.test_command)"' <<<"$PLAN_JSON")
    if [ -z "$TC_BAD" ]; then
      record "lane-test-command-present" "pass" "every lane declares a test command"
    else
      record "lane-test-command-present" "fail" "missing/none: ${TC_BAD}"
    fi

    # 8. contract-present-if-parallel
    if [ "$MODE_VAL" = "parallel" ]; then
      CONTRACT_NULL=$(jq -r '.contract == null' <<<"$PLAN_JSON")
      CV=$(jq -r '.contract.version // ""' <<<"$PLAN_JSON")
      CP=$(jq -r '.contract.path // ""' <<<"$PLAN_JSON")
      CK=$(jq -r '.contract.kind // ""' <<<"$PLAN_JSON")
      CVAL=$(jq -r '.contract.validation_command // ""' <<<"$PLAN_JSON")
      EP_DECLARED=0
      [ "$(jq '.contract.endpoints | length' <<<"$PLAN_JSON" 2>/dev/null || echo 0)" -gt 0 ] && EP_DECLARED=1
      grep -qE '^- Endpoints: none' "$PLAN" && EP_DECLARED=1
      if [ "$CONTRACT_NULL" = "true" ] || [ -z "$CV" ] || [ -z "$CP" ] || [ -z "$CK" ] || [ -z "$CVAL" ] || [ "$EP_DECLARED" -eq 0 ]; then
        record "contract-present-if-parallel" "fail" "missing contract field(s) for a parallel plan"
      else
        record "contract-present-if-parallel" "pass" "version/path/kind/validation_command/endpoints all present"
      fi
    else
      record "contract-present-if-parallel" "pass" "not a parallel plan (mode=$MODE_VAL)"
    fi

    # 9. contract-endpoints-complete
    EP_COUNT=$(jq '.contract.endpoints | length' <<<"$PLAN_JSON" 2>/dev/null || echo 0)
    if [ "$EP_COUNT" -eq 0 ]; then
      if grep -qE '^- Endpoints: none' "$PLAN"; then
        record "contract-endpoints-complete" "pass" "zero endpoints, declared 'Endpoints: none'"
      else
        record "contract-endpoints-complete" "fail" "zero endpoints without an 'Endpoints: none' declaration"
      fi
    else
      EP_BAD=""
      while IFS= read -r erow; do
        eid=$(jq -r '.endpoint' <<<"$erow")
        emethod=$(jq -r '.method' <<<"$erow")
        epath=$(jq -r '.full_path' <<<"$erow")
        estatus=$(jq -r '.status_codes' <<<"$erow")
        ereq=$(jq -r '.request_shape' <<<"$erow")
        eresp=$(jq -r '.response_shape' <<<"$erow")
        rowbad=""
        [ -z "$eid" ] && rowbad="no-id"
        case "$emethod" in
          GET | POST | PUT | PATCH | DELETE) ;;
          *) rowbad="${rowbad:+$rowbad,}bad-method" ;;
        esac
        case "$epath" in
          /*) ;;
          *) rowbad="${rowbad:+$rowbad,}relative-path" ;;
        esac
        [ -z "$estatus" ] && rowbad="${rowbad:+$rowbad,}no-status"
        [ -z "$ereq" ] && rowbad="${rowbad:+$rowbad,}no-request-shape"
        [ -z "$eresp" ] && rowbad="${rowbad:+$rowbad,}no-response-shape"
        if [ -n "$estatus" ] && [ -n "$eresp" ]; then
          OLDIFS=$IFS
          IFS=','
          for code in $estatus; do
            code=$(echo "$code" | tr -d '[:space:]')
            [ -z "$code" ] && continue
            echo "$eresp" | grep -q "${code}=" || rowbad="${rowbad:+$rowbad,}unmapped-${code}"
          done
          IFS=$OLDIFS
        fi
        [ -n "$rowbad" ] && EP_BAD="${EP_BAD}${EP_BAD:+; }${eid:-<no-id>}:${rowbad}"
      done < <(jq -c '.contract.endpoints[]' <<<"$PLAN_JSON")
      if [ -z "$EP_BAD" ]; then
        record "contract-endpoints-complete" "pass" "$EP_COUNT endpoint(s) complete"
      else
        record "contract-endpoints-complete" "fail" "$EP_BAD"
      fi
    fi

    # 10. contract-no-placeholders — same token set as no-tbd-placeholders,
    # plus ellipses and unresolved angle fields, scoped to the contract body.
    CONTRACT_BODY=$(section_body "API contract" | awk '/^### / {exit} {print}')
    if printf '%s\n' "$CONTRACT_BODY" | grep -qE '(TBD|TODO|<placeholder>|<TBD>|XXX-|\.\.\.|<[^>]+>)'; then
      HIT=$(printf '%s\n' "$CONTRACT_BODY" | grep -nE '(TBD|TODO|<placeholder>|<TBD>|XXX-|\.\.\.|<[^>]+>)' | head -3 | tr '\n' ';')
      record "contract-no-placeholders" "fail" "found: $HIT"
    else
      record "contract-no-placeholders" "pass" "no placeholder tokens in contract body"
    fi

    # 11. contract-version-present
    CV2=$(jq -r '.contract.version // ""' <<<"$PLAN_JSON")
    if echo "$CV2" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      record "contract-version-present" "pass" "version=$CV2"
    else
      record "contract-version-present" "fail" "version='$CV2' does not match MAJOR.MINOR.PATCH"
    fi

    # 12. tasks-tagged-with-lane — re-scan raw text (not the parser's JSON):
    # the parser keeps only the FIRST `**Lane:**` line per task, so detecting
    # a duplicate tag needs the raw count.
    TASK_LANE_ISSUES=$(awk -v knownlist="$KNOWN_LANES_CSV" '
      function check() {
        if (num == "") return
        if (lanecount == 0) print num": missing"
        else if (lanecount > 1) print num": duplicated"
        else if (index("," knownlist ",", "," lane ",") == 0) print num": unknown(" lane ")"
      }
      /^```/ { infence = !infence; next }
      infence { next }
      /^### Task [0-9]+:/ { check(); num=$0; sub(/^### Task /,"",num); sub(/:.*/,"",num); lane=""; lanecount=0; next }
      /^## / && num != "" { check(); num=""; next }
      num != "" && /^\*\*Lane:\*\*/ {
        lanecount++
        n = split($0, a, "`"); if (n >= 2) lane = a[2]
        next
      }
      END { check() }
    ' "$PLAN")
    if [ -z "$TASK_LANE_ISSUES" ]; then
      record "tasks-tagged-with-lane" "pass" "every task carries exactly one known **Lane:** tag"
    else
      record "tasks-tagged-with-lane" "fail" "$(echo "$TASK_LANE_ISSUES" | tr '\n' ';')"
    fi

    # 13. every-lane-has-1-task
    NOTASK_LANES=""
    while IFS= read -r lname; do
      [ -z "$lname" ] && continue
      cnt=$(jq --arg l "$lname" '[.tasks[] | select(.lane == $l)] | length' <<<"$PLAN_JSON")
      [ "$cnt" -eq 0 ] && NOTASK_LANES="${NOTASK_LANES}${NOTASK_LANES:+, }${lname}"
    done < <(jq -r '.lanes[].name' <<<"$PLAN_JSON")
    if [ -z "$NOTASK_LANES" ]; then
      record "every-lane-has-1-task" "pass" "every lane owns >=1 task"
    else
      record "every-lane-has-1-task" "fail" "no task for: ${NOTASK_LANES}"
    fi

    # 14. lane-task-files-subset-of-lane-owns
    TASK_FILE_BAD=""
    while IFS= read -r trow; do
      tlane=$(jq -r '.lane' <<<"$trow")
      [ "$tlane" = "null" ] && continue
      tnum=$(jq -r '.number' <<<"$trow")
      while IFS= read -r p; do
        [ -z "$p" ] && continue
        stripped="${p%%:*}"
        ok=0
        i=0
        while [ "$i" -lt "$OWNS_N" ]; do
          if [ "${LANE_ARR[$i]}" = "$tlane" ] && owns_match "$stripped" "${PATTERN_ARR[$i]}"; then
            ok=1
            break
          fi
          i=$((i + 1))
        done
        [ "$ok" -eq 0 ] && TASK_FILE_BAD="${TASK_FILE_BAD}${TASK_FILE_BAD:+; }task${tnum}:${stripped}(lane=${tlane})"
      done < <(jq -r '.files.create[], .files.modify[], .files.verify[]' <<<"$trow")
    done < <(jq -c '.tasks[]' <<<"$PLAN_JSON")
    if [ -z "$TASK_FILE_BAD" ]; then
      record "lane-task-files-subset-of-lane-owns" "pass" "every task path is owned by its own lane"
    else
      record "lane-task-files-subset-of-lane-owns" "fail" "$TASK_FILE_BAD"
    fi

    # 15. lane-names-unique
    DUP_LANES=$(jq -r '[.lanes[].name] | group_by(.) | map(select(length > 1) | .[0]) | join(", ")' <<<"$PLAN_JSON")
    if [ -z "$DUP_LANES" ]; then
      record "lane-names-unique" "pass" "no duplicate lane names"
    else
      record "lane-names-unique" "fail" "duplicated: $DUP_LANES"
    fi

    # 16. exactly-one-orchestrator-lane
    ORCH_COUNT=$(jq '[.lanes[] | select(.agent == "orchestrator")] | length' <<<"$PLAN_JSON")
    ORCH_NAMES=$(jq -r '[.lanes[] | select(.agent == "orchestrator") | .name] | join(",")' <<<"$PLAN_JSON")
    if [ "$ORCH_COUNT" -eq 1 ] && [ "$ORCH_NAMES" = "$ORCH_LANE" ]; then
      record "exactly-one-orchestrator-lane" "pass" "orchestrator lane=$ORCH_LANE"
    else
      record "exactly-one-orchestrator-lane" "fail" "count=$ORCH_COUNT names=[$ORCH_NAMES] declared=$ORCH_LANE"
    fi

    # 17. lane-name-grammar-safe
    BAD_NAMES=""
    while IFS= read -r lname; do
      [ -z "$lname" ] && continue
      printf '%s' "$lname" | grep -qE '^[a-z][a-z0-9-]{0,31}$' || BAD_NAMES="${BAD_NAMES}${BAD_NAMES:+, }${lname}"
    done < <(jq -r '.lanes[].name' <<<"$PLAN_JSON")
    if [ -z "$BAD_NAMES" ]; then
      record "lane-name-grammar-safe" "pass" "all lane names match ^[a-z][a-z0-9-]{0,31}\$"
    else
      record "lane-name-grammar-safe" "fail" "invalid: ${BAD_NAMES}"
    fi

    # 18. depends-on-lanes-known
    DEP_UNKNOWN=""
    while IFS=$'\t' read -r lname dep; do
      [ -z "$lname" ] && continue
      echo ",$KNOWN_LANES_CSV," | grep -qF ",${dep}," || DEP_UNKNOWN="${DEP_UNKNOWN}${DEP_UNKNOWN:+, }${lname}->${dep}"
    done < <(jq -r '.lanes[] | .name as $n | .depends_on[] | "\($n)\t\(.)"' <<<"$PLAN_JSON")
    if [ -z "$DEP_UNKNOWN" ]; then
      record "depends-on-lanes-known" "pass" "every depends_on names a declared lane"
    else
      record "depends-on-lanes-known" "fail" "$DEP_UNKNOWN"
    fi

    # 19. depends-on-no-self
    SELF_DEP=$(jq -r '[.lanes[] | . as $l | select($l.depends_on | index($l.name)) | $l.name] | join(", ")' <<<"$PLAN_JSON")
    if [ -z "$SELF_DEP" ]; then
      record "depends-on-no-self" "pass" "no lane depends on itself"
    else
      record "depends-on-no-self" "fail" "self-dependency: $SELF_DEP"
    fi

    # 20. depends-on-acyclic — Kahn topological sort in awk over the
    # `name -> depends_on` edges; any lane left with nonzero in-degree marks
    # an unbroken cycle.
    ACYCLIC_DETAIL=$(jq -r '
      (.lanes[] | "N\t" + .name),
      (.lanes[] | .name as $n | .depends_on[] | "E\t" + $n + "\t" + .)
    ' <<<"$PLAN_JSON" | awk -F'\t' '
      $1 == "N" { nodes[$2] = 1; if (!($2 in indeg)) indeg[$2] = 0; next }
      $1 == "E" { adj[$3] = adj[$3] SUBSEP $2; indeg[$2]++; next }
      END {
        n = 0
        for (nd in nodes) n++
        qn = 0
        for (nd in nodes) if (indeg[nd] == 0) { queue[qn] = nd; qn++ }
        consumed = 0
        head = 0
        while (head < qn) {
          cur = queue[head]; head++
          consumed++
          cnt = split(adj[cur], deps, SUBSEP)
          for (k = 1; k <= cnt; k++) {
            nd2 = deps[k]
            if (nd2 == "") continue
            indeg[nd2]--
            if (indeg[nd2] == 0) { queue[qn] = nd2; qn++ }
          }
        }
        if (consumed < n) {
          unresolved = ""
          for (nd in nodes) if (indeg[nd] > 0) unresolved = unresolved " " nd
          print "cycle involving:" unresolved
        }
      }
    ')
    if [ -z "$ACYCLIC_DETAIL" ]; then
      record "depends-on-acyclic" "pass" "depends_on graph is acyclic"
    else
      record "depends-on-acyclic" "fail" "$ACYCLIC_DETAIL"
    fi
  fi

  # 21. superpowers-ticks-have-receipts — always runs for real, in every
  # mode (parallel, serial, or malformed), since it guards plan integrity
  # rather than execution shape. Sees ticks ANYWHERE in the section,
  # including the `### Handoff` subsection that item 10 above exempts from
  # being required — a forged tick on a Handoff item must still fail here.
  #
  # This is a tamper-EVIDENT audit trail, chain-verified here and anchored
  # to a repo commit — NOT tamper-proof, and it proves only that
  # superpowers-invoke.sh was run with that skill name, not that the skill
  # itself ran: nothing stops an agent from calling the script without ever
  # calling `Skill()` first. It verifies three things about each line of
  # RUN_DIR/superpowers-receipts.log (format documented in
  # superpowers-invoke.sh's header):
  #   (a) the hash chain recomputes end-to-end — the first line whose
  #       recorded hash doesn't match sha256(previous-chain-hash + this
  #       line's tab-joined payload) fails loudly, naming that line;
  #   (b) every recorded repo-head-sha that isn't the literal `no-git` names
  #       a real commit that is an ancestor of the checkable repo's current
  #       HEAD;
  #   (c) every `[x]` tick in the plan has a matching line that passed both
  #       (a) and (b).
  # Anyone who can compute sha256 and has read this algorithm can still
  # forge a self-consistent chain; anyone who can rewrite local git history
  # can mint a commit for a fake receipt to point at. This mechanism raises
  # the cost of forging a receipt that this script never wrote — it does not
  # make forgery impossible, and it says nothing about whether the skill
  # itself was actually invoked. The 0444 chmod superpowers-invoke.sh
  # applies to the log is a cheap speed bump against casual editing, not
  # protection against either attack.
  RECEIPTS="${PLAN_DIR}/superpowers-receipts.log"

  if command -v sha256sum >/dev/null 2>&1; then
    SHA_CMD=(sha256sum)
  else
    SHA_CMD=(shasum -a 256)
  fi

  # Resolve a repo to verify repo-head-shas against, the same way
  # superpowers-invoke.sh resolves one to record them: prefer the plan's own
  # location, fall back to this process's cwd.
  REPO_FOR_CHECK=""
  if RG=$(git -C "$PLAN_DIR" rev-parse --show-toplevel 2>/dev/null); then
    REPO_FOR_CHECK="$RG"
  elif RG=$(git rev-parse --show-toplevel 2>/dev/null); then
    REPO_FOR_CHECK="$RG"
  fi

  CHAIN_ISSUE=""
  SHA_ISSUE=""
  : >"${SCRATCH}/valid-receipt-skills"

  if [ -f "$RECEIPTS" ]; then
    PREV_HASH=""
    LINE_NO=0
    while IFS=$'\t' read -r r_ts r_skill r_sha r_hash; do
      LINE_NO=$((LINE_NO + 1))
      { [ -z "$r_ts" ] && [ -z "$r_skill" ]; } && continue
      LINE_OK=1

      if [ -z "$r_hash" ]; then
        # Old-format line (3 fields, pre-dates repo-sha anchoring) — never
        # valid under the current contract.
        [ -z "$CHAIN_ISSUE" ] && CHAIN_ISSUE="line ${LINE_NO} (skill=${r_skill:-?}): old-format receipt (missing repo-sha/hash fields)"
        LINE_OK=0
      else
        PAYLOAD=$(printf '%s\t%s\t%s' "$r_ts" "$r_skill" "$r_sha")
        EXPECT_HASH=$(printf '%s%s' "$PREV_HASH" "$PAYLOAD" | "${SHA_CMD[@]}" | awk '{print $1}')
        if [ "$EXPECT_HASH" != "$r_hash" ]; then
          [ -z "$CHAIN_ISSUE" ] && CHAIN_ISSUE="line ${LINE_NO} (skill=${r_skill}): hash chain broken"
          LINE_OK=0
        fi

        if [ "$r_sha" != "no-git" ]; then
          if [ -z "$REPO_FOR_CHECK" ]; then
            SHA_ISSUE="${SHA_ISSUE}${SHA_ISSUE:+, }line ${LINE_NO}:${r_sha}(no git repo to verify against)"
            LINE_OK=0
          elif ! git -C "$REPO_FOR_CHECK" cat-file -e "${r_sha}^{commit}" 2>/dev/null; then
            SHA_ISSUE="${SHA_ISSUE}${SHA_ISSUE:+, }line ${LINE_NO}:${r_sha}(not-a-commit)"
            LINE_OK=0
          elif ! git -C "$REPO_FOR_CHECK" merge-base --is-ancestor "$r_sha" HEAD 2>/dev/null; then
            SHA_ISSUE="${SHA_ISSUE}${SHA_ISSUE:+, }line ${LINE_NO}:${r_sha}(not-ancestor-of-HEAD)"
            LINE_OK=0
          fi
        fi
      fi

      [ "$LINE_OK" -eq 1 ] && echo "$r_skill" >>"${SCRATCH}/valid-receipt-skills"
      PREV_HASH="$r_hash"
    done <"$RECEIPTS"
  fi

  MISSING=""
  while IFS= read -r skill; do
    [ -z "$skill" ] && continue
    grep -qxF "$skill" "${SCRATCH}/valid-receipt-skills" 2>/dev/null ||
      MISSING="${MISSING}${MISSING:+, }${skill}"
  done < <(awk '
    /^```/ { infence = !infence; next }
    infence { next }
    /^## Superpowers invoked/ { inside=1; next }
    inside && /^## / { inside=0 }
    inside
  ' "$PLAN" | sed -n 's/^- \[x\] \([a-z0-9-]*\).*/\1/p')

  if [ -n "$CHAIN_ISSUE" ]; then
    record "superpowers-ticks-have-receipts" "fail" "$CHAIN_ISSUE"
  elif [ -n "$SHA_ISSUE" ]; then
    record "superpowers-ticks-have-receipts" "fail" "invalid repo-sha: ${SHA_ISSUE}"
  elif [ -n "$MISSING" ]; then
    record "superpowers-ticks-have-receipts" "fail" "ticked without a valid receipt: ${MISSING}"
  else
    record "superpowers-ticks-have-receipts" "pass" "every ticked skill has a chain-valid, ancestor-verified receipt"
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
