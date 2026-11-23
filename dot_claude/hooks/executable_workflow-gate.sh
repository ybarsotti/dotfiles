#!/usr/bin/env bash
# workflow-gate.sh — a Stop and SubagentStop hook that blocks the end of a turn while the
# workflow step file of this session still has an open step.
#
# Scope. The hook acts only on a session that ran `workflow.sh init`. That command prints
# "[workflow-gate] tracking <file>", and the hook looks for that line in the transcript of the
# session (or of the subagent). A session with no tracking line is never touched, so normal
# work outside a workflow is not affected.
#
# Exit 0 lets the turn end. Exit 2 blocks it and feeds stderr back to the agent.
#
# Ways out, so that a wrong block never traps a session:
#   1. A waiting or blocked step (`workflow.sh wait|block`) is a legitimate stop.
#   2. `stop_hook_active`: the hook blocks once per stop attempt, never in a loop.
#   3. The user says "encerrar mesmo assim" in the session.
#   4. A step file that has not changed for 2 days is ignored.
set -uo pipefail

WORKFLOW="${WORKFLOW_SH:-$HOME/.claude/skills/_shared/workflow.sh}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/workflow-gate"
LOG="$STATE_DIR/gate.log"
ESCAPE="encerrar mesmo assim"
# Only a step file inside a run folder is trusted. Any text in the transcript (a fetched page,
# a file the agent read) can contain a tracking line, so the path alone proves nothing.
TRUSTED_ROOT="${WORKFLOW_TRUSTED_ROOT:-$HOME/.claude}"

command -v jq >/dev/null 2>&1 || exit 0
[ -x "$WORKFLOW" ] || exit 0
mkdir -p "$STATE_DIR" 2>/dev/null || true

PAYLOAD=$(cat 2>/dev/null || true)
[ -n "$PAYLOAD" ] || exit 0
jq -e '.stop_hook_active == true' >/dev/null 2>&1 <<<"$PAYLOAD" && exit 0

# A subagent has its own transcript. Its tracking line is there, not in the parent.
TRANSCRIPT=$(jq -r '(.agent_transcript_path // "") as $a | if $a != "" then $a else (.transcript_path // "") end' <<<"$PAYLOAD")
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

FILE=$(grep -o -- '\[workflow-gate\] tracking [^"\\ ]*' "$TRANSCRIPT" | tail -1 | cut -d' ' -f3-)
[ -n "${FILE:-}" ] && [ -f "$FILE" ] || exit 0
case "$FILE" in
  *..*) exit 0 ;;
  "$TRUSTED_ROOT"/*-runs/*) ;;
  *) exit 0 ;;
esac
head -1 "$FILE" | grep -q '^# Workflow: ' || exit 0
[ -n "$(find "$FILE" -mtime -2 2>/dev/null)" ] || exit 0

# The escape phrase counts only in a message that the user typed, not in a hook message.
if jq -r 'select(.type == "user") | .message.content | select(type == "string")' "$TRANSCRIPT" 2>/dev/null \
  | grep -v -F '[workflow-gate]' | grep -qiF "$ESCAPE"; then
  printf '%s escape phrase used for %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$FILE" >>"$LOG"
  exit 0
fi

"$WORKFLOW" check "$FILE" >/dev/null 2>&1 && exit 0

printf '%s blocked %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$FILE" >>"$LOG"
{
  printf '[workflow-gate] %s has open steps.\n\n' "$FILE"
  "$WORKFLOW" status "$FILE"
  cat <<EOF

Do the next step now. When it is done, run:
  workflow.sh done "$FILE" <id> <evidence>
When a step does not apply, skip it with the reason. When you wait for a worker or for the
user, mark it with wait or block. The review step cannot be skipped after code was built.
If the user stopped the run, run: workflow.sh close "$FILE" "<reason>".
EOF
} >&2
exit 2
