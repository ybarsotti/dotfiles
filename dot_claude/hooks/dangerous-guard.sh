#!/usr/bin/env bash
set -euo pipefail

json=$(cat)
cmd=$(echo "$json" | /opt/homebrew/bin/jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

if echo "$cmd" | grep -qE '(rm\s+-rf|git\s+reset\s+--hard|git\s+push\s+--force|DROP\s+TABLE|TRUNCATE\s+TABLE|git\s+clean\s+-f)'; then
  echo "$(date '+%Y-%m-%d %H:%M') | BLOCKED | $(pwd) | $cmd" >> ~/.claude/audit.log

  dir=$(basename "$(pwd)")
  osascript -e "display notification \"$cmd\" with title \"Claude — Comando destrutivo\" subtitle \"$dir\" sound name \"Basso\"" 2>/dev/null || true
fi
