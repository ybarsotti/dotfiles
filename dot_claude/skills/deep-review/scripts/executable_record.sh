#!/usr/bin/env bash
# record.sh — a reviewer records ONE finding.
#
# Usage:
#   record.sh --persona ID --category CAT --severity SEV --title T --evidence E
#             [--file PATH] [--line N] [--description D] [--suggestion S]
#             [--findings PATH]
#
# Appends one compact JSON line to the findings file. Every reviewer appends to the
# same file concurrently. One printf of a single line under APPEND_LIMIT bytes is an
# atomic append on a local filesystem, so no lock is needed and no reviewer can
# overwrite another's finding.
#
# The findings file comes from --findings or $DEEP_REVIEW_FINDINGS.

set -euo pipefail

APPEND_LIMIT=4096

VALID_SEVERITY="CRITICAL HIGH MEDIUM LOW"
VALID_CATEGORY="security correctness concurrency db-performance typing architecture
simplicity code-reuse tests docs project-fit scope frontend observability"

PERSONA=""; CATEGORY=""; SEVERITY=""; TITLE=""; EVIDENCE=""
FILE="-"; LINE="0"; DESCRIPTION=""; SUGGESTION=""
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
    --findings)     FINDINGS="$2"; shift 2 ;;
    *)              err "unknown flag: $1" ;;
  esac
done

command -v jq >/dev/null 2>&1 || err "jq not installed (brew install jq)"

[ -n "$FINDINGS" ] || err "no findings file (pass --findings or set DEEP_REVIEW_FINDINGS)"
[ -n "$PERSONA" ]  || err "--persona is required"
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

build_line() {
  jq -cn \
    --arg persona "$PERSONA" --arg category "$CATEGORY" --arg severity "$SEVERITY" \
    --arg title "$TITLE" --arg evidence "$EVIDENCE" --arg file "$FILE" \
    --argjson line "$LINE" --arg description "$1" --arg suggestion "$2" \
    '{persona:$persona,category:$category,severity:$severity,file:$file,line:$line,
      title:$title,evidence:$evidence,description:$description,suggestion:$suggestion}'
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
