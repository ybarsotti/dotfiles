#!/usr/bin/env bash
# PreToolUse hook for the Agent tool and for Bash (`orca orchestration worker-start`). It refuses `model: "opus"` for an agent that does not
# plan, design or review an architecture. Code, fixes, QA, exploration and data reads run on
# the default subagent model (Sonnet). An Opus subagent costs several times more, and a week of
# usage showed Opus explorers, rebases and validators as the largest share of tokens.
set -euo pipefail

input="$(cat)"
if [ "$(jq -r '.tool_name // ""' <<<"$input")" = "Bash" ]; then
  cmd="$(jq -r '.tool_input.command // ""' <<<"$input")"
  grep -q 'worker-start' <<<"$cmd" || exit 0
  grep -qE -- '--model[ =]opus' <<<"$cmd" || exit 0
  model="opus"; type="orca-worker"; desc="$(grep -oE -- '--spec .{0,160}' <<<"$cmd" | cut -c8- || true)"
else
  model="$(jq -r '.tool_input.model // ""' <<<"$input")"
  type="$(jq -r '.tool_input.subagent_type // "general-purpose"' <<<"$input")"
  desc="$(jq -r '.tool_input.description // ""' <<<"$input")"
fi
[ "$model" = "opus" ] || exit 0

case "$type" in
  Plan | plan-reviewer | architecture-critic | ui-designer | fork) exit 0 ;;
esac
if grep -qiE '\b(plan|design|architect|brainstorm)' <<<"$desc"; then
  exit 0
fi

reason="Opus is only for agents that write or review a plan, a design or an architecture. Start it again without the model parameter (Agent) or with --model sonnet (Orca worker). For a build, fix, QA or review, use the named agent (implementer-backend, implementer-frontend, fixer, qa-ui, qa-business)."
jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
