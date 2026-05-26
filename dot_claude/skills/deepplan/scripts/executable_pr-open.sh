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
        | cut -c1-65)
[ -z "$TITLE" ] && TITLE=$(head -1 "$PLAN" | sed 's/^#\+ //' | cut -c1-65)

# Infer conventional-commit type from changed paths and recent commits.
CHANGED=$(git diff --name-only main...HEAD 2>/dev/null || git diff --name-only HEAD~5..HEAD 2>/dev/null)
RECENT_COMMITS=$(git log --pretty=%s main..HEAD 2>/dev/null || git log -5 --pretty=%s)
infer_type() {
  if   echo "$RECENT_COMMITS" | grep -qiE '^fix(\(|:)';      then echo "fix"
  elif echo "$RECENT_COMMITS" | grep -qiE '^feat(\(|:)';     then echo "feat"
  elif echo "$RECENT_COMMITS" | grep -qiE '^refactor(\(|:)'; then echo "refactor"
  elif echo "$RECENT_COMMITS" | grep -qiE '^docs(\(|:)';     then echo "docs"
  elif echo "$RECENT_COMMITS" | grep -qiE '^chore(\(|:)';    then echo "chore"
  elif echo "$CHANGED" | grep -qE '\.(md|txt|rst)$';         then echo "docs"
  elif echo "$CHANGED" | grep -qiE '(test|spec)';            then echo "test"
  else echo "feat"
  fi
}
PR_TYPE=$(infer_type)
case "$TITLE" in
  feat:*|fix:*|refactor:*|docs:*|chore:*|test:*) ;;  # already prefixed
  *) TITLE="${PR_TYPE}: ${TITLE}" ;;
esac

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

# Compute auto-reviewers from CODEOWNERS for the changed paths.
REVIEWER_FLAGS=()
CODEOWNERS=""
for cand in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
  [ -f "$cand" ] && { CODEOWNERS="$cand"; break; }
done
if [ -n "$CODEOWNERS" ] && [ -n "$CHANGED" ]; then
  OWNERS=$(
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      # First matching glob wins; CODEOWNERS resolves last-match-wins so
      # iterate in reverse for that semantic.
      tac "$CODEOWNERS" 2>/dev/null | awk -v path="$f" '
        /^[[:space:]]*#/ || NF < 2 {next}
        {
          pat=$1; for (i=2; i<=NF; i++) { print $i; }
          exit
        }
      '
    done <<< "$CHANGED" | sort -u | grep -oE '@[A-Za-z0-9_/-]+' | sed 's/^@//'
  )
  for o in $OWNERS; do
    REVIEWER_FLAGS+=("--reviewer" "$o")
  done
fi

# Open the PR (always as draft when --draft was passed; otherwise ready).
LABEL_FLAGS=("--label" "$PR_TYPE")
URL=$(gh pr create $DRAFT_FLAG --title "$TITLE" --body-file "$BODY" \
        "${LABEL_FLAGS[@]}" "${REVIEWER_FLAGS[@]+"${REVIEWER_FLAGS[@]}"}" 2>&1) || {
  # Retry without labels/reviewers if the repo lacks them (gh errors hard).
  echo "pr-open.sh: retrying without labels/reviewers (likely missing on remote)" >&2
  URL=$(gh pr create $DRAFT_FLAG --title "$TITLE" --body-file "$BODY" 2>&1) || {
    echo "pr-open.sh: gh pr create failed:" >&2
    echo "$URL" >&2
    exit 1
  }
}

echo "$URL" | grep -oE 'https://github.com/[^ ]+' | head -1
