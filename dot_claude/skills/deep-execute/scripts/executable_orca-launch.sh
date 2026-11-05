#!/usr/bin/env bash
# orca-launch.sh — launch every lane worker as an Orca terminal.
#
# Usage:
#   orca-launch.sh WAVE_DIR CWD SPEC...
#
# The interface is the one wave-launch.sh has, so init-run.sh, prepare-run.sh and the
# manifest stay as they are. WAVE_DIR is only the name of the launch directory that
# prepare-run.sh scaffolds; nothing here needs Wave.
#
# Each lane runs worker-loop.sh in its own Orca terminal in the run's workspace. The
# wake is still the file `lanes/<lane>/reply.md`, which reply.sh writes. The terminal
# handle (`term_...`) goes into the lane's `block_ref`, which reply.sh uses for its
# liveness check.
#
# CWD must be inside an Orca workspace. `orca worktree current` says whether it is.
#
# Every lane is attempted even after one fails, and the exit code is 1 if any lane
# failed to launch.
set -uo pipefail

if [ $# -lt 3 ]; then
	echo "orca-launch.sh: usage: orca-launch.sh WAVE_DIR CWD SPEC..." >&2
	exit 2
fi

WAVE_DIR="$1"
CWD="$2"
shift 2

MANIFEST="${WAVE_DIR}/manifest.json"
[ -f "$MANIFEST" ] || {
	echo "orca-launch.sh: missing ${MANIFEST} — run prepare-run.sh first" >&2
	exit 2
}
[ -d "$CWD" ] || {
	echo "orca-launch.sh: CWD is not a directory: ${CWD}" >&2
	exit 2
}
command -v jq >/dev/null 2>&1 || {
	echo "orca-launch.sh: jq required" >&2
	exit 2
}
command -v orca >/dev/null 2>&1 || {
	echo "orca-launch.sh: orca not found — open Orca, or use wave-launch.sh inside Wave" >&2
	exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKER_LOOP="${SCRIPT_DIR}/worker-loop.sh"
[ -f "$WORKER_LOOP" ] || WORKER_LOOP="${SCRIPT_DIR}/executable_worker-loop.sh"
[ -f "$WORKER_LOOP" ] || {
	echo "orca-launch.sh: cannot find worker-loop.sh next to this script" >&2
	exit 2
}

new_uuid() {
	if command -v uuidgen >/dev/null 2>&1; then
		uuidgen | tr '[:upper:]' '[:lower:]'
	else
		cat /proc/sys/kernel/random/uuid
	fi
}

FAILED=0
for spec in "$@"; do
	LANE="${spec%%:*}"
	REST="${spec#*:}"
	if [ "$REST" = "$spec" ]; then
		RUNNER="claude"
		MODEL="sonnet"
	else
		RUNNER="${REST%%:*}"
		MODEL="${REST#*:}"
		MODEL="${MODEL%%@*}"
		[ -n "$RUNNER" ] || RUNNER="claude"
		[ -n "$MODEL" ] || MODEL="sonnet"
	fi

	PROMPT_FILE=$(jq -r --arg n "$LANE" '.workers[]? | select(.name == $n) | .prompt_file // empty' "$MANIFEST")
	if [ -z "$PROMPT_FILE" ] || [ ! -f "$PROMPT_FILE" ]; then
		FAILED=1
		jq -n --arg lane "$LANE" --arg detail "no prompt_file for lane in ${MANIFEST}" \
			'{lane: $lane, launched: false, detail: $detail}'
		continue
	fi

	SESSION_ID=$(new_uuid)
	# Orca types --command into a login shell, so quote every argument for that shell.
	COMMAND=$(printf '%q ' "$WORKER_LOOP" "$(dirname "$WAVE_DIR")" "$LANE" "$SESSION_ID" "$RUNNER" "$MODEL" "$PROMPT_FILE")

	if OUT=$(orca terminal create --worktree "path:${CWD}" --title "Lane · ${LANE}" --command "$COMMAND" --json 2>&1) &&
		HANDLE=$(printf '%s' "$OUT" | jq -r '[.. | .handle? // empty | strings] | first // empty') &&
		[ -n "$HANDLE" ]; then
		TMP=$(mktemp)
		jq --arg n "$LANE" --arg b "$HANDLE" --arg s "$SESSION_ID" \
			'.workers = [.workers[]? | if .name == $n then .block_ref = $b | .session_id = $s | .status = "running" else . end]' \
			"$MANIFEST" >"$TMP" && mv "$TMP" "$MANIFEST"
		jq -n --arg lane "$LANE" --arg block "$HANDLE" --arg session "$SESSION_ID" \
			'{lane: $lane, launched: true, block_ref: $block, session_id: $session}'
	else
		FAILED=1
		jq -n --arg lane "$LANE" --arg detail "orca terminal create failed: ${OUT:-no output}" \
			'{lane: $lane, launched: false, detail: $detail}'
	fi
done

if [ "$FAILED" -eq 1 ]; then
	echo "orca-launch.sh: at least one lane failed to launch — see the 'launched:false' line(s) above" >&2
	exit 1
fi
exit 0
