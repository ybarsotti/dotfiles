#!/usr/bin/env bash
set -euo pipefail

payload="$(cat || true)"
cwd="$(PAYLOAD="$payload" python3 - <<'PY' 2>/dev/null || true
import json, os

data = json.loads(os.environ.get("PAYLOAD") or "{}")
for key in ("cwd", "project_dir", "workspace_dir"):
    value = data.get(key)
    if isinstance(value, str) and value:
        print(value)
        raise SystemExit
workspace = data.get("workspace")
if isinstance(workspace, dict):
    for key in ("cwd", "current_dir", "root"):
        value = workspace.get(key)
        if isinstance(value, str) and value:
            print(value)
            raise SystemExit
PY
)"

if [ -z "${cwd:-}" ] || [ ! -d "$cwd" ]; then
  cwd="$PWD"
fi

parts=()

# Refresh a stale index in the background, at low priority. One refresh runs at a time on
# this machine, because an analyze of a large repo takes gigabytes of memory and many
# sessions start in parallel. A busy lock skips the refresh; the next session tries again.
LOCK="${XDG_CACHE_HOME:-$HOME/.cache}/codeintel-refresh.lock"
refresh_bg() {
  mkdir -p "$(dirname "$LOCK")"
  # A lock older than two hours belongs to a refresh that died.
  find "$LOCK" -maxdepth 0 -mmin +120 -exec rmdir {} \; 2>/dev/null || true
  mkdir "$LOCK" 2>/dev/null || return 0
  (cd "$cwd" && nohup nice -n 19 sh -c "$1" >/dev/null 2>&1; rmdir "$LOCK") </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
}
head="$(git -C "$cwd" rev-parse HEAD 2>/dev/null || true)"
if [ -n "$head" ] && [ -f "$cwd/.gitnexus/meta.json" ] && command -v gitnexus >/dev/null; then
  if [ "$(jq -r '.lastCommit // ""' "$cwd/.gitnexus/meta.json" 2>/dev/null)" != "$head" ]; then
    # --index-only: a plain analyze also rewrites CLAUDE.md, AGENTS.md and skill files in the repo.
    # GITNEXUS_MEMORY=off keeps the 4 GB heap: analyze otherwise sizes it from total RAM (36 GB
    # here) and a large repo then holds 5 GB or more. Two workers keep the refresh in the background.
    refresh_bg "GITNEXUS_MEMORY=off NODE_OPTIONS=--max-old-space-size=4096 gitnexus analyze --index-only --workers 2"
  fi
fi
# Only when git ignores graphify-out: an update of a committed graph dirties the worktree.
if [ -n "$head" ] && [ -f "$cwd/graphify-out/graph.json" ] && command -v graphify >/dev/null \
  && git -C "$cwd" check-ignore -q graphify-out/graph.json; then
  commit_time="$(git -C "$cwd" log -1 --format=%ct 2>/dev/null || echo 0)"
  if [ "$(stat -f %m "$cwd/graphify-out/graph.json")" -lt "$commit_time" ]; then
    refresh_bg "graphify update ."
  fi
fi

if [ -f "$cwd/.serena/project.yml" ]; then
  parts+=("serena: .serena/project.yml detected. Serena serves this working directory; use it for symbol-level exploration and edits.")
fi

if [ -d "$cwd/.gitnexus" ]; then
  repo_name="$(basename "$cwd")"
  if [ -f "$cwd/.gitnexus/meta.json" ]; then
    repo_name="$(python3 - "$cwd/.gitnexus/meta.json" "$repo_name" <<'PY' 2>/dev/null || true
import json, sys

fallback = sys.argv[2]
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    print(fallback)
    raise SystemExit
for key in ("repo", "repoName", "name", "project"):
    value = data.get(key)
    if isinstance(value, str) and value:
        print(value)
        raise SystemExit
print(fallback)
PY
)"
  fi
  parts+=("gitnexus: .gitnexus index detected for ${repo_name:-$(basename "$cwd")}. Use GitNexus MCP for architecture, flows, impact analysis before symbol edits, and detect_changes before commits. If stale, run gitnexus analyze --index-only.")
fi

graph_roots=()
if [ -f "$cwd/graphify-out/GRAPH_REPORT.md" ]; then
  graph_roots+=("graphify-out")
fi
if [ -f "$cwd/docs/graphify-out/GRAPH_REPORT.md" ]; then
  graph_roots+=("docs/graphify-out")
fi
if [ "${#graph_roots[@]}" -gt 0 ]; then
  joined="$(IFS=", "; echo "${graph_roots[*]}")"
  parts+=("graphify: graph reports detected at ${joined}. Read GRAPH_REPORT.md before broad architecture/codebase questions; prefer graphify query/path/explain for cross-module or code-plus-docs questions.")
fi

if [ "${#parts[@]}" -eq 0 ]; then
  exit 0
fi

context="$(printf '%s\n' "${parts[@]}")"
CONTEXT="$context" python3 - <<'PY'
import json, os

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": os.environ["CONTEXT"],
    }
}))
PY
