#!/usr/bin/env bash
# launch-workers.sh — Creates a tabbed worker pane and launches an agent in each tab
#
# Usage:
#   launch-workers.sh <run_dir> <cwd> <worker1> <worker2> [worker3] ...
#
# Arguments:
#   run_dir   — Path to the orchestration run directory (must contain system-prompt.txt)
#   cwd       — Working directory for all workers
#   workerN   — Worker spec (kebab-case name, optionally with runner/model/effort):
#                 name                          -> claude, model sonnet, no effort
#                 name:runner:model              -> explicit runner + model
#                 name:runner:model@effort       -> explicit runner + model + effort
#               Supported runners: claude, codex.
#
# Output:
#   Prints JSON with worker surface refs and pane ref to stdout.
#   All other output goes to stderr.
#
# Example:
#   ./launch-workers.sh /tmp/cmux-orchestrator/cmux-20260324-150000 /Users/me/project \
#     auth-refactor backend:claude:opus@high frontend:codex:gpt-5.6-terra@high

set -euo pipefail

# Effort levels accepted after `@` in a worker spec, e.g. `opus@high`.
KNOWN_EFFORTS=(none minimal low medium high xhigh max)

# parse_spec SPEC — sets the globals `name`, `runner`, `model`, `effort`.
#
# Grammar: bare `name` means `name:claude:sonnet`; otherwise
# `name:runner:model` or `name:runner:model@effort`. Anything that doesn't
# fit — an unknown runner, an empty field, extra colons, a trailing `@` with
# no effort, or an effort outside KNOWN_EFFORTS — fails loudly (diagnostic on
# stderr, non-zero return) rather than parsing into a well-formed launch of
# the wrong thing.
parse_spec() {
  local spec="$1" rest model_spec
  case "$spec" in
    *:*:*:*)
      echo "Error: malformed worker spec '${spec}' (too many colons)" >&2
      return 1
      ;;
    *:*:*)
      name=${spec%%:*}; rest=${spec#*:}
      runner=${rest%%:*}; model_spec=${rest#*:}
      ;;
    *) name="$spec"; runner=claude; model_spec=sonnet ;;
  esac

  if [ -z "$name" ] || [ -z "$runner" ] || [ -z "$model_spec" ]; then
    echo "Error: malformed worker spec '${spec}' (empty name, runner, or model)" >&2
    return 1
  fi

  case "$runner" in
    claude | codex) ;;
    *)
      echo "Error: unknown runner '${runner}' in worker spec '${spec}' (expected claude or codex)" >&2
      return 1
      ;;
  esac

  model=${model_spec%@*}
  if [ "$model_spec" = "$model" ]; then
    effort=""
  else
    effort=${model_spec##*@}
    if [ -z "$effort" ]; then
      echo "Error: malformed worker spec '${spec}' (empty effort after @)" >&2
      return 1
    fi
    local known ok=0
    for known in "${KNOWN_EFFORTS[@]}"; do
      if [ "$effort" = "$known" ]; then ok=1; break; fi
    done
    if [ "$ok" -ne 1 ]; then
      echo "Error: unknown effort '${effort}' in worker spec '${spec}' (expected one of: ${KNOWN_EFFORTS[*]})" >&2
      return 1
    fi
  fi

  if [ -z "$model" ]; then
    echo "Error: malformed worker spec '${spec}' (empty model)" >&2
    return 1
  fi
}

[ "${LAUNCH_WORKERS_LIB_ONLY:-0}" = 1 ] && return 0

RUN_DIR="$1"
CWD="$2"
shift 2
SPECS=("$@")

if [ ${#SPECS[@]} -lt 1 ]; then
  echo "Error: at least one worker spec required" >&2
  exit 1
fi

if [ ! -f "${RUN_DIR}/system-prompt.txt" ]; then
  echo "Error: ${RUN_DIR}/system-prompt.txt not found" >&2
  exit 1
fi

# Parse every spec up front so a malformed one fails before we touch cmux at all.
declare -a NAMES RUNNERS MODELS EFFORTS
HAS_CLAUDE=0
HAS_CODEX=0
for spec in "${SPECS[@]}"; do
  parse_spec "$spec"
  NAMES+=("$name")
  RUNNERS+=("$runner")
  MODELS+=("$model")
  EFFORTS+=("$effort")
  [ "$runner" = claude ] && HAS_CLAUDE=1
  [ "$runner" = codex ] && HAS_CODEX=1
done

if ! cmux identify --json >/dev/null 2>&1; then
  echo "Error: not running inside cmux" >&2
  exit 1
fi

if [ "$HAS_CLAUDE" -eq 1 ] && ! command -v claude >/dev/null 2>&1; then
  echo "Error: claude CLI not found" >&2
  exit 1
fi

if [ "$HAS_CODEX" -eq 1 ] && ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex CLI not found" >&2
  exit 1
fi

echo "Creating worker pane..." >&2

# Step 1: Create ONE worker pane (split down from orchestrator)
WORKER_PANE_JSON=$(cmux --json new-pane --direction right)
WORKER_PANE_REF=$(echo "$WORKER_PANE_JSON" | jq -r '.pane_ref')
FIRST_SURFACE=$(echo "$WORKER_PANE_JSON" | jq -r '.surface_ref')

echo "Worker pane: ${WORKER_PANE_REF}" >&2

# Build array of surface refs
declare -a SURFACES
SURFACES[0]="$FIRST_SURFACE"

# Step 2: For each additional worker, create a tab (surface) in the same pane
for ((i = 1; i < ${#NAMES[@]}; i++)); do
  NEW_SURFACE=$(cmux --json new-surface --pane "${WORKER_PANE_REF}" | jq -r '.surface_ref')
  SURFACES[i]="$NEW_SURFACE"
  echo "Created tab for ${NAMES[$i]}: ${NEW_SURFACE}" >&2
done

# build_launch_cmd RUNNER MODEL EFFORT NAME — sets LAUNCH_CMD to the shell
# command line to type into the worker's pane. Every dynamic value (name,
# model, cwd, prompt path) is passed through `printf %q` so a space or shell
# metacharacter in a worker name or cwd can't break the launch; nothing is
# ever interpolated raw into the string handed to `cmux send`.
build_launch_cmd() {
  local runner="$1" model="$2" effort="$3" name="$4"
  local name_q model_q cwd_q prompt_q effort_q

  printf -v name_q '%q' "$name"
  printf -v model_q '%q' "$model"
  printf -v cwd_q '%q' "$CWD"
  printf -v prompt_q '%q' "${RUN_DIR}/system-prompt.txt"

  case "$runner" in
    claude)
      LAUNCH_CMD="cd ${cwd_q} && claude --model ${model_q}"
      if [ -n "$effort" ]; then
        printf -v effort_q '%q' "$effort"
        LAUNCH_CMD="${LAUNCH_CMD} --effort ${effort_q}"
      fi
      LAUNCH_CMD="${LAUNCH_CMD} --name ${name_q} --dangerously-skip-permissions --append-system-prompt-file ${prompt_q}"
      ;;
    codex)
      # effort is validated against KNOWN_EFFORTS, so it's safe to embed
      # verbatim inside the quoted -c value.
      LAUNCH_CMD="cd ${cwd_q} && codex --model ${model_q} -c model_reasoning_effort=\"${effort}\" --dangerously-bypass-approvals-and-sandbox --no-alt-screen"
      ;;
  esac
}

# Step 3: Launch the agent in each surface
for ((i = 0; i < ${#NAMES[@]}; i++)); do
  WORKER="${NAMES[$i]}"
  SURFACE="${SURFACES[i]}"
  echo "Launching ${RUNNERS[$i]} in ${SURFACE} for ${WORKER}..." >&2
  build_launch_cmd "${RUNNERS[$i]}" "${MODELS[$i]}" "${EFFORTS[$i]}" "${WORKER}"
  cmux send --surface "${SURFACE}" -- "${LAUNCH_CMD}\n"
done

# Step 4: Wait for all agents to initialize (overridable so tests don't
# have to eat a real 12s sleep per invocation).
INIT_DELAY="${LAUNCH_WORKERS_INIT_DELAY:-12}"
echo "Waiting ${INIT_DELAY}s for agents to initialize..." >&2
sleep "$INIT_DELAY"

# Step 5: Rename tabs and send task prompts
for ((i = 0; i < ${#NAMES[@]}; i++)); do
  WORKER="${NAMES[$i]}"
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
for ((i = 0; i < ${#NAMES[@]}; i++)); do
  COMMA=""
  if [ $i -lt $((${#NAMES[@]} - 1)) ]; then COMMA=","; fi
  echo "    {\"name\": \"${NAMES[$i]}\", \"runner\": \"${RUNNERS[$i]}\", \"surface_ref\": \"${SURFACES[i]}\"}${COMMA}"
done
echo "  ]"
echo "}"
