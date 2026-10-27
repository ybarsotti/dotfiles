#!/usr/bin/env bash
# record.sh — a reviewer records ONE finding.
#
# Usage:
#   record.sh --persona ID --category CAT --severity SEV --title T --evidence E
#             [--file PATH] [--line N] [--description D] [--suggestion S]
#             [--remark R] [--findings PATH]
#   record.sh --persona ID --clean SECTION [--findings PATH]
#
# --remark is the finding as one short comment a person can paste on the PR: a question
# with the fix inside, at most REMARK_LIMIT characters. --clean records that a section of
# the persona's checklist ran and found nothing; it goes to clean.jsonl beside the
# findings file, so the report can show what was checked, not only what failed.
#
# Appends one compact JSON line to the findings file. Every reviewer appends to the
# same file concurrently. One printf of a single line under APPEND_LIMIT bytes is an
# atomic append on a local filesystem, so no lock is needed and no reviewer can
# overwrite another's finding.
#
# The findings file comes from --findings or $DEEP_REVIEW_FINDINGS.

set -euo pipefail

APPEND_LIMIT=4096

VALID_SEVERITY="CRITICAL HIGH MEDIUM LOW QUESTION"
REMARK_LIMIT=160
VALID_CATEGORY="security correctness concurrency db-performance typing architecture
simplicity code-reuse tests docs project-fit scope frontend observability
ui-ux accessibility responsiveness shortcut"

PERSONA=""; CATEGORY=""; SEVERITY=""; TITLE=""; EVIDENCE=""
FILE="-"; LINE="0"; DESCRIPTION=""; SUGGESTION=""; REMARK=""; CLEAN=""
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
    --clean)        CLEAN="$2"; shift 2 ;;
    --findings)     FINDINGS="$2"; shift 2 ;;
    *)              err "unknown flag: $1" ;;
  esac
done

command -v jq >/dev/null 2>&1 || err "jq not installed (brew install jq)"

[ -n "$FINDINGS" ] || err "no findings file (pass --findings or set DEEP_REVIEW_FINDINGS)"
[ -n "$PERSONA" ]  || err "--persona is required"

if [ -n "$CLEAN" ]; then
  jq -cn --arg persona "$PERSONA" --arg clean "$CLEAN" '{persona:$persona,clean:$clean}' \
    >> "$(dirname "$FINDINGS")/clean.jsonl"
  printf 'record: %s clean: %s\n' "$PERSONA" "$CLEAN" >&2
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
