#!/usr/bin/env bash
# launch-workers.sh — Creates a tabbed worker pane and launches Claude in each tab
#
# Usage:
#   launch-workers.sh <run_dir> <cwd> <worker1> <worker2> [worker3] ...
#
# Arguments:
#   run_dir   — Path to the orchestration run directory (must contain system-prompt.txt)
#   cwd       — Working directory for all workers
#   workerN   — Worker names (kebab-case, e.g. auth-refactor add-tests api-docs)
#
# Output:
#   Prints JSON with worker surface refs and pane ref to stdout.
#   All other output goes to stderr.
#
# Example:
#   ./launch-workers.sh /tmp/cmux-orchestrator/cmux-20260324-150000 /Users/me/project auth-refactor add-tests api-docs

set -euo pipefail

RUN_DIR="$1"
CWD="$2"
shift 2
WORKERS=("$@")

if [ ${#WORKERS[@]} -lt 1 ]; then
  echo "Error: at least one worker name required" >&2
  exit 1
fi

if [ ! -f "${RUN_DIR}/system-prompt.txt" ]; then
  echo "Error: ${RUN_DIR}/system-prompt.txt not found" >&2
  exit 1
fi

if ! cmux identify --json >/dev/null 2>&1; then
  echo "Error: not running inside cmux" >&2
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "Error: claude CLI not found" >&2
  exit 1
fi

echo "Creating worker pane..." >&2

# Step 1: Create ONE worker pane (split down from orchestrator)
WORKER_PANE_JSON=$(cmux --json new-pane --direction down)
WORKER_PANE_REF=$(echo "$WORKER_PANE_JSON" | jq -r '.pane_ref')
FIRST_SURFACE=$(echo "$WORKER_PANE_JSON" | jq -r '.surface_ref')

echo "Worker pane: ${WORKER_PANE_REF}" >&2

# Build array of surface refs
declare -a SURFACES
SURFACES[0]="$FIRST_SURFACE"

# Step 2: For each additional worker, create a tab (surface) in the same pane
for ((i=1; i<${#WORKERS[@]}; i++)); do
  NEW_SURFACE=$(cmux --json new-surface --pane "${WORKER_PANE_REF}" | jq -r '.surface_ref')
  SURFACES[i]="$NEW_SURFACE"
  echo "Created tab for ${WORKERS[$i]}: ${NEW_SURFACE}" >&2
done

# Step 3: Launch Claude in each surface
for ((i=0; i<${#WORKERS[@]}; i++)); do
  WORKER="${WORKERS[$i]}"
  SURFACE="${SURFACES[i]}"
  echo "Launching Claude in ${SURFACE} for ${WORKER}..." >&2
  cmux send --surface "${SURFACE}" -- "cd ${CWD} && claude --model sonnet --name '${WORKER}' --dangerously-skip-permissions --append-system-prompt-file ${RUN_DIR}/system-prompt.txt\n"
done

# Step 4: Wait for all Claude instances to initialize
echo "Waiting 12s for Claude to initialize..." >&2
sleep 12

# Step 5: Rename tabs and send task prompts
for ((i=0; i<${#WORKERS[@]}; i++)); do
  WORKER="${WORKERS[$i]}"
  SURFACE="${SURFACES[i]}"

  # Rename tab
  cmux rename-tab --surface "${SURFACE}" "w: ${WORKER}"

  # Send task prompt
  PROMPT_FILE="${RUN_DIR}/worker-${WORKER}.prompt.md"
  if [ -f "$PROMPT_FILE" ]; then
    cmux send --surface "${SURFACE}" -- "Read and execute the task described at ${PROMPT_FILE} — start immediately.\n"
    echo "Task sent to ${WORKER} (${SURFACE})" >&2
  else
    echo "Warning: ${PROMPT_FILE} not found, skipping task send for ${WORKER}" >&2
  fi
done

# Step 6: Output JSON result to stdout
echo "{"
echo "  \"pane_ref\": \"${WORKER_PANE_REF}\","
echo "  \"workers\": ["
for ((i=0; i<${#WORKERS[@]}; i++)); do
  COMMA=""
  if [ $i -lt $((${#WORKERS[@]} - 1)) ]; then COMMA=","; fi
  echo "    {\"name\": \"${WORKERS[$i]}\", \"surface_ref\": \"${SURFACES[i]}\"}${COMMA}"
done
echo "  ]"
echo "}"
