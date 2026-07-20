#!/usr/bin/env bash
# parse-args.sh — Phase 0's fixed argument grammar. `$ARGUMENTS` is a flat,
# space-separated token stream (a slash-command argument line, not shell
# syntax) — every flag SKILL.md's Phase 0 recognizes lives here so the skill
# just reads the JSON fields back instead of re-deriving this parsing loop
# on every run.
#
# Usage:
#   parse-args.sh "$ARGUMENTS"
#
# Emits one line of JSON:
#   {"task_description":"...", "ticket":"...", "max_plan_iter":3,
#    "no_codex":false, "skip_grill":false, "dry_run":false}
# An unrecognized `--flag` exits 2 with a message on stderr, nothing on stdout.

set -eufo pipefail

RAW="${1:-}"
# Deliberate: RAW is a flat token stream, not shell syntax to re-parse. `-f`
# (noglob, part of `set -eufo` above) makes this unquoted split safe from
# pathname expansion, and quotes inside a token are literal characters a
# task description can legitimately contain, not shell quoting to strip.
# shellcheck disable=SC2086
set -- $RAW

TICKET=""
MAX_PLAN_ITER=3
NO_CODEX=false
SKIP_GRILL=false
DRY_RUN=false
TASK_DESCRIPTION=""

append_desc() {
  if [ -z "$TASK_DESCRIPTION" ]; then
    TASK_DESCRIPTION="$1"
  else
    TASK_DESCRIPTION="$TASK_DESCRIPTION $1"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ticket)
      shift
      [ $# -gt 0 ] || { echo "parse-args.sh: --ticket requires a value" >&2; exit 2; }
      TICKET="$1"
      ;;
    --max-plan-iter)
      shift
      [ $# -gt 0 ] || { echo "parse-args.sh: --max-plan-iter requires a value" >&2; exit 2; }
      case "$1" in
        ''|*[!0-9]*)
          echo "parse-args.sh: --max-plan-iter requires a positive integer, got '$1'" >&2
          exit 2
          ;;
      esac
      MAX_PLAN_ITER="$1"
      ;;
    --no-codex)   NO_CODEX=true ;;
    --skip-grill) SKIP_GRILL=true ;;
    --dry-run)    DRY_RUN=true ;;
    --*)
      echo "parse-args.sh: unknown flag '$1'" >&2
      exit 2
      ;;
    *)
      append_desc "$1"
      ;;
  esac
  shift
done

jq -n \
  --arg task_description "$TASK_DESCRIPTION" \
  --arg ticket "$TICKET" \
  --argjson max_plan_iter "$MAX_PLAN_ITER" \
  --argjson no_codex "$NO_CODEX" \
  --argjson skip_grill "$SKIP_GRILL" \
  --argjson dry_run "$DRY_RUN" \
  '{task_description: $task_description, ticket: $ticket, max_plan_iter: $max_plan_iter,
    no_codex: $no_codex, skip_grill: $skip_grill, dry_run: $dry_run}'
