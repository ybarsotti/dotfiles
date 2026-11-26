#!/usr/bin/env bash
# Tests for orca-spawn-guard.sh. Run: bash test-orca-spawn-guard.sh
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
hook="$here/orca-spawn-guard.sh"; [ -f "$hook" ] || hook="$here/executable_orca-spawn-guard.sh"
pass=0; fail=0
check() { # name, expected (deny|allow), env value, payload
  local out got
  out="$(ORCA_WORKTREE_ID="$3" bash "$hook" <<<"$4")"
  if grep -q '"deny"' <<<"$out"; then got=deny; else got=allow; fi
  if [ "$got" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (got $got)"; fi
}
bash_payload() { jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
agent_payload() { jq -nc --arg t "$1" '{tool_name:"Agent",tool_input:{subagent_type:$t,prompt:"x"}}'; }

check "codex exec in Orca" deny w1 "$(bash_payload 'codex exec -m gpt-6.1-terra "fix it"')"
check "env-wrapped codex exec" deny w1 "$(bash_payload 'cd /x && env -u T codex exec -C /x "$(cat b.md)" < /dev/null')"
check "claude -p in Orca" deny w1 "$(bash_payload 'echo hi | claude -p --model haiku')"
check "gtimeout wrapper" deny w1 "$(bash_payload 'gtimeout 1800 codex exec --model x "y"')"
check "grep for the words" allow w1 "$(bash_payload 'grep -rn "codex exec" docs/')"
check "orca worker command" allow w1 "$(bash_payload 'orca terminal create --worktree id:1 --command "codex exec y" --json')"
check "claude --agent without -p" allow w1 "$(bash_payload 'claude --agent fixer')"
check "escape hatch" allow w1 "$(bash_payload 'ORCA_SPAWN_OK=1 codex exec "y"')"
check "plain ls" allow w1 "$(bash_payload 'ls -la')"
check "outside Orca" allow "" "$(bash_payload 'codex exec "y"')"
check "Agent implementer" deny w1 "$(agent_payload implementer-backend)"
check "Agent Explore" allow w1 "$(agent_payload Explore)"
check "Agent ux-writer" allow w1 "$(agent_payload ux-writer)"
check "Agent implementer outside Orca" allow "" "$(agent_payload implementer-backend)"
check "Codex shell payload" deny w1 '{"tool_name":"Bash","turn_id":"t","tool_input":{"command":"codex exec \"y\""}}'
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
