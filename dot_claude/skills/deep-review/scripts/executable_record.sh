#!/usr/bin/env bash
# record.sh — a reviewer records ONE finding.
#
# Usage:
#   record.sh --persona ID --category CAT --severity SEV --title T --evidence E
#             [--file PATH] [--line N] [--description D] [--suggestion S]
#             [--remark R] [--findings PATH]
#   record.sh --persona ID --check ITEM STATUS NOTE [--check ...] [--findings PATH]
#
# --remark is the finding as one short comment a person can paste on the PR: a question
# with the fix inside, at most REMARK_LIMIT characters.
#
# --check ticks one item of the persona's required checklist. STATUS is `ok` (checked, no
# finding), `finding` (a finding was recorded for it) or `na` (nothing in this diff to
# check). NOTE is required: what was read or searched, or why the item does not apply.
# Ticks go to checklist.jsonl beside the findings file. When the run lists the persona's
# items in reviewers/<persona>.checklist, an unknown item is rejected, and the command
# prints the items still open. reviewer.sh fails a reviewer that leaves an item open.
#
# Appends one compact JSON line to the findings file. Every reviewer appends to the
# same file concurrently. One printf of a single line under APPEND_LIMIT bytes is an
# atomic append on a local filesystem, so no lock is needed and no reviewer can
# overwrite another's finding.
#
# The findings file comes from --findings or $DEEP_REVIEW_FINDINGS.
#
# A persona records at most LOW_LIMIT LOW findings ($DEEP_REVIEW_LOW_LIMIT, default 3).
# The next one is rejected, so a report cannot fill up with nits.

set -euo pipefail

APPEND_LIMIT=4096

VALID_SEVERITY="CRITICAL HIGH MEDIUM LOW QUESTION"
REMARK_LIMIT=160
LOW_LIMIT="${DEEP_REVIEW_LOW_LIMIT:-3}"
VALID_CATEGORY="security correctness concurrency db-performance typing architecture
simplicity code-reuse tests docs project-fit scope frontend observability
ui-ux accessibility responsiveness shortcut"

PERSONA=""; CATEGORY=""; SEVERITY=""; TITLE=""; EVIDENCE=""
FILE="-"; LINE="0"; DESCRIPTION=""; SUGGESTION=""; REMARK=""; CHECKS=()
FINDINGS="${DEEP_REVIEW_FINDINGS:-}"

err() { printf 'record: ERROR: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --persona)      PERSONA="$2"; shift 2 ;;
    --category)     CATEGORY="$2"; shift 2 ;;
    --severity)     SEVERITY="$2"; shift 2 ;;
    --title)        TITLE="$2"; shift 2 ;;
    --evidence)     EVIDENCE="$2"; shift 2 ;;
    --file)         FILE="$2"; shift 2 ;;
    --line)         LINE="$2"; shift 2 ;;
    --description)  DESCRIPTION="$2"; shift 2 ;;
    --suggestion)   SUGGESTION="$2"; shift 2 ;;
    --remark)       REMARK="$2"; shift 2 ;;
    --check)        [ $# -ge 4 ] || err "--check takes three values: ITEM STATUS NOTE"
                    CHECKS+=("$2" "$3" "$4"); shift 4 ;;
    --findings)     FINDINGS="$2"; shift 2 ;;
    *)              err "unknown flag: $1" ;;
  esac
done

command -v jq >/dev/null 2>&1 || err "jq not installed (brew install jq)"

[ -n "$FINDINGS" ] || err "no findings file (pass --findings or set DEEP_REVIEW_FINDINGS)"
[ -n "$PERSONA" ]  || err "--persona is required"

if [ "${#CHECKS[@]}" -gt 0 ]; then
  RUN_DIR=$(dirname "$FINDINGS")
  TICKS="${RUN_DIR}/checklist.jsonl"
  ITEMS="${RUN_DIR}/reviewers/${PERSONA}.checklist"
  # Validate every tick before the first append, so one bad tick records nothing.
  for ((i = 0; i < ${#CHECKS[@]}; i += 3)); do
    item="${CHECKS[i]}"; status="${CHECKS[i+1]}"; note="${CHECKS[i+2]}"
    case "$status" in ok|finding|na) ;; *) err "--check ${item}: status must be ok, finding or na (got: '${status}')" ;; esac
    [ -n "$note" ] || err "--check ${item}: the note is required: what you checked, or why the item does not apply"
    if [ -s "$ITEMS" ] && ! grep -qxF -- "$item" "$ITEMS"; then
      err "--check: '${item}' is not on the ${PERSONA} checklist: $(paste -sd' ' "$ITEMS")"
    fi
  done
  for ((i = 0; i < ${#CHECKS[@]}; i += 3)); do
    jq -cn --arg persona "$PERSONA" --arg id "${CHECKS[i]}" --arg status "${CHECKS[i+1]}" \
      --arg note "${CHECKS[i+2]}" '{persona:$persona,id:$id,status:$status,note:$note}' >> "$TICKS"
  done
  printf 'record: %s ticked %d item(s)\n' "$PERSONA" "$(( ${#CHECKS[@]} / 3 ))" >&2
  if [ -s "$ITEMS" ]; then
    open=$(comm -23 <(sort -u "$ITEMS") \
      <(jq -r --arg p "$PERSONA" 'select(.persona == $p) | .id' "$TICKS" | sort -u) | paste -sd' ' -)
    [ -z "$open" ] || printf 'record: %s items still open: %s\n' "$PERSONA" "$open" >&2
  fi
  exit 0
fi

[ -n "$TITLE" ]    || err "--title is required"

# Evidence is the point of this command. A finding that cannot cite the precedent it
# breaks — a path:line in this repo, or the repo rule it violates — is an opinion, and
# the panel rejects it here instead of in the report.
[ -n "$EVIDENCE" ] || err "--evidence is required: cite a path:line in this repo, or quote the rule the diff breaks"

grep -qw -- "$SEVERITY" <<< "$VALID_SEVERITY" \
  || err "--severity must be one of: $(tr '\n' ' ' <<< "$VALID_SEVERITY")(got: '$SEVERITY')"
grep -qw -- "$CATEGORY" <<< "$VALID_CATEGORY" \
  || err "--category must be one of: $(tr '\n' ' ' <<< "$VALID_CATEGORY")(got: '$CATEGORY')"

[[ "$LINE" =~ ^[0-9]+$ ]] || err "--line must be a non-negative integer (got: '$LINE')"
[ "${#REMARK}" -le "$REMARK_LIMIT" ] \
  || err "--remark must be ${REMARK_LIMIT} characters or fewer (got ${#REMARK}): one short question with the fix inside"

build_line() {
  jq -cn \
    --arg persona "$PERSONA" --arg category "$CATEGORY" --arg severity "$SEVERITY" \
    --arg title "$TITLE" --arg evidence "$EVIDENCE" --arg file "$FILE" \
    --argjson line "$LINE" --arg description "$1" --arg suggestion "$2" --arg remark "$REMARK" \
    '{persona:$persona,category:$category,severity:$severity,file:$file,line:$line,
      title:$title,evidence:$evidence,description:$description,suggestion:$suggestion,
      remark:$remark}'
}

if [ "$SEVERITY" = LOW ] && [ -f "$FINDINGS" ]; then
  lows=$(jq -c --arg p "$PERSONA" 'select(.persona == $p and .severity == "LOW")' "$FINDINGS" | wc -l)
  [ "$lows" -lt "$LOW_LIMIT" ] \
    || err "${PERSONA} already has ${LOW_LIMIT} LOW findings; record no more LOW findings"
fi

JSON_LINE=$(build_line "$DESCRIPTION" "$SUGGESTION")

# Keep the append atomic. Prose is the only part that can grow without bound, so trim
# the prose rather than dropping the finding.
if [ "${#JSON_LINE}" -ge "$APPEND_LIMIT" ]; then
  JSON_LINE=$(build_line "${DESCRIPTION:0:800}" "${SUGGESTION:0:800}")
fi
if [ "${#JSON_LINE}" -ge "$APPEND_LIMIT" ]; then
  JSON_LINE=$(build_line "" "")
fi
[ "${#JSON_LINE}" -lt "$APPEND_LIMIT" ] || err "finding too large to append atomically even after trimming"

printf '%s\n' "$JSON_LINE" >> "$FINDINGS"

printf 'record: %s/%s %s recorded\n' "$PERSONA" "$CATEGORY" "$SEVERITY" >&2
