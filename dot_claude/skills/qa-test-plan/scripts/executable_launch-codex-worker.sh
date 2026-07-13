#!/usr/bin/env bash
# launch-codex-worker.sh — Launch a codex worker in a cmux pane for visibility.
#
# The bundled cmux-orchestrator launch-workers.sh launches *claude* workers only, so
# the qa-test-plan browser executor (a codex worker driving agent-browser) needs its
# own launcher built on raw cmux primitives.
#
# Usage:
#   launch-codex-worker.sh <run_dir> <cwd> <worker-name> <task-file>
#
# Arguments:
#   run_dir      — orchestration run directory (holds done markers, prompts)
#   cwd          — working directory for the worker (the project under test)
#   worker-name  — kebab-case name, used for the tab label
#   task-file    — path to the markdown task the codex worker executes
#
# Output:
#   Prints JSON with pane_ref + surface_ref (or "mode":"headless" on fallback) to stdout.
#   All progress/diagnostic output goes to stderr.
#
# Behaviour:
#   Opens one pane split-right, cd's to <cwd>, and runs
#     codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check - < <task-file>
#   If any cmux primitive is unavailable, falls back to a plain background codex exec
#   (no pane, no visibility) and says so on stderr.

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

# The command the worker runs inside the pane. Reads the task from the file on stdin.
CODEX_CMD="cd ${CWD} && codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check - < ${TASK_FILE}"

# --- Headless fallback: no cmux, or cmux not usable here -------------------------------
fallback_headless() {
  local reason="$1"
  echo "Warning: ${reason} — falling back to headless codex exec (no pane, no visibility)." >&2
  local log="${RUN_DIR}/${WORKER}.log"
  ( cd "${CWD}" && codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check - < "${TASK_FILE}" ) \
    >"${log}" 2>&1 &
  local pid=$!
  echo "Headless codex worker pid=${pid}, log=${log}" >&2
  printf '{"mode":"headless","pid":%s,"log":"%s"}\n' "${pid}" "${log}"
}

if ! command -v cmux >/dev/null 2>&1; then
  fallback_headless "cmux CLI not found"
  exit 0
fi

if ! cmux identify --json >/dev/null 2>&1; then
  fallback_headless "not running inside cmux"
  exit 0
fi

# --- Visible path: open a pane and drive codex there ----------------------------------
echo "Creating codex worker pane (split right)..." >&2

PANE_JSON=$(cmux --json new-pane --direction right 2>/dev/null)
if [ -z "${PANE_JSON}" ]; then
  fallback_headless "cmux new-pane failed"
  exit 0
fi

PANE_REF=$(echo "${PANE_JSON}" | jq -r '.pane_ref // empty' 2>/dev/null)
SURFACE_REF=$(echo "${PANE_JSON}" | jq -r '.surface_ref // empty' 2>/dev/null)

if [ -z "${SURFACE_REF}" ]; then
  fallback_headless "could not read surface_ref from cmux new-pane"
  exit 0
fi

echo "Worker pane: ${PANE_REF} (surface ${SURFACE_REF})" >&2

# Label the tab (best-effort — do not fail the launch if rename is unsupported).
cmux rename-tab --surface "${SURFACE_REF}" "w: ${WORKER}" 2>/dev/null || true

# Send the codex command; trailing \n auto-submits (Enter).
if ! cmux send --surface "${SURFACE_REF}" -- "${CODEX_CMD}\n"; then
  fallback_headless "cmux send failed"
  exit 0
fi

echo "Codex worker ${WORKER} started in ${SURFACE_REF}" >&2

printf '{"mode":"pane","pane_ref":"%s","surface_ref":"%s"}\n' "${PANE_REF}" "${SURFACE_REF}"
