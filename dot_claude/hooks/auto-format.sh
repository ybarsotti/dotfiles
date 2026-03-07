#!/usr/bin/env bash
set -euo pipefail

json=$(cat)
file=$(echo "$json" | /opt/homebrew/bin/jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

[ -z "$file" ] || [ ! -f "$file" ] && exit 0

ext="${file##*.}"

case "$ext" in
  ts|tsx|js|jsx|mjs|cjs|json|css|scss|html)
    if command -v prettier &>/dev/null; then prettier --write "$file" --log-level silent; fi
    ;;
  py)
    if command -v ruff &>/dev/null; then
      ruff format "$file" --quiet
    elif command -v black &>/dev/null; then
      black "$file" --quiet
    fi
    ;;
  go)
    if command -v gofmt &>/dev/null; then gofmt -w "$file"; fi
    ;;
  rs)
    if command -v rustfmt &>/dev/null; then rustfmt "$file" --quiet 2>/dev/null; fi
    ;;
  rb)
    if command -v rubocop &>/dev/null; then rubocop --autocorrect "$file" --no-color 2>/dev/null; fi
    ;;
esac

exit 0
