#!/usr/bin/env bash
# verify-evidence.sh — the mechanical half of a blindspot pass.
#
# Usage: verify-evidence.sh <run-dir>
#
# Every finding cites a location. record.sh proves the citation is PRESENT; it cannot
# prove the reviewer OPENED it. A citation that does not resolve in the working tree is
# the one blindspot a script can catch: the reviewer wrote a path:line it never read.
#
# Reads  <run-dir>/findings.jsonl
# Writes a Markdown section to stdout, and nothing at all when every citation resolves.
# Exit code is always 0. This pass informs the reader; it does not fail the run.

set -uo pipefail

RUN_DIR="${1:?usage: verify-evidence.sh <run-dir>}"
FINDINGS="${RUN_DIR}/findings.jsonl"

[ -s "$FINDINGS" ] || exit 0
command -v jq >/dev/null 2>&1 || { printf 'verify-evidence: jq not installed\n' >&2; exit 0; }

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Resolve one citation. Echoes a reason when it does not hold, nothing when it does.
check_citation() {
  local path="$1" line="$2"
  [ -z "$path" ] && return 0
  [ "$path" = "-" ] && return 0
  local full="${REPO_ROOT}/${path}"
  if [ ! -f "$full" ]; then
    printf 'no such file (deleted by the diff, or never opened)'
    return 0
  fi
  if [ "$line" -gt 0 ]; then
    local total
    total=$(wc -l < "$full" | tr -d " ")
    if [ "$line" -gt "$((total + 1))" ]; then
      printf 'file has %s lines' "$total"
    fi
  fi
}

UNRESOLVED=""
while IFS=$'\t' read -r persona title file line evidence; do
  # The --file/--line pair, then a path:line inside --evidence. Both are citations.
  reason=$(check_citation "$file" "${line:-0}")
  [ -n "$reason" ] && UNRESOLVED+="| ${persona} | ${title} | \`${file}:${line}\` | ${reason} |"$'\n'

  if [[ "$evidence" =~ ^([^[:space:]:]+):([0-9]+) ]]; then
    e_path="${BASH_REMATCH[1]}"; e_line="${BASH_REMATCH[2]}"
    if [ "$e_path" != "$file" ] || [ "$e_line" != "$line" ]; then
      reason=$(check_citation "$e_path" "$e_line")
      [ -n "$reason" ] && UNRESOLVED+="| ${persona} | ${title} | \`${e_path}:${e_line}\` (evidence) | ${reason} |"$'\n'
    fi
  fi
done < <(jq -r '[.persona, .title, .file, (.line|tostring), .evidence] | @tsv' "$FINDINGS")

[ -n "$UNRESOLVED" ] || exit 0

printf '## Blindspot — citations that do not resolve\n\n'
printf 'A citation is not a reading. These findings point at a location this reviewer may never\n'
printf 'have opened. Confirm each one before you act on it, or drop the finding.\n\n'
printf '| Reviewer | Finding | Citation | Why it does not resolve |\n'
printf '|---|---|---|---|\n'
printf '%s\n' "$UNRESOLVED"
printf 'A path the diff deletes resolves this way too, and is not a mistake.\n'
