#!/usr/bin/env bash
# report.sh — turns recorded findings into report.md. Deterministic, no LLM.
#
# Usage: report.sh <run-dir>
#
# Reads:
#   <run-dir>/findings.jsonl   one JSON finding per line (written by record.sh)
#   <run-dir>/status.tsv       persona<TAB>runner<TAB>status  (optional)
# Writes the report to stdout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$1"
FINDINGS="${RUN_DIR}/findings.jsonl"
STATUS="${RUN_DIR}/status.tsv"

[ -f "$FINDINGS" ] || { printf 'report: ERROR: missing %s\n' "$FINDINGS" >&2; exit 1; }

MERGED=$(jq -s -f "${SCRIPT_DIR}/merge.jq" "$FINDINGS")

count_sev() { jq --arg s "$1" '[.[] | select(.severity == $s)] | length' <<< "$MERGED"; }

TOTAL=$(jq 'length' <<< "$MERGED")
N_CRITICAL=$(count_sev CRITICAL)
N_HIGH=$(count_sev HIGH)
N_MEDIUM=$(count_sev MEDIUM)
N_LOW=$(count_sev LOW)

# Severity decides the verdict. A reviewer that calls something CRITICAL and then votes
# APPROVE is the contradiction this removes.
if [ "$N_CRITICAL" -gt 0 ]; then
  VERDICT="REJECT"
elif [ "$N_HIGH" -gt 0 ]; then
  VERDICT="REQUEST_CHANGES"
elif [ "$TOTAL" -gt 0 ]; then
  VERDICT="REQUEST_CHANGES"
else
  VERDICT="APPROVE"
fi

printf '# Review Panel Report\n\n'
printf '**Verdict: %s**\n\n' "$VERDICT"
printf '## Summary\n\n'
printf -- '- Findings: %s (%s CRITICAL, %s HIGH, %s MEDIUM, %s LOW)\n' \
  "$TOTAL" "$N_CRITICAL" "$N_HIGH" "$N_MEDIUM" "$N_LOW"

if [ -f "$STATUS" ]; then
  OK=$(awk -F'\t' '$3=="ok"{n++} END{print n+0}' "$STATUS")
  BAD=$(awk -F'\t' '$3!="ok"{n++} END{print n+0}' "$STATUS")
  printf -- '- Reviewers: %s (%s ok, %s not ok)\n' "$((OK + BAD))" "$OK" "$BAD"
fi
printf '\n'

if [ "$TOTAL" -eq 0 ]; then
  printf 'No reviewer recorded a finding.\n'
  exit 0
fi

printf '## By category\n\n'
printf '| Category | CRITICAL | HIGH | MEDIUM | LOW |\n'
printf '|---|---|---|---|---|\n'
jq -r '
  group_by(.category)
  | sort_by(-(length))
  | .[]
  | "| \(.[0].category) | " +
    ([.[] | select(.severity=="CRITICAL")] | length | tostring) + " | " +
    ([.[] | select(.severity=="HIGH")]     | length | tostring) + " | " +
    ([.[] | select(.severity=="MEDIUM")]   | length | tostring) + " | " +
    ([.[] | select(.severity=="LOW")]      | length | tostring) + " |"
' <<< "$MERGED"
printf '\n'

printf '## Findings\n\n'
printf '| # | Severity | Category | File:Line | Title | Reported by |\n'
printf '|---|---|---|---|---|---|\n'
jq -r '
  to_entries[]
  | .key as $i | .value as $f
  | "| \($i + 1) | \($f.severity) | \($f.category) | \($f.file)\(if $f.line > 0 then ":\($f.line)" else "" end) | \($f.title) | \($f.personas | join(", ")) |"
' <<< "$MERGED"
printf '\n'

printf '## Detail\n\n'
jq -r '
  to_entries[]
  | .key as $i | .value as $f
  | "### \($i + 1). [\($f.severity)] \($f.title)\n"
    + "\n- **Category:** \($f.category)"
    + "\n- **Location:** \($f.file)\(if $f.line > 0 then ":\($f.line)" else "" end)"
    + "\n- **Reported by:** \($f.personas | join(", "))"
    + "\n- **Evidence:** \($f.evidence)"
    + (if ($f.description // "") != "" then "\n\n\($f.description)" else "" end)
    + (if ($f.suggestion // "") != "" then "\n\n**Suggested fix:** \($f.suggestion)" else "" end)
    + "\n"
' <<< "$MERGED"

printf '## Per reviewer\n\n'
jq -r '
  [.[] | . as $f | $f.personas[] | {persona: ., severity: $f.severity}]
  | group_by(.persona)
  | .[]
  | "- \(.[0].persona): \(length) finding(s) — " +
    ([.[] | select(.severity=="CRITICAL")] | length | tostring) + " CRITICAL, " +
    ([.[] | select(.severity=="HIGH")]     | length | tostring) + " HIGH, " +
    ([.[] | select(.severity=="MEDIUM")]   | length | tostring) + " MEDIUM, " +
    ([.[] | select(.severity=="LOW")]      | length | tostring) + " LOW"
' <<< "$MERGED"

if [ -f "$STATUS" ]; then
  NOT_OK=$(awk -F'\t' '$3!="ok"' "$STATUS")
  if [ -n "$NOT_OK" ]; then
    printf '\n## Reviewers that did not report\n\n'
    awk -F'\t' '$3!="ok" {printf "- %s (%s): %s\n", $1, $2, $3}' "$STATUS"
  fi
fi
