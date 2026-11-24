#!/usr/bin/env bash
# PreToolUse hook for AskUserQuestion. After a plan is approved and the build chain runs, a
# question in the chat stops the run until the user answers. The user is often in another
# session, so the run waits. This hook refuses the first AskUserQuestion of each question in a
# running chain, and tells the agent to put the question in the Inbox and go on with the
# other steps (_shared/inbox.md).
#
# Scope: only a session whose step file (the `[workflow-gate] tracking` line) has its `goal`
# or `build` step started. Planning, grilling and normal chat are never touched.
# Way out: the same question asked a second time passes. The agent asks again only when no
# other step can go on, or when the Inbox is not available.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
payload="$(cat)"
transcript="$(jq -r '.transcript_path // ""' <<<"$payload")"
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

file="$(grep -o -- '\[workflow-gate\] tracking [^"\\ ]*' "$transcript" | tail -1 | cut -d' ' -f3-)"
[ -n "$file" ] && [ -f "$file" ] || exit 0
case "$file" in "$HOME/.claude/"*) ;; *) exit 0 ;; esac
grep -qE '^- \[[^ ]\] (goal|build) \|' "$file" || exit 0

state="${XDG_STATE_HOME:-$HOME/.local/state}/ask-after-approval"
mkdir -p "$state"
key="$(jq -c '[.session_id, (.tool_input.questions // [] | map(.question))]' <<<"$payload" | shasum | cut -c1-16)"
if [ -f "$state/$key" ]; then
  rm -f "$state/$key"
  exit 0
fi
touch "$state/$key"
find "$state" -type f -mtime +2 -delete 2>/dev/null || true

reason="The plan is approved and the chain runs, so a decision never stops it. Follow _shared/inbox.md, section Decisions during a build chain: take the decision with the least impact (today's rule first, then the docs, then the easiest to undo), record it in decisions.md with its alternatives, send it to the Inbox as 'Did I choose right?', and go on. Ask with AskUserQuestion again, with the same question, only when the Inbox is not available."
jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
