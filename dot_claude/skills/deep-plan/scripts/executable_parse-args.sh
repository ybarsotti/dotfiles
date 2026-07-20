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
#
# --max-plan-iter N must satisfy 1 <= N <= 20 (exits 2 otherwise): 0 would
# silently disable the entire Phase 2 review loop (SKILL.md's loop condition
# is `ITER > --max-plan-iter`), and the ceiling keeps an arbitrarily large
# value from reaching `jq --argjson` un-clamped — 20 iterations already
# means 100 reviewer-persona invocations.
#
# A flag passed more than once is last-occurrence-wins (no error) — same as
# a normal shell `getopts`-style loop re-assigning the same variable.

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
MAX_PLAN_ITER_CEILING=20
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
      # Reject on digit count before ever evaluating the value as arithmetic
      # — a value long enough to overflow bash's 64-bit integers must not
      # wrap around into something that slips under the ceiling below.
      # MAX_PLAN_ITER_CEILING's digit count (2) is comfortably inside 15.
      if [ "${#1}" -gt 15 ]; then
        echo "parse-args.sh: --max-plan-iter must be between 1 and ${MAX_PLAN_ITER_CEILING}, got '$1'" >&2
        exit 2
      fi
      # Force base-10 (`10#`) so a leading-zero value like "010" isn't
      # misread as octal by bash arithmetic, and so the stored value is
      # always canonical decimal — plain JSON, safe for `jq --argjson`.
      MAX_PLAN_ITER_N=$((10#$1))
      if [ "$MAX_PLAN_ITER_N" -lt 1 ]; then
        # 0 is well-formed input but a destructive value: Phase 2's loop
        # condition is `ITER > --max-plan-iter`, so 0 trips on the very
        # first iteration and silently skips the entire reviewer loop.
        echo "parse-args.sh: --max-plan-iter must be >= 1 (0 disables the whole Phase 2 review loop), got '$1'" >&2
        exit 2
      fi
      if [ "$MAX_PLAN_ITER_N" -gt "$MAX_PLAN_ITER_CEILING" ]; then
        # Ceiling of 20: each iteration fans out 5 reviewer personas, so 20
        # iterations is already 100 agent invocations — an unclamped value
        # here was passing straight through to `jq --argjson`.
        echo "parse-args.sh: --max-plan-iter must be <= ${MAX_PLAN_ITER_CEILING}, got '$1'" >&2
        exit 2
      fi
      MAX_PLAN_ITER="$MAX_PLAN_ITER_N"
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
