#!/usr/bin/env bash
# dispatch.sh — orchestrates a /review-panel run end-to-end.
#
# Usage:
#   dispatch.sh <variant> [--reviewers N] [--ratio C:X] [--scope ref]
#               [--task id] [--timeout secs] [--keep-artifacts] [--dry-run]
#
# Output: streams progress to stderr, prints final report.md to stdout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
VARIANTS_DIR="${SKILL_DIR}/variants"
RUNS_ROOT="${HOME}/.claude/review-panel-runs"

# --- Defaults ---
VARIANT="default"
REVIEWERS=10
RATIO="5:5"
SCOPE="main...HEAD"
TASK=""
TIMEOUT=600
KEEP_ARTIFACTS=0
DRY_RUN=0

log() { printf '[review-panel] %s\n' "$*" >&2; }
err() { printf '[review-panel] ERROR: %s\n' "$*" >&2; exit 1; }

# --- Parse args ---
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
  VARIANT="$1"
  shift
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --reviewers)        REVIEWERS="$2"; shift 2 ;;
    --ratio)            RATIO="$2"; shift 2 ;;
    --scope)            SCOPE="$2"; shift 2 ;;
    --task)             TASK="$2"; shift 2 ;;
    --timeout)          TIMEOUT="$2"; shift 2 ;;
    --keep-artifacts)   KEEP_ARTIFACTS=1; shift ;;
    --dry-run)          DRY_RUN=1; shift ;;
    *)                  err "unknown flag: $1" ;;
  esac
done

# --- Validate ---
VARIANT_FILE="${VARIANTS_DIR}/${VARIANT}.yml"
[ -f "$VARIANT_FILE" ] || {
  AVAILABLE=$(find "$VARIANTS_DIR" -maxdepth 1 -name '*.yml' -exec basename {} .yml \; | tr '\n' ' ')
  err "variant '$VARIANT' not found at $VARIANT_FILE. Available: $AVAILABLE"
}

if ! [[ "$REVIEWERS" =~ ^[0-9]+$ ]] || [ "$REVIEWERS" -le 0 ]; then
  err "--reviewers must be positive integer (got: $REVIEWERS)"
fi
[[ "$RATIO" =~ ^([0-9]+):([0-9]+)$ ]] || err "--ratio must be N:M (got: $RATIO)"
RATIO_C="${BASH_REMATCH[1]}"
RATIO_X="${BASH_REMATCH[2]}"
RATIO_SUM=$((RATIO_C + RATIO_X))
[ "$RATIO_SUM" -gt 0 ] || err "--ratio cannot be 0:0"

# Rebalance ratio to total --reviewers (proportional)
N_CLAUDE=$(( REVIEWERS * RATIO_C / RATIO_SUM ))
N_CODEX=$(( REVIEWERS - N_CLAUDE ))

command -v yq      >/dev/null 2>&1 || err "yq not installed (brew install yq)"
command -v git     >/dev/null 2>&1 || err "git not installed"
[ "$N_CLAUDE" -gt 0 ] && { command -v claude >/dev/null 2>&1 || err "claude CLI not installed"; }
[ "$N_CODEX" -gt 0 ]  && { command -v codex  >/dev/null 2>&1 || err "codex CLI not installed (npm i -g @openai/codex)"; }
[[ "$SCOPE" == PR-* ]] && { command -v gh >/dev/null 2>&1 || err "gh CLI required for --scope PR-*"; }

# --- Run dir ---
RUN_ID="run-$(date +%Y%m%d-%H%M%S)-$(openssl rand -hex 2)"
RUN_DIR="/tmp/review-panel/${RUN_ID}"
mkdir -p "${RUN_DIR}/reviewers" "${RUN_DIR}/results" "${RUN_DIR}/logs"

log "run-id=${RUN_ID}"
log "variant=${VARIANT} reviewers=${REVIEWERS} ratio=${N_CLAUDE}c:${N_CODEX}x scope=${SCOPE}"

# --- Read personas from variant ---
PERSONA_COUNT=$(yq '.personas | length' "$VARIANT_FILE")
[ "$PERSONA_COUNT" -ge 1 ] || err "variant has no personas"

# --- MCP / CLI availability check for `requires_mcp` field ---
SETTINGS_FILE="${HOME}/.claude/settings.json"

# Map MCP name → fallback CLI binary (when the MCP isn't configured but the CLI
# can still feed task data into context.md). Keep this list small and explicit.
declare -A MCP_CLI_FALLBACK=(
  [linear]=lineark
)

mcp_or_cli_available() {
  # Returns 0 if the named MCP is configured in settings.json OR its CLI
  # fallback exists in PATH. Returns 1 otherwise.
  local name="$1"
  if [ -f "$SETTINGS_FILE" ] && jq -e --arg k "$name" '.mcpServers[$k] // empty' "$SETTINGS_FILE" >/dev/null 2>&1; then
    return 0
  fi
  local cli="${MCP_CLI_FALLBACK[$name]:-}"
  if [ -n "$cli" ] && command -v "$cli" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

persona_requires_satisfied() {
  # Returns 0 if persona at index $1 has no requires_mcp OR at least one of its
  # required MCPs/CLIs is available. Returns 1 (skip) otherwise.
  local idx="$1"
  local reqs
  reqs=$(yq -r ".personas[$idx].requires_mcp // [] | .[]" "$VARIANT_FILE" 2>/dev/null)
  [ -z "$reqs" ] && return 0  # no requirements → always available
  while IFS= read -r req; do
    [ -z "$req" ] && continue
    if mcp_or_cli_available "$req"; then return 0; fi
  done <<< "$reqs"
  return 1
}

# Pick personas: cycle if we need more reviewers than personas defined.
# Personas with unmet `requires_mcp` go into SKIPPED instead of PERSONAS.
PERSONAS=()
RUNNERS=()
SKIPPED=()
SKIPPED_REASON=()
slots_claude=$N_CLAUDE
slots_codex=$N_CODEX

for ((i=0; i<REVIEWERS; i++)); do
  pid=$(( i % PERSONA_COUNT ))
  persona_id=$(yq ".personas[$pid].id" "$VARIANT_FILE")
  persona_runner=$(yq ".personas[$pid].runner" "$VARIANT_FILE")

  # Skip personas whose required MCPs/CLIs aren't available
  if ! persona_requires_satisfied "$pid"; then
    base="$persona_id"
    suffix=$(( i / PERSONA_COUNT ))
    [ "$suffix" -gt 0 ] && persona_id="${base}-${suffix}"
    reqs=$(yq -r ".personas[$pid].requires_mcp | join(\", \")" "$VARIANT_FILE")
    SKIPPED+=("$persona_id")
    SKIPPED_REASON+=("requires one of: ${reqs} (no MCP configured, no CLI fallback)")
    log "  [${persona_id}] SKIPPED — requires one of: ${reqs}"
    continue
  fi

  # Resolve runner per ratio
  case "$persona_runner" in
    claude) runner="claude"; slots_claude=$((slots_claude-1)) ;;
    codex)  runner="codex";  slots_codex=$((slots_codex-1)) ;;
    any|null|"")
      if [ "$slots_claude" -gt 0 ]; then runner="claude"; slots_claude=$((slots_claude-1));
      elif [ "$slots_codex" -gt 0 ]; then runner="codex";  slots_codex=$((slots_codex-1));
      else runner="claude"; fi ;;
    *) err "unknown runner '$persona_runner' for persona $persona_id" ;;
  esac

  # Suffix duplicate IDs to keep result files unique
  base="$persona_id"
  suffix=$(( i / PERSONA_COUNT ))
  [ "$suffix" -gt 0 ] && persona_id="${base}-${suffix}"

  PERSONAS+=("$persona_id")
  RUNNERS+=("$runner")
done

[ "${#PERSONAS[@]}" -gt 0 ] || err "no eligible personas after filtering by --requires_mcp; check your MCP config"

# --- Dry run: print plan and exit ---
if [ "$DRY_RUN" = 1 ]; then
  log "DRY RUN — no reviewers will be spawned"
  echo
  printf 'Variant:   %s\n' "$VARIANT"
  printf 'Reviewers: %d (%d Claude + %d Codex)\n' "$REVIEWERS" "$N_CLAUDE" "$N_CODEX"
  printf 'Scope:     %s\n' "$SCOPE"
  [ -n "$TASK" ] && printf 'Task:      %s\n' "$TASK"
  printf 'Timeout:   %ds per reviewer\n' "$TIMEOUT"
  printf 'Run dir:   %s\n' "$RUN_DIR"
  echo
  printf 'Persona assignments:\n'
  for ((i=0; i<${#PERSONAS[@]}; i++)); do
    printf '  %2d. %-30s → %s\n' $((i+1)) "${PERSONAS[$i]}" "${RUNNERS[$i]}"
  done
  if [ "${#SKIPPED[@]}" -gt 0 ]; then
    printf '\nSkipped (unmet requirements):\n'
    for ((i=0; i<${#SKIPPED[@]}; i++)); do
      printf '  -  %-30s %s\n' "${SKIPPED[$i]}" "${SKIPPED_REASON[$i]}"
    done
  fi
  echo
  printf 'Estimated cost: ~%dk tokens (rough: 5k input + 2k output per reviewer + 10k aggregator)\n' \
    $(( ${#PERSONAS[@]} * 7 + 10 ))
  exit 0
fi

# --- Synthetic results for skipped personas (so aggregator surfaces them) ---
for ((i=0; i<${#SKIPPED[@]}; i++)); do
  pname="${SKIPPED[$i]}"
  preason="${SKIPPED_REASON[$i]}"
  # shellcheck disable=SC2016  # %s are printf format specifiers, not shell expansions
  printf '```yaml\nverdict: APPROVE\nfindings: []\nnotes: |\n  Persona %s skipped — %s.\n```\n' \
    "$pname" "$preason" > "${RUN_DIR}/results/${pname}.md"
done

# --- Phase 1: Collect context ---
log "collecting context (scope=${SCOPE})..."
"${SCRIPT_DIR}/collect-context.sh" "$RUN_DIR" "$SCOPE" "$TASK"

# --- Phase 2: Build per-reviewer prompts ---
OUTPUT_SCHEMA=$(yq '.output_schema' "$VARIANT_FILE")

for ((i=0; i<${#PERSONAS[@]}; i++)); do
  persona_id="${PERSONAS[$i]}"
  pidx=$(( i % PERSONA_COUNT ))
  base_id=$(yq ".personas[$pidx].id" "$VARIANT_FILE")
  role=$(yq ".personas[$pidx].role" "$VARIANT_FILE")
  focus=$(yq ".personas[$pidx].focus" "$VARIANT_FILE")
  body=$(yq ".personas[$pidx].prompt" "$VARIANT_FILE")

  cat > "${RUN_DIR}/reviewers/${persona_id}.prompt.md" <<EOF
# Persona: ${persona_id} (base: ${base_id})

## Role
${role}

## Focus area
${focus}

## Instructions
${body}

## Output format (REQUIRED)

You MUST output ONLY a single fenced YAML block in exactly this shape — nothing
else, no preamble, no commentary outside the fence:

${OUTPUT_SCHEMA}

After the YAML block, do not write anything else. Exit immediately.

The diff and repo context follow below the separator.
EOF
done

# --- Phase 3: Fan out reviewers in background ---
log "starting ${REVIEWERS} reviewers (timeout=${TIMEOUT}s each)..."
declare -a PIDS
declare -a START_TS

# shellcheck disable=SC2154  # $p is the loop variable inside the trap, not an external ref
trap 'log "interrupt — killing reviewers..."; for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done; exit 130' INT TERM

for ((i=0; i<${#PERSONAS[@]}; i++)); do
  persona_id="${PERSONAS[$i]}"
  runner="${RUNNERS[$i]}"
  result_file="${RUN_DIR}/results/${persona_id}.md"
  log_file="${RUN_DIR}/logs/${persona_id}.log"

  log "  [${persona_id}] dispatching (${runner})"
  "${SCRIPT_DIR}/reviewer.sh" "$runner" "$persona_id" "$RUN_DIR" "$TIMEOUT" \
    > "$result_file" 2> "$log_file" &
  PIDS+=($!)
  START_TS+=("$(date +%s)")
done

# --- Phase 4: Wait, then collect status ---
SUCCEEDED=0
FAILED=0
for ((i=0; i<${#PIDS[@]}; i++)); do
  if wait "${PIDS[$i]}"; then
    SUCCEEDED=$((SUCCEEDED+1))
    elapsed=$(( $(date +%s) - START_TS[i] ))
    log "  [${PERSONAS[$i]}] done (${elapsed}s)"
  else
    FAILED=$((FAILED+1))
    elapsed=$(( $(date +%s) - START_TS[i] ))
    log "  [${PERSONAS[$i]}] FAILED (${elapsed}s) — see ${RUN_DIR}/logs/${PERSONAS[$i]}.log"
    # Drop empty result so aggregator doesn't trip
    : > "${RUN_DIR}/results/${PERSONAS[$i]}.md"
    # shellcheck disable=SC2016  # %s are printf format specifiers, not shell expansions
    printf '```yaml\nverdict: REQUEST_CHANGES\nfindings: []\nnotes: |\n  Reviewer %s (%s) failed — no findings produced.\n```\n' \
      "${PERSONAS[$i]}" "${RUNNERS[$i]}" > "${RUN_DIR}/results/${PERSONAS[$i]}.md"
  fi
done

log "reviewers done: ${SUCCEEDED} ok, ${FAILED} failed"

# --- Phase 5: Aggregate ---
log "aggregating findings..."
"${SCRIPT_DIR}/aggregate.sh" "$RUN_DIR"

# --- Phase 6: Persist report and optionally clean up ---
PERSIST_DIR="${RUNS_ROOT}/${RUN_ID}"
mkdir -p "$PERSIST_DIR"
cp "${RUN_DIR}/report.md" "${PERSIST_DIR}/report.md"
cp "${RUN_DIR}/context.md" "${PERSIST_DIR}/context.md"
log "report saved to ${PERSIST_DIR}/report.md"

if [ "$KEEP_ARTIFACTS" = 0 ]; then
  rm -rf "$RUN_DIR"
  log "cleaned up ${RUN_DIR}"
else
  log "keeping artifacts at ${RUN_DIR}"
fi
