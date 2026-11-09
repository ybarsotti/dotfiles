#!/usr/bin/env bash
# worker-loop.sh — runs one lane as a sequence of headless agent turns.
#
# Usage:
#   worker-loop.sh RUN_DIR LANE
#
# The lane's record in RUN_DIR/launch/manifest.json (written by init-run.sh)
# gives the runner, model, effort, session id and brief. Any terminal can run
# this script: orca-launch.sh starts it in an Orca terminal, and a plain
# `nohup worker-loop.sh RUN_DIR LANE &` is the headless fallback.
#
# Turns. The first turn sends the brief. Each later turn sends the replies
# that reply.sh published since the last turn. A claude lane keeps one
# conversation: `--session-id` on its first turn, `--resume` after that, also
# after a relaunch. A codex lane is stateless per turn, so every codex turn
# sends the worker rules and the brief again.
#
# Replies. reply.sh publishes lanes/<lane>/replies/<NNNNNN>.md atomically. This
# loop records the highest reply number it delivered in
# lanes/<lane>/replies.consumed, after the turn succeeds. A reply that lands
# during a turn has a higher number, so the next turn delivers it.
#
# Idle and stop. `done` ends a round, not the lane: the loop stays alive and
# waits for the next reply, because review and QA fixes come back to the lane
# that owns the code. The loop exits 0 only when lanes/<lane>/stop exists.
#
# Liveness. The loop writes its pid to lanes/<lane>/loop.pid, and tees the
# agent output to lanes/<lane>/worker.log. monitor-events.sh and reply.sh
# check the pid with `kill -0`; monitor-events.sh scans the log.
#
# Failure. An agent that fails, a turn that times out, a brief with an
# unresolved placeholder and the turn cap all emit `blocked` for the lane's
# first declared task, then exit nonzero. A lane that dies without a word is
# indistinguishable from one that is still thinking.
#
# Environment: WORKER_LOOP_MAX_TURNS (default 40), WORKER_LOOP_POLL_SECONDS
# (default 2), WORKER_LOOP_TURN_TIMEOUT in seconds (default 3600).
set -uo pipefail

if [ $# -ne 2 ]; then
	echo "worker-loop.sh: usage: worker-loop.sh RUN_DIR LANE" >&2
	exit 2
fi
RUN_DIR="$(cd "$1" 2>/dev/null && pwd)" || {
	echo "worker-loop.sh: no such run directory: $1" >&2
	exit 2
}
LANE="$2"

MAX_TURNS="${WORKER_LOOP_MAX_TURNS:-40}"
POLL_SECONDS="${WORKER_LOOP_POLL_SECONDS:-2}"
TURN_TIMEOUT="${WORKER_LOOP_TURN_TIMEOUT:-3600}"

command -v jq >/dev/null 2>&1 || {
	echo "worker-loop.sh: jq required" >&2
	exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVENT="${SCRIPT_DIR}/event.sh"
[ -f "$EVENT" ] || EVENT="${SCRIPT_DIR}/executable_event.sh"

LAUNCH="${RUN_DIR}/launch/manifest.json"
LANE_DIR="${RUN_DIR}/lanes/${LANE}"
REPLIES="${LANE_DIR}/replies"
CONSUMED="${LANE_DIR}/replies.consumed"
STARTED="${LANE_DIR}/session.started"
SYSTEM_FILE="${RUN_DIR}/launch/system-prompt.txt"

RECORD=$(jq -c --arg n "$LANE" '.workers[]? | select(.name == $n)' "$LAUNCH" 2>/dev/null)
if [ -z "$RECORD" ]; then
	echo "worker-loop.sh: lane '${LANE}' has no record in ${LAUNCH}" >&2
	exit 2
fi
field() { jq -r --arg k "$1" '.[$k] // ""' <<<"$RECORD"; }
RUNNER=$(field runner)
MODEL=$(field model)
EFFORT=$(field effort)
SESSION_ID=$(field session_id)
BRIEF_FILE=$(field prompt_file)
TASK=$(field task)
[ -n "$TASK" ] || TASK="lane ${LANE}"

# emit TYPE MSG — a failure to write the event is reported, never swallowed.
emit() {
	bash "$EVENT" "$RUN_DIR" "$LANE" "$TASK" "$1" "$2" >/dev/null ||
		echo "worker-loop.sh: could not write the '$1' event for lane ${LANE}" >&2
}
fail() {
	echo "worker-loop.sh: $2" >&2
	emit blocked "$2"
	exit "$1"
}

[ -f "$BRIEF_FILE" ] || fail 2 "lane ${LANE} has no brief at ${BRIEF_FILE}"
[ -f "$SYSTEM_FILE" ] || fail 2 "lane ${LANE} has no worker rules at ${SYSTEM_FILE}"
if grep -qE '\{\{[A-Z_]+\}\}' "$BRIEF_FILE"; then
	fail 2 "the brief of lane ${LANE} has an unresolved placeholder: ${BRIEF_FILE}"
fi

CWD=$(jq -r '.cwd // empty' "${RUN_DIR}/manifest.json" 2>/dev/null)
if [ -n "$CWD" ]; then
	cd "$CWD" || fail 2 "lane ${LANE} cannot enter the worktree ${CWD}"
fi

mkdir -p "$REPLIES"
rm -f "${LANE_DIR}/stop"
printf '%s\n' "$$" >"${LANE_DIR}/loop.pid"

# macOS ships no `timeout`: gtimeout, then timeout, then perl's alarm.
if command -v gtimeout >/dev/null 2>&1; then
	with_timeout() { gtimeout "$@"; }
elif command -v timeout >/dev/null 2>&1; then
	with_timeout() { timeout "$@"; }
else
	with_timeout() {
		local secs="$1"
		shift
		perl -e 'alarm shift @ARGV; exec @ARGV' "$secs" "$@"
	}
fi

# run_turn PROMPT — one agent call; the prompt is always the last argument.
run_turn() {
	local prompt="$1" args
	case "$RUNNER" in
	codex)
		# Sandboxed: the worktree (cwd) and RUN_DIR, where event.sh writes, are writable.
		# Network stays on, because lane tests install packages and call local services.
		args=(codex exec --skip-git-repo-check --sandbox workspace-write --add-dir "$RUN_DIR"
			-c approval_policy=never -c sandbox_workspace_write.network_access=true)
		[ -n "$MODEL" ] && args+=(--model "$MODEL")
		[ -n "$EFFORT" ] && args+=(-c "model_reasoning_effort=${EFFORT}")
		;;
	*)
		# No sandbox: a claude lane relies on the shared-worktree boundary checks and the git deny.
		args=(claude -p --dangerously-skip-permissions --disallowedTools "Bash(git:*)"
			--append-system-prompt "$(cat "$SYSTEM_FILE")")
		[ -n "$MODEL" ] && args+=(--model "$MODEL")
		[ -n "$EFFORT" ] && args+=(--effort "$EFFORT")
		if [ -f "$STARTED" ]; then args+=(--resume "$SESSION_ID"); else args+=(--session-id "$SESSION_ID"); fi
		;;
	esac
	# The session exists once the agent starts, so a relaunch after a crash resumes it.
	: >"$STARTED"
	with_timeout "$TURN_TIMEOUT" "${args[@]}" "$prompt" 2>&1 | tee -a "${LANE_DIR}/worker.log"
	return "${PIPESTATUS[0]}"
}

# pending_replies — the reply files newer than the consumed number, in order.
pending_replies() {
	local consumed f n
	consumed=$(cat "$CONSUMED" 2>/dev/null || echo 0)
	case "$consumed" in '' | *[!0-9]*) consumed=0 ;; esac
	for f in "$REPLIES"/*.md; do
		[ -f "$f" ] || continue
		n=$(basename "$f" .md)
		[ $((10#$n)) -gt "$consumed" ] && printf '%s\n' "$f"
	done
}

EXTRA=""
NEED_TURN=1
if [ -f "$STARTED" ]; then
	EXTRA="You are resuming lane ${LANE} after the loop restarted. Read your brief again at ${BRIEF_FILE}, check the board, and continue where you stopped."
fi
TURN=0
while :; do
	LAST_SEQ=""
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		n=$(basename "$f" .md)
		EXTRA="${EXTRA}${EXTRA:+$'\n\n'}## Reply from the orchestrator (${n})"$'\n\n'"$(cat "$f")"
		LAST_SEQ=$((10#$n))
		NEED_TURN=1
	done < <(pending_replies)

	if [ "$NEED_TURN" -eq 1 ]; then
		[ "$TURN" -lt "$MAX_TURNS" ] || fail 1 "worker-loop hit its ${MAX_TURNS}-turn cap with a reply still to deliver"
		TURN=$((TURN + 1))
		printf '\n=== lane %s — turn %s ===\n' "$LANE" "$TURN"
		if [ "$RUNNER" = "codex" ]; then
			PROMPT="$(cat "$SYSTEM_FILE")"$'\n\n'"$(cat "$BRIEF_FILE")"
		elif [ -f "$STARTED" ]; then
			PROMPT=""
		else
			PROMPT="$(cat "$BRIEF_FILE")"
		fi
		PROMPT="${PROMPT}${PROMPT:+${EXTRA:+$'\n\n'}}${EXTRA}"
		run_turn "$PROMPT" || fail 1 "agent command failed on turn ${TURN}; lane ${LANE} needs the orchestrator"
		[ -n "$LAST_SEQ" ] && printf '%s\n' "$LAST_SEQ" >"$CONSUMED"
		EXTRA=""
		NEED_TURN=0
		continue
	fi

	if [ -f "${LANE_DIR}/stop" ]; then
		rm -f "${LANE_DIR}/loop.pid"
		echo "worker-loop.sh: lane ${LANE} stopped"
		exit 0
	fi
	sleep "$POLL_SECONDS"
done
