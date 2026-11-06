#!/usr/bin/env bash
# launch-codex-worker.sh — Launch a codex worker in an Orca terminal for visibility.
#
# The qa-test-plan browser executor is a codex worker that drives agent-browser. It runs
# in its own Orca terminal, so the user can watch it.
#
# Usage:
#   launch-codex-worker.sh <run_dir> <cwd> <worker-name> <task-file>
#
# Arguments:
#   run_dir      — orchestration run directory (holds done markers, prompts)
#   cwd          — working directory for the worker (the project under test)
#   worker-name  — kebab-case name, used for the terminal title
#   task-file    — path to the markdown task the codex worker executes
#
# Output:
#   Prints JSON with the terminal handle (or "mode":"headless" on fallback) to stdout.
#   All progress/diagnostic output goes to stderr.
#
# Behaviour:
#   Opens one Orca terminal in <cwd> that runs
#     codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check - < <task-file>
#   Outside an Orca workspace, falls back to a plain background codex exec
#   (no terminal, no visibility) and says so on stderr.

set -uo pipefail

if [ "$#" -lt 4 ]; then
  echo "Usage: launch-codex-worker.sh <run_dir> <cwd> <worker-name> <task-file>" >&2
  exit 1
fi

RUN_DIR="$1"
CWD="$2"
WORKER="$3"
TASK_FILE="$4"

if [ ! -f "$TASK_FILE" ]; then
  echo "Error: task file ${TASK_FILE} not found" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI not found" >&2
  exit 1
fi

mkdir -p "$RUN_DIR"

# The command the worker runs inside the terminal. Reads the task from the file on stdin.
CODEX_CMD="cd $(printf %q "$CWD") && codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check - < $(printf %q "$TASK_FILE")"

# --- Headless fallback: no Orca workspace here ----------------------------------------
fallback_headless() {
  local reason="$1"
  echo "Warning: ${reason} — falling back to headless codex exec (no terminal, no visibility)." >&2
  local log="${RUN_DIR}/${WORKER}.log"
  ( cd "${CWD}" && codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check - < "${TASK_FILE}" ) \
    >"${log}" 2>&1 &
  local pid=$!
  echo "Headless codex worker pid=${pid}, log=${log}" >&2
  printf '{"mode":"headless","pid":%s,"log":"%s"}\n' "${pid}" "${log}"
}

if ! command -v orca >/dev/null 2>&1; then
  fallback_headless "orca CLI not found"
  exit 0
fi

if ! orca worktree current --json >/dev/null 2>&1; then
  fallback_headless "not inside an Orca workspace"
  exit 0
fi

# --- Visible path: open an Orca terminal that runs codex ------------------------------
echo "Creating codex worker terminal..." >&2

if ! OUT=$(orca terminal create --worktree "path:${CWD}" --title "w: ${WORKER}" --command "$CODEX_CMD" --json 2>&1); then
  fallback_headless "orca terminal create failed: ${OUT}"
  exit 0
fi

HANDLE=$(printf '%s' "$OUT" | jq -r '[.. | .handle? // empty | strings] | first // empty' 2>/dev/null)
if [ -z "${HANDLE}" ]; then
  fallback_headless "could not read the terminal handle from orca terminal create"
  exit 0
fi

echo "Codex worker ${WORKER} started in ${HANDLE}" >&2

printf '{"mode":"terminal","terminal":"%s"}\n' "${HANDLE}"
