#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034,SC1010 # checks are eval strings; "done" is a workflow.sh verb
# Checks workflow.sh and the workflow-gate.sh Stop hook.
# Run from the chezmoi source: bash dot_claude/skills/_shared/tests/executable_test-workflow-gate.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_SHARED="$(cd "$HERE/.." && pwd)"
SRC_HOOKS="$(cd "$HERE/../../../hooks" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Lay the files out as chezmoi applies them, without the executable_ prefix.
mkdir -p "$TMP/shared"
cp "$SRC_SHARED/executable_workflow.sh" "$TMP/shared/workflow.sh"
cp -R "$SRC_SHARED/workflows" "$TMP/shared/workflows"
cp "$SRC_HOOKS/executable_workflow-gate.sh" "$TMP/gate.sh"
chmod +x "$TMP/shared/workflow.sh" "$TMP/gate.sh"
W="$TMP/shared/workflow.sh"
export WORKFLOW_SH="$W" XDG_STATE_HOME="$TMP/state" WORKFLOW_TRUSTED_ROOT="$TMP"

pass=0 fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); echo "ok: $1"; else fail=$((fail + 1)); echo "FAIL: $1"; fi; }

F="$TMP/test-runs/r1/chain.md"
OUT="$("$W" init "$F" simple-plan --project /p --plan /p/plan.md)"
ok "init prints the tracking line" '[[ "$OUT" == *"[workflow-gate] tracking $F"* ]]'
ok "init marks setup done" 'grep -q "^- \[x\] setup " "$F"'
ok "init includes the chain steps" 'grep -q "^- \[ \] review " "$F" && grep -q "^- \[ \] pr " "$F"'
ok "check fails while steps are open" '! "$W" check "$F" >/dev/null'

"$W" add "$F" build.1 "Task 1" --after build >/dev/null
"$W" add "$F" build.2 "Task 2" --after build >/dev/null
ok "add keeps the build rows in order after build" '[ "$(grep -o "^- \[ \] build[^ ]*" "$F" | cut -d" " -f4 | tr "\n" ,)" = "build,build.1,build.2," ]'

ok "done refuses a missing evidence path" '! "$W" done "$F" context /nope/missing 2>/dev/null'
"$W" done "$F" context "$F" >/dev/null
ok "done logs what is next" 'grep -q "done context: .*Next: pipeline" "$F"'
"$W" log "$F" "watch job abc" >/dev/null
ok "log adds a line to the Log" 'grep -q "watch job abc. Next:" "$F"'

"$W" add "$F" visual.home "qa-ui on home" --after build >/dev/null
ok "a visual step refuses a sentence as evidence" '! "$W" done "$F" visual.home "codex read the canvas files" 2>/dev/null'
mkdir -p "$TMP/shots"; ok "a visual step refuses a folder with no image" '! "$W" done "$F" visual.home "$TMP/shots" 2>/dev/null'
printf x > "$TMP/shots/home-1440.png"
ok "a visual step accepts a folder of screenshots" '"$W" done "$F" visual.home "$TMP/shots" >/dev/null'

ok "review can be skipped before any build" '"$W" skip "$F" review "plan only" >/dev/null'
"$W" todo "$F" review >/dev/null
"$W" done "$F" build.1 "pytest: 3 passed" >/dev/null
ok "review cannot be skipped after a build step is done" '! "$W" skip "$F" review "no time" 2>/dev/null'
ok "close refuses to skip review after a build" '! "$W" close "$F" "stop" 2>/dev/null'

G="$TMP/test-runs/r2/chain.md"; "$W" init "$G" simple-plan >/dev/null; "$W" close "$G" "plan only" >/dev/null
"$W" reopen "$G" "plan only" >/dev/null
ok "reopen opens again the steps that close skipped" 'grep -q "^- \[ \] build " "$G" && grep -q "^- \[ \] review " "$G" && grep -q "^- \[x\] setup " "$G"'

"$W" wait "$F" build.2 "worker w1" >/dev/null
ok "check passes while a step waits" '"$W" check "$F" >/dev/null'
"$W" todo "$F" build.2 >/dev/null

# The hook: a transcript that ran init is gated; one that did not is left alone.
T1="$TMP/t1.jsonl"; T2="$TMP/t2.jsonl"
jq -nc --arg o "[workflow-gate] tracking $F" '{type:"user",message:{content:[{type:"tool_result",content:$o}]}}' >"$T1"
jq -nc '{type:"user",message:{content:"hello"}}' >"$T2"
hook() { jq -nc --arg t "$1" --argjson a "${2:-false}" '{transcript_path:$t, stop_hook_active:$a}' | "$TMP/gate.sh" >/dev/null 2>&1; }
ok "hook blocks a tracked session with open steps" '! hook "$T1"'
ok "hook leaves an untracked session alone" 'hook "$T2"'
ok "hook honours stop_hook_active" 'hook "$T1" true'
SUB="$(jq -nc --arg t "$T2" --arg a "$T1" '{transcript_path:$t, agent_transcript_path:$a}')"
ok "hook reads the subagent transcript on SubagentStop" '! (printf "%s" "$SUB" | "$TMP/gate.sh" >/dev/null 2>&1)'

cp "$T1" "$TMP/t3.jsonl"
jq -nc '{type:"user",message:{content:"ok, encerrar mesmo assim"}}' >>"$TMP/t3.jsonl"
ok "hook stands aside after the escape phrase" 'hook "$TMP/t3.jsonl"'

# A tracking line that names a file outside a run folder is ignored.
mkdir -p "$TMP/elsewhere"; cp "$F" "$TMP/elsewhere/chain.md"
T4="$TMP/t4.jsonl"
jq -nc --arg o "[workflow-gate] tracking $TMP/elsewhere/chain.md" '{type:"user",message:{content:[{type:"tool_result",content:$o}]}}' >"$T4"
ok "hook ignores a step file outside a run folder" 'hook "$T4"'

"$W" close "$F" "test" 2>/dev/null || true
"$W" done "$F" review "/deep-review: 0 HIGH" >/dev/null
"$W" close "$F" "test" >/dev/null
ok "hook lets a finished workflow stop" 'hook "$T1"'

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
