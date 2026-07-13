#!/usr/bin/env bash
# auto-format.sh — detect and run project-specific formatter, commit changes.
#
# Detection order (first match wins):
#   1. just format
#   2. pnpm format / npm run format / yarn format
#   3. make format
#   4. cargo fmt   (if Cargo.toml)
#   5. gofmt -w .  (if go.mod)
#   6. ruff format . (if pyproject.toml)
#
# Exits 0 always (formatter absence is non-fatal). Commits any changes as
# `chore: auto-format`.

set -uo pipefail

run_and_check() {
  local label="$1"; shift
  echo "auto-format: $label" >&2
  "$@" 2>&1 | tail -5 >&2 || return 1
}

DID=0

if command -v just >/dev/null 2>&1 && just --list 2>/dev/null | grep -qE '^\s+format\b'; then
  run_and_check "just format" just format && DID=1
elif [ -f package.json ]; then
  if jq -e '.scripts.format' package.json >/dev/null 2>&1; then
    if command -v pnpm >/dev/null 2>&1; then
      run_and_check "pnpm format" pnpm format && DID=1
    elif command -v yarn >/dev/null 2>&1; then
      run_and_check "yarn format" yarn format && DID=1
    else
      run_and_check "npm run format" npm run format && DID=1
    fi
  fi
elif [ -f Makefile ] && grep -qE '^format:' Makefile; then
  run_and_check "make format" make format && DID=1
elif [ -f Cargo.toml ] && command -v cargo >/dev/null 2>&1; then
  run_and_check "cargo fmt" cargo fmt && DID=1
elif [ -f go.mod ] && command -v gofmt >/dev/null 2>&1; then
  run_and_check "gofmt -w ." gofmt -w . && DID=1
elif [ -f pyproject.toml ] && command -v ruff >/dev/null 2>&1; then
  run_and_check "ruff format ." ruff format . && DID=1
else
  echo "auto-format: no formatter detected (skipping)" >&2
fi

if [ "$DID" -eq 1 ] && [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -m "chore: auto-format" >&2 || true
  echo "auto-format: committed formatting changes" >&2
else
  echo "auto-format: no changes" >&2
fi

exit 0
