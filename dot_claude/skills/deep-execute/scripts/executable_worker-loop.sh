#!/usr/bin/env bash
# worker-loop.sh — run one lane as a sequence of headless turns inside a Wave block.
#
# Usage:
#   worker-loop.sh RUN_DIR LANE SESSION_ID RUNNER MODEL PROMPT_FILE
#
# Why a loop and not an interactive REPL. Wave's `wsh` can launch a block but cannot
# type into one — there is no `wsh send`, and `wsh termscrollback` only reads. cmux had
# `cmux send`, which is how a `waiting` lane used to be woken. So the wake is a FILE
# here: reply.sh writes `lanes/<lane>/reply.md`, and this loop resumes the lane when
# that file changes. The agent still never polls; the loop waits, the agent does not.
#
# Why a pinned session id. Every lane shares ONE worktree, so `claude --continue` would
# resume whichever lane spoke last. `--session-id <uuid>` on the first turn and
# `--resume <uuid>` afterwards pin each lane to its own conversation.
#
# Codex lanes are stateless per turn. `codex exec resume` takes a session id but there
# is no flag to pin one at creation, so a codex lane re-reads its prompt file and reply
# each turn instead of resuming. The prompt file, reply.md and the worktree carry the
# state that matters; the model's own memory of earlier turns does not survive.
#
# The loop ends when the lane's last event is `done`, when MAX_TURNS is reached, or when
# the agent command fails. A failure emits `blocked` rather than exiting silently: the
# orchestrator's monitor triggers on `blocked`, and a lane that dies without a word is
# indistinguishable from one that is still thinking.
set -uo pipefail

if [ $# -lt 6 ]; then
	echo "worker-loop.sh: usage: worker-loop.sh RUN_DIR LANE SESSION_ID RUNNER MODEL PROMPT_FILE" >&2
	exit 2
fi

RUN_DIR="$1"
LANE="$2"
SESSION_ID="$3"
RUNNER="$4"
MODEL="$5"
PROMPT_FILE="$6"

MAX_TURNS="${WORKER_LOOP_MAX_TURNS:-40}"
POLL_SECONDS="${WORKER_LOOP_POLL_SECONDS:-5}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVENT="${SCRIPT_DIR}/event.sh"
[ -f "$EVENT" ] || EVENT="${SCRIPT_DIR}/executable_event.sh"

EVENTS="${RUN_DIR}/events.jsonl"
REPLY_FILE="${RUN_DIR}/lanes/${LANE}/reply.md"

command -v jq >/dev/null 2>&1 || {
	echo "worker-loop.sh: jq required" >&2
	exit 2
}

# GNU and BSD stat disagree on the mtime flag, and this runs on both.
mtime_of() {
	[ -f "$1" ] || {
		echo 0
		return
	}
	stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

# The lane's own last event. Any malformed line is skipped rather than fatal — the loop
# must not die on a partial write from a concurrent appender.
last_event_type() {
	[ -f "$EVENTS" ] || return 0
	jq -r --arg l "$LANE" 'select(.lane == $l) | .type' "$EVENTS" 2>/dev/null | tail -1
}

emit() {
	[ -f "$EVENT" ] || return 0
	bash "$EVENT" "$RUN_DIR" "$LANE" "$1" "$2" >/dev/null 2>&1 || true
}

run_turn() {
	local prompt="$1" first="$2"
	case "$RUNNER" in
	codex)
		# Stateless per turn — see the header.
		codex exec ${MODEL:+--model "$MODEL"} "$prompt"
		;;
	*)
		if [ "$first" = "first" ]; then
			claude -p --session-id "$SESSION_ID" ${MODEL:+--model "$MODEL"} "$prompt"
		else
			claude -p --resume "$SESSION_ID" ${MODEL:+--model "$MODEL"} "$prompt"
		fi
		;;
	esac
}

PROMPT="Read and execute the task described at ${PROMPT_FILE} — start immediately."
FIRST="first"
TURN=0

while [ "$TURN" -lt "$MAX_TURNS" ]; do
	TURN=$((TURN + 1))
	printf '\n=== lane %s — turn %s ===\n' "$LANE" "$TURN"

	if ! run_turn "$PROMPT" "$FIRST"; then
		emit blocked "agent command failed on turn ${TURN}; lane needs the orchestrator"
		echo "worker-loop.sh: ${RUNNER} failed on turn ${TURN} for lane ${LANE}" >&2
		exit 1
	fi
	FIRST="resume"

	if [ "$(last_event_type)" = "done" ]; then
		echo "worker-loop.sh: lane ${LANE} reported done after turn ${TURN}"
		exit 0
	fi

	# Wait for the orchestrator's reply. The mtime is sampled BEFORE the wait, so a
	# reply that lands between the turn ending and the wait starting is not missed.
	BEFORE=$(mtime_of "$REPLY_FILE")
	echo "worker-loop.sh: lane ${LANE} waiting for ${REPLY_FILE}"
	while [ "$(mtime_of "$REPLY_FILE")" = "$BEFORE" ]; do
		sleep "$POLL_SECONDS"
	done

	PROMPT="Read ${REPLY_FILE}, apply it, then continue your lane."
done

emit blocked "worker-loop hit its ${MAX_TURNS}-turn cap without reporting done"
echo "worker-loop.sh: lane ${LANE} hit the ${MAX_TURNS}-turn cap" >&2
exit 1
