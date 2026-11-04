#!/usr/bin/env bash
# plan-stamp.sh — binds an approval to the exact text of a plan.
#
# Usage:
#   plan-stamp.sh approve PLAN   write PLAN.approved with the current hash
#   plan-stamp.sh check PLAN     exit 0 when the plan still matches its approval
#   plan-stamp.sh hash PLAN      print the hash only
#
# The hash covers PLAN and every file in a sibling `subplans/` directory. It
# skips the `## Deviations` section, because executors append to it after the
# approval. Any other edit changes the hash, and `check` then exits 1.
#
# Exit codes for check: 0 current, 1 changed since approval, 2 never approved.
set -euo pipefail

usage() { echo "usage: plan-stamp.sh approve|check|hash PLAN" >&2; exit 64; }
[ $# -eq 2 ] || usage
cmd="$1"
plan="$2"
[ -f "$plan" ] || { echo "plan-stamp: no plan at $plan" >&2; exit 64; }
stamp="${plan}.approved"

# Prints the plan without its `## Deviations` section and without blank lines,
# so adding that section never changes the hash. Fence-aware like
# validate-plan.sh: a fenced example of the heading never starts the skip.
strip_deviations() {
    awk '
        /^```/ { infence = !infence }
        !infence && /^## Deviations[[:space:]]*$/ { skip = 1; next }
        !infence && /^## / { skip = 0 }
        !skip && NF
    ' "$1"
}

plan_hash() {
    local dir
    dir="$(dirname "$plan")"
    {
        strip_deviations "$plan"
        if [ -d "$dir/subplans" ]; then
            find "$dir/subplans" -type f -name '*.md' | LC_ALL=C sort | while read -r f; do
                printf '\n--- %s\n' "${f#"$dir"/}"
                strip_deviations "$f"
            done
        fi
    } | shasum -a 256 | awk '{print "sha256:" $1}'
}

case "$cmd" in
    hash)
        plan_hash
        ;;
    approve)
        head_sha="$(git -C "$(dirname "$plan")" rev-parse --short HEAD 2>/dev/null || echo none)"
        {
            echo "plan_hash: $(plan_hash)"
            echo "approved_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
            echo "approved_at_commit: $head_sha"
        } >"$stamp"
        echo "plan-stamp: approved $(plan_hash)"
        ;;
    check)
        if [ ! -f "$stamp" ]; then
            echo "plan-stamp: $plan has no approval stamp" >&2
            exit 2
        fi
        approved="$(awk '/^plan_hash:/{print $2}' "$stamp")"
        current="$(plan_hash)"
        if [ "$approved" != "$current" ]; then
            echo "plan-stamp: $plan changed after approval" >&2
            echo "  approved: $approved" >&2
            echo "  current:  $current" >&2
            echo "  Move the change into ## Deviations and restore the approved text," >&2
            echo "  or get the edited plan approved again." >&2
            exit 1
        fi
        echo "plan-stamp: current ($current)"
        ;;
    *)
        usage
        ;;
esac
