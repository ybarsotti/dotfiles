#!/usr/bin/env bash
# feature-branch.sh — create feat/<slug> branch from main if currently on main.
# No-op if already on a feature branch.
#
# Usage:
#   feature-branch.sh <task-description> [--ticket KEY-123]
#
# Prints the resulting branch name to stdout.

set -uo pipefail

TASK_DESC="$1"; shift
TICKET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ticket) TICKET="$2"; shift 2 ;;
    *) echo "feature-branch.sh: unknown flag '$1'" >&2; exit 1 ;;
  esac
done

command -v git >/dev/null 2>&1 || { echo "feature-branch.sh: git missing" >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "feature-branch.sh: not in a git repo" >&2; exit 1; }

CURRENT=$(git symbolic-ref --short HEAD 2>/dev/null || echo "DETACHED")

if [ "$CURRENT" != "main" ] && [ "$CURRENT" != "master" ]; then
  echo "feature-branch: already on $CURRENT (no-op)" >&2
  echo "$CURRENT"
  exit 0
fi

# Refuse to switch over uncommitted changes.
if [ -n "$(git status --porcelain)" ]; then
  echo "feature-branch.sh: uncommitted changes on $CURRENT; commit or stash first" >&2
  exit 2
fi

slug() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g' | cut -c1-50; }

if [ -n "$TICKET" ]; then
  NAME="feat/${TICKET}-$(slug "$TASK_DESC")"
else
  NAME="feat/$(slug "$TASK_DESC")"
fi

# Truncate to keep branch name reasonable.
NAME=$(echo "$NAME" | cut -c1-80 | sed 's/-$//')

git checkout -b "$NAME" >&2 || { echo "feature-branch.sh: checkout failed" >&2; exit 3; }
echo "$NAME"
