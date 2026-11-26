#!/usr/bin/env bash
# PreToolUse hook for the Agent tool and for Bash, in Claude Code and Codex. Inside Orca, an
# agent that builds, fixes, tests or reviews runs as a visible Orca worker
# (~/.claude/skills/_shared/orca-workers.md). This hook refuses the hidden ways to start one:
#   - the Agent tool with a build, fix, QA or design agent;
#   - a `codex exec` or `claude -p` that the agent types in Bash.
# A background `codex exec` once waited 19 minutes on stdin, and nobody could see it.
#
# Outside Orca (no ORCA_WORKTREE_ID), the hook allows everything. Scripts that run `claude -p`
# inside them (for example dispatch-planners.sh) are not affected: the hook sees only the
# typed command. Text in quotes is ignored, so `grep "codex exec"` passes.
# To allow one call on purpose, put ORCA_SPAWN_OK=1 in the command.
set -uo pipefail

[ -n "${ORCA_WORKTREE_ID:-}" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
tool="$(jq -r '.tool_name // ""' <<<"$input")"

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

case "$tool" in
  Agent | Task)
    type="$(jq -r '.tool_input.subagent_type // ""' <<<"$input")"
    case "$type" in
      implementer-backend | implementer-frontend | fixer | qa-business | qa-ui | ui-designer | plan-reviewer)
        deny "This session runs in Orca. Start '$type' as an Orca worker, as ~/.claude/skills/_shared/orca-workers.md describes, so the user can watch it. The Agent tool is for read-only research here."
        ;;
    esac
    ;;
  Bash | shell | exec_command)
    cmd="$(jq -r '.tool_input.command // (.tool_input.cmd // "") | if type == "array" then join(" ") else . end' <<<"$input")"
    case "$cmd" in *ORCA_SPAWN_OK=1*) exit 0 ;; esac
    # Drop quoted text, so a search for the words or an `orca ... --command "..."` passes.
    bare="$(sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" <<<"$cmd")"
    if grep -qE '(^|[[:space:];&|(`])(codex[[:space:]]+exec|claude[[:space:]]+(-p|--print))([[:space:]]|$)' <<<"$bare"; then
      deny "This session runs in Orca. Do not start a hidden 'codex exec' or 'claude -p'. Start an Orca worker (orca terminal create --command \"codex ...\" or \"claude --agent <name>\", then orca orchestration worker-start), as ~/.claude/skills/_shared/orca-workers.md describes. When the user asked for this exact command, add ORCA_SPAWN_OK=1 to it."
    fi
    ;;
esac
exit 0
