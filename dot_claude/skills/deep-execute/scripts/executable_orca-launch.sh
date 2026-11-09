#!/usr/bin/env bash
# orca-launch.sh — starts the worker loop of each lane in its own Orca terminal.
#
# Usage:
#   orca-launch.sh RUN_DIR [LANE...]
#
# With no LANE, every lane of RUN_DIR/launch/manifest.json starts. Name lanes
# to relaunch only those, for example after a crash: worker-loop.sh resumes the
# lane's pinned session and delivers the replies that waited on disk.
#
# The runner, model, effort and session id come from the launch manifest that
# init-run.sh wrote, so a relaunch uses the same agent and the same session.
# The terminal opens in the run's worktree (manifest.json's `cwd`), which must
# be inside an Orca workspace (`orca worktree current`). The terminal handle
# goes into the lane's `block_ref`, for a human who wants to watch the lane.
# Liveness does not depend on it: the loop's own pid file is the signal.
#
# Without Orca, start each loop in any terminal, or headless:
#   nohup worker-loop.sh RUN_DIR LANE >/dev/null 2>&1 &
#
# Every lane is attempted even after one fails; the exit is 1 if any lane did
# not launch.
set -uo pipefail

if [ $# -lt 1 ]; then
	echo "orca-launch.sh: usage: orca-launch.sh RUN_DIR [LANE...]" >&2
	exit 2
fi
RUN_DIR="$(cd "$1" 2>/dev/null && pwd)" || {
	echo "orca-launch.sh: no such run directory: $1" >&2
	exit 2
}
shift

LAUNCH="${RUN_DIR}/launch/manifest.json"
[ -f "$LAUNCH" ] || {
	echo "orca-launch.sh: missing ${LAUNCH} — run init-run.sh first" >&2
	exit 2
}
command -v jq >/dev/null 2>&1 || {
	echo "orca-launch.sh: jq required" >&2
	exit 2
}
command -v orca >/dev/null 2>&1 || {
	echo "orca-launch.sh: orca not found — open Orca, or start worker-loop.sh by hand (see the header)" >&2
	exit 2
}
CWD=$(jq -r '.cwd' "${RUN_DIR}/manifest.json")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKER_LOOP="${SCRIPT_DIR}/worker-loop.sh"
[ -f "$WORKER_LOOP" ] || WORKER_LOOP="${SCRIPT_DIR}/executable_worker-loop.sh"

LANES=("$@")
if [ ${#LANES[@]} -eq 0 ]; then
	while IFS= read -r l; do
		[ -n "$l" ] && LANES+=("$l")
	done < <(jq -r '.workers[]?.name' "$LAUNCH")
fi

FAILED=0
for LANE in "${LANES[@]}"; do
	if ! jq -e --arg n "$LANE" 'any(.workers[]?; .name == $n)' "$LAUNCH" >/dev/null; then
		FAILED=1
		jq -n --arg lane "$LANE" --arg detail "no record for lane in ${LAUNCH}" '{lane: $lane, launched: false, detail: $detail}'
		continue
	fi
	# Orca types --command into a login shell, so quote every argument for that shell.
	COMMAND=$(printf '%q ' bash "$WORKER_LOOP" "$RUN_DIR" "$LANE")
	if OUT=$(orca terminal create --worktree "path:${CWD}" --title "Lane · ${LANE}" --command "$COMMAND" --json 2>&1) &&
		HANDLE=$(printf '%s' "$OUT" | jq -r '[.. | .handle? // empty | strings] | first // empty') &&
		[ -n "$HANDLE" ]; then
		TMP=$(mktemp "${RUN_DIR}/launch/.manifest.XXXXXX")
		jq --arg n "$LANE" --arg b "$HANDLE" \
			'.workers = [.workers[] | if .name == $n then .block_ref = $b else . end]' "$LAUNCH" >"$TMP" && mv "$TMP" "$LAUNCH"
		jq -n --arg lane "$LANE" --arg block "$HANDLE" '{lane: $lane, launched: true, block_ref: $block}'
	else
		FAILED=1
		jq -n --arg lane "$LANE" --arg detail "orca terminal create failed: ${OUT:-no output}" '{lane: $lane, launched: false, detail: $detail}'
	fi
done

if [ "$FAILED" -eq 1 ]; then
	echo "orca-launch.sh: at least one lane failed to launch — see the 'launched:false' line(s) above" >&2
	exit 1
fi
exit 0
