#!/usr/bin/env bash
# pr-open.sh — build PR body from plan, open PR via gh.
#
# Usage: pr-open.sh <run-dir> [--ticket KEY-123] [--draft]
#
# Reads:  <run-dir>/plan.md
# Writes: <run-dir>/pr-body.md
# Prints: PR URL on stdout

set -uo pipefail

RUN_DIR="$1"; shift
TICKET=""
DRAFT_FLAG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --ticket) TICKET="$2"; shift 2 ;;
    --draft)  DRAFT_FLAG="--draft"; shift ;;
    *) echo "pr-open.sh: unknown flag '$1'" >&2; exit 1 ;;
  esac
done

PLAN="${RUN_DIR}/plan.md"
BODY="${RUN_DIR}/pr-body.md"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${SKILL_DIR}/templates/pr-body.md"

[ -f "$PLAN" ]     || { echo "pr-open.sh: missing $PLAN" >&2; exit 1; }
[ -f "$TEMPLATE" ] || { echo "pr-open.sh: missing $TEMPLATE" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "pr-open.sh: gh CLI not installed" >&2; exit 1; }

# Title from plan's first goal bullet, trimmed to 70 chars.
TITLE=$(awk '/^## Goals/{flag=1; next} /^## /{flag=0} flag && /^- /{sub(/^- /, ""); print; exit}' "$PLAN" \
        | cut -c1-70)
[ -z "$TITLE" ] && TITLE=$(head -1 "$PLAN" | sed 's/^#\+ //' | cut -c1-70)

# Auto-detect ticket if not provided.
if [ -z "$TICKET" ]; then
  TICKET=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | grep -oE '[A-Z]{2,}-[0-9]+' | head -1 || true)
  if [ -z "$TICKET" ]; then
    TICKET=$(git log -1 --pretty=%B 2>/dev/null | grep -oE '[A-Z]{2,}-[0-9]+' | head -1 || true)
  fi
fi

# Extract sections.
CONTEXT=$(awk '/^## Context/{flag=1; next} /^## /{flag=0} flag' "$PLAN")
MERMAID=$(awk '/^## Flow diagram/{flag=1; next} /^## /{flag=0} flag' "$PLAN")
AFFECTED=$(awk '/^## Affected files/{flag=1; next} /^## /{flag=0} flag' "$PLAN")
TESTS=$(awk '/^## TDD test list/{flag=1; next} /^## /{flag=0} flag' "$PLAN")
EDGES=$(awk '/^## Edge cases/{flag=1; next} /^## /{flag=0} flag' "$PLAN")
START_HERE=$(echo "$AFFECTED" | head -1)

# Populate template.
sed \
  -e "s|{{TITLE}}|${TITLE}|g" \
  -e "s|{{TICKET}}|${TICKET:-(no ticket)}|g" \
  -e "s|{{START_HERE}}|${START_HERE:-the first file in Affected files}|g" \
  "$TEMPLATE" > "$BODY.tmp"

# Inject multiline sections (sed multiline replacement is fragile; use awk).
awk -v ctx="$CONTEXT" -v mer="$MERMAID" -v aff="$AFFECTED" -v tst="$TESTS" -v edg="$EDGES" '
{
  gsub(/\{\{CONTEXT\}\}/, ctx)
  gsub(/\{\{MERMAID\}\}/, mer)
  gsub(/\{\{AFFECTED\}\}/, aff)
  gsub(/\{\{TESTS\}\}/, tst)
  gsub(/\{\{EDGES\}\}/, edg)
  print
}' "$BODY.tmp" > "$BODY"
rm -f "$BODY.tmp"

# Open the PR.
URL=$(gh pr create $DRAFT_FLAG --title "$TITLE" --body-file "$BODY" 2>&1) || {
  echo "pr-open.sh: gh pr create failed:" >&2
  echo "$URL" >&2
  exit 1
}

echo "$URL" | grep -oE 'https://github.com/[^ ]+' | head -1
