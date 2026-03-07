#!/usr/bin/env bash
set -euo pipefail

json=$(cat)
file=$(echo "$json" | /opt/homebrew/bin/jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

[ -z "$file" ] && exit 0

echo "$(date '+%H:%M') $file" >> "/tmp/claude-edits-$(date +%Y%m%d).log"
