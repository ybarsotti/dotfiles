#!/usr/bin/env bash
set -euo pipefail

json=$(cat)
file=$(echo "$json" | /opt/homebrew/bin/jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

[ -z "$file" ] || [ ! -f "$file" ] && exit 0

ext="${file##*.}"

case "$ext" in
  ts|tsx|js|jsx|mjs|cjs|json|css|scss|html)
    command -v prettier &>/dev/null && prettier --write "$file" --log-level silent || true
    ;;
  py)
    command -v ruff &>/dev/null && ruff format "$file" --quiet || \
    command -v black &>/dev/null && black "$file" --quiet || true
    ;;
  go)
    command -v gofmt &>/dev/null && gofmt -w "$file" || true
    ;;
  rs)
    command -v rustfmt &>/dev/null && rustfmt "$file" --quiet 2>/dev/null || true
    ;;
  rb)
    command -v rubocop &>/dev/null && rubocop --autocorrect "$file" --no-color 2>/dev/null || true
    ;;
esac

exit 0
