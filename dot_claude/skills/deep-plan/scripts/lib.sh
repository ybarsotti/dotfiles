#!/usr/bin/env bash
# lib.sh — shared helpers for deep-plan scripts. Source only; never invoke
# directly (no `executable_` prefix, so chezmoi deploys it under the same
# name in the source tree and the applied tree).
#
# record ITEM STATUS DETAIL — append one JSON result to the RESULTS array.
# The caller declares RESULTS=().
# slug TEXT — lowercase TEXT and join its alphanumeric runs with "-".

record() {
  local item="$1" status="$2" detail="$3"
  RESULTS+=("$(jq -n --arg i "$item" --arg s "$status" --arg d "$detail" \
    '{item:$i, status:$s, detail:$d}')")
}

slug() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g'; }
