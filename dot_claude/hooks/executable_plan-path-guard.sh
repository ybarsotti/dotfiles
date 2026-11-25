#!/usr/bin/env bash
# PreToolUse hook for Write and Edit. A plan reaches docs/superpowers/plans/ only after its
# planning run passed the Plannotator gate. Before that, the plan lives in the run folder.
#
# A session once closed its /simple-plan run, got a new request in the same chat, and wrote
# the plan straight into the project. No plan review and no gate ran. This hook refuses that.
#
# The write passes in two cases:
#   1. The step file of this session (the last `[workflow-gate] tracking` line) has its `gate`
#      step done or still to do. /simple-plan drafts the plan in docs/ before its gate. A closed
#      run marks the gate skipped, so a new plan after `close` is refused.
#   2. The step file that the plan names in its `**Step file:**` line has its `gate` step done,
#      for a later session that edits an approved plan (deep-execute deviations, PR fixes).
# publish-plan.sh copies the approved plan with Bash, so this hook does not see it.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
payload="$(cat)"
path="$(jq -r '.tool_input.file_path // ""' <<<"$payload")"
case "$path" in */docs/superpowers/plans/*.md) ;; *) exit 0 ;; esac

# gate_in <step file> <marks>: the gate row of a trusted step file has one of the marks.
gate_in() {
  local f="$1"
  [ -n "$f" ] && [ -f "$f" ] || return 1
  case "$f" in "$HOME/.claude/"*-runs/*) ;; *) return 1 ;; esac
  grep -qE "^- \[[$2]\] gate \|" "$f"
}

transcript="$(jq -r '.transcript_path // ""' <<<"$payload")"
session_file=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  session_file="$(grep -o -- '\[workflow-gate\] tracking [^"\\ ]*' "$transcript" | tail -1 | cut -d' ' -f3-)"
fi
gate_in "$session_file" "x ~!" && exit 0

if [ -f "$path" ]; then
  # shellcheck disable=SC2016  # the backticks are Markdown in the plan header
  plan_file="$(grep -m1 -oE '\*\*Step file:\*\* *`?[^` ]+' "$path" | sed -E 's/.*\*\* *`?//')"
  plan_file="${plan_file/#\~/$HOME}"
  gate_in "$plan_file" "x" && exit 0
fi

reason="A plan goes into docs/superpowers/plans/ only after its Plannotator gate. Run /simple-plan (or /deep-plan) for this change, so the plan review and the Plannotator gate run. When the step file of this session was closed and the user asks for a new change, run 'workflow.sh reopen <file> \"<reason>\"' and start the skill again at its first open step."
jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
