#!/usr/bin/env bash
set -euo pipefail

json=$(cat)
message=$(echo "$json" | /opt/homebrew/bin/jq -r '.message // ""' 2>/dev/null || echo "")

echo "$(date '+%Y-%m-%d %H:%M') | $(pwd) | ${message:0:120}" >> ~/.claude/session.log
