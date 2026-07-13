#!/usr/bin/env bash
# bootstrap-codeintel.sh — refresh local code intelligence indexes before
# planning/coding. Idempotent; safe to run multiple times.
#
# Usage:
#   bootstrap-codeintel.sh <run-dir>
#
# Side effects:
#   - gitnexus analyze  (if .gitnexus/ already initialized for this repo)
#   - graphify update . (if graphify-out/graph.json already exists)
#   - serena activation is NOT done here — the orchestrator MUST call
#     mcp__plugin_serena_serena__activate_project itself (script can't issue
#     MCP tool calls). The skill prompt instructs the orchestrator to do so.
#
# Writes a status marker file: <run-dir>/codeintel-status.json
# Exit always 0 (failures degrade gracefully).

set -uo pipefail

RUN_DIR="$1"
mkdir -p "$RUN_DIR"
MARKER="${RUN_DIR}/codeintel-status.json"

GITNEXUS_STATUS="absent"
GRAPHIFY_STATUS="absent"
SERENA_HINT="orchestrator: call mcp__plugin_serena_serena__activate_project with the current repo path"

# ─── GitNexus ──────────────────────────────────────────────────────────────

if command -v gitnexus >/dev/null 2>&1 && [ -d .git ]; then
  # GitNexus keeps the index outside the repo (in ~/.gitnexus). Use `gitnexus
  # status` for detection: prints "Repository not indexed" + exits non-zero
  # when this repo is unknown.
  if gitnexus status >/tmp/codeintel-gn-status-$$.log 2>&1; then
    echo "bootstrap-codeintel: running gitnexus analyze..." >&2
    if gitnexus analyze >/tmp/codeintel-gitnexus-$$.log 2>&1; then
      GITNEXUS_STATUS="fresh"
    else
      GITNEXUS_STATUS="stale"
      echo "bootstrap-codeintel: gitnexus analyze failed; see /tmp/codeintel-gitnexus-$$.log" >&2
    fi
  else
    GITNEXUS_STATUS="not-indexed (run: gitnexus analyze)"
  fi
fi

# ─── Graphify ──────────────────────────────────────────────────────────────

if command -v graphify >/dev/null 2>&1 && [ -f graphify-out/graph.json ]; then
  echo "bootstrap-codeintel: running graphify update ." >&2
  if graphify update . >/tmp/codeintel-graphify-$$.log 2>&1; then
    GRAPHIFY_STATUS="fresh"
  else
    GRAPHIFY_STATUS="stale"
    echo "bootstrap-codeintel: graphify update failed; see /tmp/codeintel-graphify-$$.log" >&2
  fi
elif command -v graphify >/dev/null 2>&1; then
  GRAPHIFY_STATUS="absent (build with: graphify <input>)"
fi

# ─── Marker ────────────────────────────────────────────────────────────────

jq -n \
  --arg g  "$GITNEXUS_STATUS" \
  --arg gr "$GRAPHIFY_STATUS" \
  --arg s  "$SERENA_HINT" \
  '{gitnexus: $g, graphify: $gr, serena: $s, timestamp: (now | todate)}' \
  > "$MARKER"

cat "$MARKER"
exit 0
