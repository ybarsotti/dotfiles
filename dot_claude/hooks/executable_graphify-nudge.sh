#!/usr/bin/env bash
# PreToolUse(Bash): before the first search command of a session in a repo with a graphify
# graph, point the agent at GRAPH_REPORT.md. It prints once per session, not on every search.
set -uo pipefail

payload="$(cat)"
[ -f graphify-out/graph.json ] || exit 0
read -r session cmd < <(printf '%s' "$payload" | jq -r '[.session_id // "none", (.tool_input.command // "" | gsub("\\s+"; " "))] | @tsv' 2>/dev/null) || exit 0
case " $cmd" in
  *grep*|*" rg "*|*" find "*|*" fd "*|*" ack "*|*" ag "*) ;;
  *) exit 0 ;;
esac
mark="${TMPDIR:-/tmp}/graphify-nudge-${session//[^A-Za-z0-9_-]/}"
[ -e "$mark" ] && exit 0
: >"$mark"
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"graphify: Knowledge graph exists. Read graphify-out/GRAPH_REPORT.md for god nodes and community structure before searching raw files."}}'
