#!/usr/bin/env bash
# wave-launch.sh — launch every lane worker as a Wave Terminal block.
#
# Usage:
#   wave-launch.sh WAVE_DIR CWD SPEC...
#
# SPEC is the same grammar init-run.sh already emits: `name`, `name:runner:model`,
# or `name:runner:model@effort`. A bare name means claude:sonnet.
#
# WAVE_DIR is the directory prepare-run.sh already scaffolded: it holds
# system-prompt.txt, one worker-<lane>.prompt.md per lane, and manifest.json.
# That scaffolding is transport-agnostic — prepare-run.sh launches nothing — so it
# is reused as-is and only the transport differs here.
#
# What replaces cmux. cmux opened a pane per lane and typed into it with `cmux send`.
# Wave has no equivalent: `wsh run` launches a block and `wsh termscrollback` reads
# one, but nothing types into a live block. So each lane runs worker-loop.sh instead,
# which takes its first prompt as an argument and takes every later one from
# `lanes/<lane>/reply.md`. reply.sh writes that file; the file is the wake.
#
# Each lane gets its own session UUID. All lanes share one worktree, so resuming
# "the last session" would cross lanes; the UUID pins each lane's conversation.
#
# Writes `block_ref` and `session_id` back into manifest.json per lane, and prints one
# JSON line per lane. Every lane is attempted even after one fails, and the exit code
# is 1 if any lane failed to launch — a half-launched run must not read as success.
set -uo pipefail

if [ $# -lt 3 ]; then
	echo "wave-launch.sh: usage: wave-launch.sh WAVE_DIR CWD SPEC..." >&2
	exit 2
fi

WAVE_DIR="$1"
CWD="$2"
shift 2

MANIFEST="${WAVE_DIR}/manifest.json"
[ -f "$MANIFEST" ] || {
	echo "wave-launch.sh: missing ${MANIFEST} — run prepare-run.sh first" >&2
	exit 2
}
[ -d "$CWD" ] || {
	echo "wave-launch.sh: CWD is not a directory: ${CWD}" >&2
	exit 2
}
command -v jq >/dev/null 2>&1 || {
	echo "wave-launch.sh: jq required" >&2
	exit 2
}
command -v wsh >/dev/null 2>&1 || {
	echo "wave-launch.sh: wsh not found — this run is not inside Wave Terminal" >&2
	exit 2
}
[ -n "${WAVETERM_TABID:-}" ] && [ -n "${WAVETERM_BLOCKID:-}" ] || {
	echo "wave-launch.sh: run /deep-execute inside the Wave tab reserved for this task" >&2
	exit 2
}
wsh setmeta -b "${WAVETERM_BLOCKID}" "frame:title=Orchestrator" >/dev/null 2>&1 || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKER_LOOP="${SCRIPT_DIR}/worker-loop.sh"
[ -f "$WORKER_LOOP" ] || WORKER_LOOP="${SCRIPT_DIR}/executable_worker-loop.sh"
[ -f "$WORKER_LOOP" ] || {
	echo "wave-launch.sh: cannot find worker-loop.sh next to this script" >&2
	exit 2
}

# A UUID per lane. uuidgen exists on macOS and on the Linux images CI uses; the
# /proc fallback keeps this working where it does not.
new_uuid() {
	if command -v uuidgen >/dev/null 2>&1; then
		uuidgen | tr '[:upper:]' '[:lower:]'
	else
		cat /proc/sys/kernel/random/uuid
	fi
}

FAILED=0
TARGET_BLOCK="${WAVETERM_BLOCKID}"
SPLIT_RUN="${HOME}/.local/bin/wave-split-run"
LAYOUT_ACTION="right"
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

	# The block runs through `/bin/zsh -lc` for the same reason the Wave widgets do:
	# a block starts with no ~/.zprofile, so it has no /opt/homebrew/bin and would
	# find neither claude nor jq. Arguments are passed positionally rather than
	# interpolated into the command string, so a lane name never becomes shell syntax.
	# shellcheck disable=SC2016  # the single quotes are deliberate: zsh expands these, not us
	if [ -n "$TARGET_BLOCK" ] && [ -x "$SPLIT_RUN" ]; then
		BLOCK_OUT=$($SPLIT_RUN "$LAYOUT_ACTION" "$TARGET_BLOCK" "Lane · ${LANE}" "$CWD" /bin/zsh -lc \
			'exec "$1" "$2" "$3" "$4" "$5" "$6" "$7"' \
			"deep-execute:${LANE}" \
			"$WORKER_LOOP" "$(dirname "$WAVE_DIR")" "$LANE" "$SESSION_ID" "$RUNNER" "$MODEL" "$PROMPT_FILE" 2>&1) && LAUNCHED=1 || LAUNCHED=0
	else
		BLOCK_OUT=$(wsh run --cwd "$CWD" -- /bin/zsh -lc \
			'exec "$1" "$2" "$3" "$4" "$5" "$6" "$7"' \
			"deep-execute:${LANE}" \
			"$WORKER_LOOP" "$(dirname "$WAVE_DIR")" "$LANE" "$SESSION_ID" "$RUNNER" "$MODEL" "$PROMPT_FILE" 2>&1) && LAUNCHED=1 || LAUNCHED=0
	fi
	if [ "$LAUNCHED" -eq 1 ]; then
		BLOCK_REF=$(printf '%s' "$BLOCK_OUT" | grep -oE 'block:[0-9a-f-]+' | head -1)
		TMP=$(mktemp)
		jq --arg n "$LANE" --arg b "${BLOCK_REF:-}" --arg s "$SESSION_ID" \
			'.workers = [.workers[]? | if .name == $n then .block_ref = $b | .session_id = $s | .status = "running" else . end]' \
			"$MANIFEST" >"$TMP" && mv "$TMP" "$MANIFEST"
		jq -n --arg lane "$LANE" --arg block "${BLOCK_REF:-unknown}" --arg session "$SESSION_ID" \
			'{lane: $lane, launched: true, block_ref: $block, session_id: $session}'
		TARGET_BLOCK="${BLOCK_REF:-$TARGET_BLOCK}"
		LAYOUT_ACTION="down"
	else
		FAILED=1
		jq -n --arg lane "$LANE" --arg detail "wsh run failed: ${BLOCK_OUT}" \
			'{lane: $lane, launched: false, detail: $detail}'
	fi
done

if [ "$FAILED" -eq 1 ]; then
	echo "wave-launch.sh: at least one lane failed to launch — see the 'launched:false' line(s) above" >&2
	exit 1
fi

STATUS_RUNNER="${SCRIPT_DIR}/run-status.sh"
[ -f "$STATUS_RUNNER" ] || STATUS_RUNNER="${SCRIPT_DIR}/executable_run-status.sh"
if [ -x "$STATUS_RUNNER" ] && [ -f "$(dirname "$WAVE_DIR")/status.json" ]; then
	nohup "$STATUS_RUNNER" "$(dirname "$WAVE_DIR")" --watch \
		>"$(dirname "$WAVE_DIR")/status-watcher.log" 2>&1 </dev/null &
fi
exit 0
