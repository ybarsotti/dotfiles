#!/usr/bin/env bash
# unfinished-run-gate.sh — a Stop hook that refuses to let a deep-execute run end
# without its report.
#
# Why a hook and not a script the agent calls. Phase 5 is the only phase with no gate, and
# across three real runs the report was never built once. finish-run.sh checks for it, but the
# agent has to remember to call finish-run.sh — and forgetting the last step IS the failure.
# A Stop hook fires from the harness whether or not anyone remembered.
#
# Exit 0 lets the session stop. Exit 2 blocks it and feeds stderr back to the agent.
#
# THE ESCAPE HATCH IS NOT OPTIONAL. A blocking hook that misdiagnoses traps a session with no
# way out but editing settings.json mid-irritation, which is worse than a missing report. There
# are two, and both leave a trace:
#   1. Saying "encerrar mesmo assim" anywhere in the session.
#   2. One block per run. After that the run is marked and never blocks again.
set -uo pipefail

RUNS_DIR="${DEEP_EXECUTE_RUNS_DIR:-$HOME/.claude/deep-execute-runs}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/deep-execute"
LOG="${STATE_DIR}/stop-gate.log"
ESCAPE="encerrar mesmo assim"

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0
[ -d "$RUNS_DIR" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# The hook payload arrives on stdin. `stop_hook_active` is set when this hook already blocked
# and the agent is coming back around; honouring it is what stops an infinite block/resume loop.
PAYLOAD=$(cat 2>/dev/null || true)
if [ -n "$PAYLOAD" ] && jq -e '.stop_hook_active == true' >/dev/null 2>&1 <<<"$PAYLOAD"; then
  exit 0
fi

TRANSCRIPT=$(jq -r '.transcript_path // empty' <<<"${PAYLOAD:-{\}}" 2>/dev/null || true)
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && grep -qiF "$ESCAPE" "$TRANSCRIPT"; then
  printf '%s escape phrase used\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$LOG"
  exit 0
fi

# A run counts as unfinished when it has a manifest, no rendered report, and saw activity in the
# last day. The age bound matters: an abandoned run from last month must not block every session
# from now on.
for dir in "$RUNS_DIR"/*/; do
  [ -d "$dir" ] || continue
  [ -f "${dir}manifest.json" ] || continue
  [ -f "${dir}report/index.html" ] && continue

  RUN_ID=$(basename "$dir")
  MARK="${STATE_DIR}/blocked-${RUN_ID}"
  [ -f "$MARK" ] && continue

  EVENTS="${dir}events.jsonl"
  [ -f "$EVENTS" ] || continue
  # `find -mtime -1` rather than parsing timestamps: the file's own mtime is the activity.
  [ -n "$(find "$EVENTS" -mtime -1 2>/dev/null)" ] || continue

  : >"$MARK"
  printf '%s blocked once for %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RUN_ID" >>"$LOG"
  cat >&2 <<EOF
Run ${RUN_ID} has no report at ${dir}report/index.html.

Phase 5 is not done. Build it and close the run:
  build-run-report.sh ${dir%/} --final-sha <sha> [--review ...] [--qa ...] [--pr ...]
  finish-run.sh ${dir%/} [--qa PATH]

If the run genuinely does not need one — it was abandoned, or you are not in it — say
"${ESCAPE}" and this will stand aside. This blocks once per run either way.
EOF
  exit 2
done

exit 0
