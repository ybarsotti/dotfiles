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

if [ -f "$cwd/.serena/project.yml" ]; then
  parts+=("serena: .serena/project.yml detected. Activate this project with the Serena MCP activate_project tool before symbol-level exploration or edits.")
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
  parts+=("gitnexus: .gitnexus index detected for ${repo_name:-$(basename "$cwd")}. Use GitNexus MCP for architecture, flows, impact analysis before symbol edits, and detect_changes before commits. If stale, run npx gitnexus analyze.")
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
