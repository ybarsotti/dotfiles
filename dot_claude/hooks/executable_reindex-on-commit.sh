#!/usr/bin/env bash
# Auto re-index code intelligence graphs after `git commit` / `git merge`.
# Reads PostToolUse Bash payload from stdin. Skips silently if not a commit/merge,
# or if the project does not have an existing graph (gitnexus/graphify).
set -euo pipefail

JQ="/opt/homebrew/bin/jq"
[ -x "$JQ" ] || JQ="$(command -v jq || true)"
[ -z "$JQ" ] && exit 0

json=$(cat)
cmd=$("$JQ" -r '.tool_input.command // ""' 2>/dev/null <<<"$json" || echo "")
cwd=$("$JQ" -r '.cwd // ""' 2>/dev/null <<<"$json" || echo "")
[ -z "$cwd" ] && cwd="$PWD"

case "$cmd" in
    *"git commit"*|*"git merge"*) ;;
    *) exit 0 ;;
esac

cd "$cwd" 2>/dev/null || exit 0
repo_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
cd "$repo_root" 2>/dev/null || exit 0

log_dir="/tmp/claude-codeintel-$(date +%Y%m%d)"
mkdir -p "$log_dir"
ts=$(date '+%H:%M:%S')

if [ -d .gitnexus ] && command -v npx &>/dev/null; then
    embeddings_flag=""
    if [ -f .gitnexus/meta.json ] && grep -q '"embeddings"[[:space:]]*:[[:space:]]*[1-9]' .gitnexus/meta.json 2>/dev/null; then
        embeddings_flag="--embeddings"
    fi
    nohup npx gitnexus analyze $embeddings_flag >"$log_dir/gitnexus-$ts.log" 2>&1 &
    disown
fi

if [ -f graphify-out/graph.json ] && command -v graphify &>/dev/null; then
    nohup graphify . --update >"$log_dir/graphify-$ts.log" 2>&1 &
    disown
fi

exit 0
