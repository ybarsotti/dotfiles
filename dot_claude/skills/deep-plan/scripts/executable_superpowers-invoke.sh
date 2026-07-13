#!/usr/bin/env bash
# superpowers-invoke.sh — record an invocation of a superpowers skill in the
# plan's `## Superpowers invoked` section. Marks the matching `[ ]` as `[x]`
# and appends a timestamp.
#
# The orchestrator calls this AFTER actually invoking the skill (via the Skill
# tool). The script only records the fact — it does not invoke skills itself.
#
# Usage:
#   superpowers-invoke.sh <plan.md> <skill-name>
#
# Example:
#   superpowers-invoke.sh "$RUN_DIR/plan.md" brainstorming

set -uo pipefail

PLAN="$1"
SKILL_NAME="$2"

[ -f "$PLAN" ] || { echo "superpowers-invoke.sh: missing $PLAN" >&2; exit 2; }

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TMP=$(mktemp)

awk -v skill="$SKILL_NAME" -v ts="$TS" '
  /^## Superpowers invoked/ { in_section = 1; print; next }
  /^## / && in_section { in_section = 0 }
  in_section && $0 ~ ("\\[ \\] " skill " ") {
    sub(/\[ \]/, "[x]")
    sub(/— <when>/, "— " ts)
    sub(/—.*$/, "— " ts)
    print; next
  }
  { print }
' "$PLAN" > "$TMP"

mv "$TMP" "$PLAN"
echo "superpowers-invoke: marked ${SKILL_NAME} as invoked at ${TS}" >&2
