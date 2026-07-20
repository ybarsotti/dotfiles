#!/usr/bin/env bash
# validate-draft.sh — deterministic check that a planner's raw draft (the
# output of dispatch-planners.sh, BEFORE plannotator review) is a genuine,
# complete plan and not an empty or mid-generation-truncated stream.
#
# This exists because a planner can exhaust its turn/time budget silently:
# `claude -p` / `codex exec` exit 0 even when they wrote nothing, or wrote
# only the first few sections before the budget ran out. dispatch-planners.sh
# only failed when BOTH planners' processes exited non-zero — a truncated but
# exit-0 draft from either one went straight to review looking legitimate.
#
# Usage:
#   validate-draft.sh <draft.md> [--json]
#
# Emits {item, status:pass|fail, detail} records — same contract as
# validate-plan.sh. Exit 0 if all pass, 1 if any fail.

set -uo pipefail

DRAFT="$1"; shift
JSON_OUT=0

while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON_OUT=1; shift ;;
    *) echo "validate-draft.sh: unknown flag '$1'" >&2; exit 2 ;;
  esac
done

[ -n "$DRAFT" ] || { echo "validate-draft.sh: missing <draft.md> argument" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "validate-draft.sh: jq required" >&2; exit 2; }

# task_title_count / task_body_issues — shared with validate-plan.sh via
# task-body-lib.sh (see that file for why).
# shellcheck source=./task-body-lib.sh
. "$(dirname "$0")/task-body-lib.sh"

# The canonical checklist item vocabulary — read from the templates rather
# than hardcoded here a second time, so `draft-tail-complete` (below) can
# never quietly drift from what superpowers:writing-plans actually emits.
# Both templates matter: a subplan's `## Checklist` is a strict subset of a
# root plan's, but reading only one would still be a second copy of the
# other's item names in spirit.
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE_PLAN="${SKILL_DIR}/templates/plan.md"
TEMPLATE_SUBPLAN="${SKILL_DIR}/templates/subplan.md"
[ -f "$TEMPLATE_PLAN" ] || { echo "validate-draft.sh: missing $TEMPLATE_PLAN (checklist vocabulary source)" >&2; exit 2; }
[ -f "$TEMPLATE_SUBPLAN" ] || { echo "validate-draft.sh: missing $TEMPLATE_SUBPLAN (checklist vocabulary source)" >&2; exit 2; }

# checklist_vocab_from FILE — every item name declared under FILE's
# `## Checklist` section, one per line. Fence-aware for consistency with
# every other section-body scan in this skill, though the templates
# themselves carry no fenced examples inside that section today.
checklist_vocab_from() {
  awk '
    /^```/ { infence = !infence; next }
    infence { next }
    /^## Checklist/ { inside = 1; next }
    inside && /^## / { inside = 0 }
    inside
  ' "$1" | sed -n 's/^- \[ \] \([^[:space:]]*\)[[:space:]]*$/\1/p'
}
CHECKLIST_VOCAB=$( { checklist_vocab_from "$TEMPLATE_PLAN"; checklist_vocab_from "$TEMPLATE_SUBPLAN"; } | sort -u)

RESULTS=()

record() {
  local item="$1" status="$2" detail="$3"
  RESULTS+=("$(jq -n --arg i "$item" --arg s "$status" --arg d "$detail" \
    '{item:$i, status:$s, detail:$d}')")
}

# A missing file is a hard, unambiguous truncation signal — record it as a
# normal failing item (not a script error) so --json output stays uniform
# for every caller, including a planner process that never wrote its file.
if [ ! -f "$DRAFT" ]; then
  record "draft-non-empty" "fail" "file does not exist: $DRAFT"
  record "draft-header-complete" "fail" "no file to inspect"
  record "draft-tasks-complete" "fail" "no file to inspect"
  record "draft-tail-complete" "fail" "no file to inspect"
  record "draft-fences-balanced" "fail" "no file to inspect"
  ALL_JSON=$(printf '%s\n' "${RESULTS[@]}" | jq -s '.')
  if [ "$JSON_OUT" -eq 1 ]; then echo "$ALL_JSON"; else
    echo "$ALL_JSON" | jq -r '.[] | "- [ ] " + .item + " — " + .detail'
  fi
  exit 1
fi

# 1. Non-empty (grep/awk on a 0-byte file report cleanly, but a silently
# empty draft — the exact bug this script exists to catch — deserves its own
# named, unambiguous item rather than falling out of the other four).
SIZE=$(wc -c < "$DRAFT" | tr -d '[:space:]')
if [ -n "$SIZE" ] && [ "$SIZE" -gt 0 ]; then
  record "draft-non-empty" "pass" "${SIZE} bytes"
else
  record "draft-non-empty" "fail" "file is empty (0 bytes)"
fi

# 2. Header complete — the superpowers:writing-plans title line plus a
# genuinely filled Goal/Architecture/Tech Stack (not just present-but-blank,
# and not a template placeholder like `<one sentence...>`). Same anchored
# patterns validate-plan.sh's writing-plans-header check already proves
# correct against real drafts, reused rather than re-invented so the two
# scripts never quietly diverge on what "complete" means.
HEADER_MISS=""
grep -aqE '^# .+ Implementation Plan$' "$DRAFT" || HEADER_MISS="${HEADER_MISS}title;"
grep -aqE '^\*\*Goal:\*\* *[^<[:space:]]' "$DRAFT" || HEADER_MISS="${HEADER_MISS}Goal;"
grep -aqE '^\*\*Architecture:\*\* *[^<[:space:]]' "$DRAFT" || HEADER_MISS="${HEADER_MISS}Architecture;"
grep -aqE '^\*\*Tech Stack:\*\* *[^<[:space:]]' "$DRAFT" || HEADER_MISS="${HEADER_MISS}Tech-Stack;"
if [ -z "$HEADER_MISS" ]; then
  record "draft-header-complete" "pass" "title + Goal/Architecture/Tech Stack present"
else
  record "draft-header-complete" "fail" "missing: $HEADER_MISS"
fi

# 3. Implementation tasks complete — the section header exists, at least one
# real `### Task N: <name>` block is inside it, AND every task block found
# has a body (Files + Interfaces + ≥4 checkbox steps) — not just a bare
# heading. Fence-aware and rejects a placeholder title
# (`### Task 1: <Component Name>`) the same way validate-plan.sh's tasks-≥1
# check does. A planner that ran dry after emitting an outline of task
# titles (three bare `### Task N:` headings, zero content) used to pass this
# check on title count alone — task_body_issues (shared with validate-plan.sh
# via task-body-lib.sh) closes that gap the same way validate-plan.sh's
# tasks-have-files-and-interfaces / tasks-have-tdd-steps checks already do.
TASK_TITLES=$(task_title_count "$DRAFT")
TASK_ISSUES=$(task_body_issues "$DRAFT")
if grep -aqE '^## Implementation tasks' "$DRAFT"; then
  HAS_TASKS_SECTION=1
else
  HAS_TASKS_SECTION=0
fi
if [ "$HAS_TASKS_SECTION" -eq 1 ] && [ "$TASK_TITLES" -ge 1 ] && [ -z "$TASK_ISSUES" ]; then
  record "draft-tasks-complete" "pass" "$TASK_TITLES task block(s), all with Files+Interfaces+≥4 steps"
else
  MISS=""
  [ "$HAS_TASKS_SECTION" -eq 0 ] && MISS="no '## Implementation tasks' section"
  [ "$TASK_TITLES" -lt 1 ] && MISS="${MISS:+$MISS; }no '### Task N: <name>' block"
  if [ -n "$TASK_ISSUES" ]; then
    ISSUE_DETAIL=$(echo "$TASK_ISSUES" | tr '\n' ';' | cut -c1-200)
    MISS="${MISS:+$MISS; }incomplete task body: $ISSUE_DETAIL"
  fi
  record "draft-tasks-complete" "fail" "$MISS"
fi

# 4. Tail complete — the draft reached its final section instead of getting
# cut off partway through. `## Checklist` is always the last section
# superpowers:writing-plans emits, and `superpowers-all-invoked` is one of
# its late, standard items — but plans that extend the checklist (this
# session's own drafts do, with lane/contract items appended after it) can
# legitimately keep going past it, so this does NOT require it to be the
# literal last line. Instead it requires two independent, content-level
# signals: the canary item is present as a real checkbox INSIDE the
# Checklist section (proves generation reached that far), and the file's
# very last non-blank line's item name is a COMPLETE, KNOWN name drawn from
# CHECKLIST_VOCAB (the templates' own `## Checklist` lists, computed above).
#
# An earlier version of this check accepted any line "shaped like" a
# checklist item (`- [ ] <word>` with anything after it) as proof the stream
# ended on an item boundary. It doesn't: `- [ ] lane-cont` and
# `- [ ] lane-contract-present and this sentence trails off mid way through`
# both match that shape while being exactly the mid-word/mid-sentence
# truncations this check exists to catch. A shape regex cannot tell
# `lane-cont` from `lane-contract-present`; checklist item names are a
# closed, enumerable set, so checking the last line's item name against that
# set can, and does.
# The heading itself always carries trailing text ("## Checklist
# (machine-validated; ...)"), so this is a prefix match on `## Checklist`,
# not section_body's exact-line match used for plain headings elsewhere.
CHECKLIST_BODY=$(awk '
  /^```/ { infence = !infence; next }
  infence { next }
  /^## Checklist/ { inside = 1; next }
  inside && /^## / { inside = 0 }
  inside
' "$DRAFT")
if grep -aqE '^## Checklist' "$DRAFT"; then
  HAS_CHECKLIST=1
else
  HAS_CHECKLIST=0
fi
if printf '%s\n' "$CHECKLIST_BODY" | grep -qE '^- \[[ xX]\] superpowers-all-invoked[[:space:]]*$'; then
  HAS_CANARY=1
else
  HAS_CANARY=0
fi
LAST_LINE=$(awk 'NF { last = $0 } END { print last }' "$DRAFT")
# Only a line that is EXACTLY `- [ ] <item>` (optional trailing whitespace,
# nothing else) yields a LAST_ITEM at all — a truncation mid-word or
# mid-sentence never matches this pattern end-to-end, so it falls through
# with LAST_ITEM empty and fails below regardless of vocabulary.
LAST_ITEM=$(printf '%s' "$LAST_LINE" | sed -n 's/^- \[[ xX]\] \([^[:space:]]*\)[[:space:]]*$/\1/p')
if [ -n "$LAST_ITEM" ] && printf '%s\n' "$CHECKLIST_VOCAB" | grep -qxF "$LAST_ITEM"; then
  LAST_WELLFORMED=1
else
  LAST_WELLFORMED=0
fi
if [ "$HAS_CHECKLIST" -eq 1 ] && [ "$HAS_CANARY" -eq 1 ] && [ "$LAST_WELLFORMED" -eq 1 ]; then
  record "draft-tail-complete" "pass" "checklist reaches 'superpowers-all-invoked' and ends on known item '$LAST_ITEM'"
else
  MISS=""
  [ "$HAS_CHECKLIST" -eq 0 ] && MISS="no '## Checklist' section"
  [ "$HAS_CANARY" -eq 0 ] && MISS="${MISS:+$MISS; }checklist never reaches 'superpowers-all-invoked'"
  if [ "$LAST_WELLFORMED" -eq 0 ]; then
    if [ -n "$LAST_ITEM" ]; then
      MISS="${MISS:+$MISS; }last line's item '$LAST_ITEM' is not a known checklist item"
    else
      MISS="${MISS:+$MISS; }last line is not a complete checklist item: '$(printf '%s' "$LAST_LINE" | cut -c1-80)'"
    fi
  fi
  record "draft-tail-complete" "fail" "$MISS"
fi

# 5. Fences balanced — an odd count of ``` lines means a fenced code block
# was opened and never closed, the single clearest byte-level fingerprint of
# a mid-block cutoff. (0 is even and passes trivially; an all-prose
# truncation is still caught by the other four checks above.)
FENCE_COUNT=$(grep -acE '^```' "$DRAFT")
if [ $(( FENCE_COUNT % 2 )) -eq 0 ]; then
  record "draft-fences-balanced" "pass" "$FENCE_COUNT fence line(s), balanced"
else
  record "draft-fences-balanced" "fail" "$FENCE_COUNT fence line(s) — an odd count means an unclosed \`\`\` block"
fi

# ─── Output ───────────────────────────────────────────────────────────────

ALL_JSON=$(printf '%s\n' "${RESULTS[@]}" | jq -s '.')
FAILS=$(echo "$ALL_JSON" | jq '[.[] | select(.status == "fail")] | length')

if [ "$JSON_OUT" -eq 1 ]; then
  echo "$ALL_JSON"
else
  printf "## validate-draft: %s\n\n" "$DRAFT"
  echo "$ALL_JSON" | jq -r '.[] | "- [" + (if .status == "pass" then "x" else " " end) + "] " + .item + " — " + .detail'
  echo
  if [ "$FAILS" -eq 0 ]; then
    echo "verdict: ALL PASS"
  else
    echo "verdict: $FAILS FAIL"
  fi
fi

[ "$FAILS" -eq 0 ] && exit 0 || exit 1
