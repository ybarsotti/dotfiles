#!/usr/bin/env bash
# init-run.sh — scaffolds a deep-execute run directory from an approved
# parallel plan: validates the plan, refuses to start on any uncommitted
# contract/shared file, hands cmux the confirmed agent mapping to scaffold
# worker prompts, then writes the run-state manifest.json that everything
# else in this skill (event.sh, board.sh, validate-run-state.sh) reads.
#
# Usage:
#   init-run.sh PLAN RUN_DIR CWD ORCH_SURFACE
#
# PLAN describes the project rooted at CWD — every relative path in the plan
# (Affected files, contract path, shared_read_only entries) is resolved
# against CWD, so this script validates the plan FROM CWD, matching how a
# human would run validate-plan.sh from the project root.
#
# Design note (not spelled out in the plan's interface list): cmux's own
# prepare-run.sh writes ITS OWN manifest.json, shaped for cmux's launch
# bookkeeping (surface_ref, prompt/result files, worker_pane_ref) — a shape
# that doesn't fit schemas/run-state.schema.json's `manifest` definition
# (additionalProperties: false, and a different `workers[]` shape). Rather
# than force those two shapes into one file, cmux is pointed at
# `${RUN_DIR}/cmux/` as its own run directory, and this script writes the
# schema-conformant `${RUN_DIR}/manifest.json` separately. A later task that
# needs a worker's surface_ref reads `${RUN_DIR}/cmux/manifest.json`; the
# prompt/result files it writes live at predictable `${RUN_DIR}/cmux/
# worker-<lane>.prompt.md` paths by cmux's own convention.

set -eufo pipefail

if [ $# -lt 4 ]; then
  echo "Usage: init-run.sh PLAN RUN_DIR CWD ORCH_SURFACE" >&2
  exit 2
fi

PLAN_ARG="$1"
RUN_DIR="$2"
CWD="$3"
ORCH_SURFACE="$4"

[ -f "$PLAN_ARG" ] || {
  echo "init-run.sh: missing plan file: $PLAN_ARG" >&2
  exit 1
}
[ -d "$CWD" ] || {
  echo "init-run.sh: no such CWD: $CWD" >&2
  exit 1
}
git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "init-run.sh: CWD is not a git repository: $CWD" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "init-run.sh: jq required" >&2
  exit 2
}

# Canonicalize PLAN to an absolute path up front — everything after this
# point (including cd'ing into CWD to validate) must still be able to find it.
PLAN_DIR_ABS="$(cd "$(dirname "$PLAN_ARG")" && pwd)"
PLAN="${PLAN_DIR_ABS}/$(basename "$PLAN_ARG")"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEEP_PLAN_SCRIPTS="$(cd "${SCRIPT_DIR}/../../deep-plan/scripts" && pwd)"
CMUX_SCRIPTS="$(cd "${SCRIPT_DIR}/../../cmux-orchestrator/scripts" && pwd)"

# Resolve BOTH the source-tree name (executable_*) and the deployed name for
# every cross-skill script — chezmoi apply strips the `executable_` prefix
# only in the deployed tree, and this skill is exercised from both.
VALIDATE_PLAN="${DEEP_PLAN_SCRIPTS}/validate-plan.sh"
[ -f "$VALIDATE_PLAN" ] || VALIDATE_PLAN="${DEEP_PLAN_SCRIPTS}/executable_validate-plan.sh"
PARSER="${DEEP_PLAN_SCRIPTS}/plan-to-json.sh"
[ -f "$PARSER" ] || PARSER="${DEEP_PLAN_SCRIPTS}/executable_plan-to-json.sh"
PREPARE_RUN="${CMUX_SCRIPTS}/prepare-run.sh"
[ -f "$PREPARE_RUN" ] || PREPARE_RUN="${CMUX_SCRIPTS}/executable_prepare-run.sh"

WORKER_PROMPT="${SKILL_DIR}/templates/worker-system-prompt.txt"
[ -f "$WORKER_PROMPT" ] || {
  echo "init-run.sh: missing worker system prompt: $WORKER_PROMPT" >&2
  exit 2
}

# ─── Step 1: validate the plan, from the project root it describes ────────

VALIDATE_JSON=$(cd "$CWD" && "$VALIDATE_PLAN" "$PLAN" --root --json) || {
  echo "init-run.sh: refusing to start — plan failed validate-plan.sh --root:" >&2
  echo "$VALIDATE_JSON" | jq -r '.[] | select(.status=="fail") | "  - " + .item + ": " + .detail' >&2
  exit 1
}

# ─── Step 2: parse the plan (own source of truth, not re-derived by hand) ──

PLAN_JSON=$("$PARSER" "$PLAN") || {
  echo "init-run.sh: plan-to-json.sh could not parse $PLAN" >&2
  exit 1
}

MODE=$(jq -r '.mode // ""' <<<"$PLAN_JSON")
[ "$MODE" = "parallel" ] || {
  echo "init-run.sh: refusing to start — plan mode is '${MODE}', not 'parallel' (deep-execute only runs parallel plans)" >&2
  exit 1
}
CONTRACT_NULL=$(jq -r '.contract == null' <<<"$PLAN_JSON")
[ "$CONTRACT_NULL" = "false" ] || {
  echo "init-run.sh: refusing to start — plan declares no API contract (required for a parallel run)" >&2
  exit 1
}

ORCH_LANE=$(jq -r '.orchestrator_lane // ""' <<<"$PLAN_JSON")
CONTRACT_VERSION=$(jq -r '.contract.version' <<<"$PLAN_JSON")
CONTRACT_PATH=$(jq -r '.contract.path' <<<"$PLAN_JSON")
CONTRACT_KIND=$(jq -r '.contract.kind' <<<"$PLAN_JSON")
CONTRACT_VALIDATION=$(jq -r '.contract.validation_command' <<<"$PLAN_JSON")

SHARED_ARR=()
while IFS= read -r s; do
  [ -z "$s" ] && continue
  SHARED_ARR+=("$s")
done < <(jq -r '.shared_read_only[]' <<<"$PLAN_JSON")

# ─── Step 3: refuse to continue if the contract or any shared file is ─────
# uncommitted — this run's baseline_commit is HEAD, and any lane worker's
# view of "the contract" comes from that commit, not the working tree.

UNCOMMITTED=""
MISSING=""
for p in "$CONTRACT_PATH" "${SHARED_ARR[@]}"; do
  [ -f "${CWD}/${p}" ] || MISSING="${MISSING}${MISSING:+, }${p}"
  DIRTY=$(git -C "$CWD" status --porcelain -- "$p" 2>/dev/null)
  [ -z "$DIRTY" ] || UNCOMMITTED="${UNCOMMITTED}${UNCOMMITTED:+, }${p}"
done
[ -z "$MISSING" ] || {
  echo "init-run.sh: refusing to start — missing on disk: $MISSING" >&2
  exit 1
}
[ -z "$UNCOMMITTED" ] || {
  echo "init-run.sh: refusing to start — uncommitted: $UNCOMMITTED" >&2
  exit 1
}

# ─── Step 4: confirmed agent mapping -> cmux worker specs ──────────────────
# agents.allowlist lines are "<model> <effort>" for claude (opus/sonnet) or
# "codex <model> <effort>" for codex — the exact grammar validate-plan.sh's
# lane-agent-in-allowlist already checked the plan's `agent` column against,
# so no further validation is needed here, only re-shaping into
# launch-workers.sh's `name:runner:model@effort` spec grammar.
agent_to_spec() {
  local lane="$1" agent="$2" a b c runner model effort
  read -r a b c <<<"$agent"
  if [ "$a" = "codex" ]; then
    runner="codex"
    model="$b"
    effort="$c"
  else
    runner="claude"
    model="$a"
    effort="$b"
  fi
  printf '%s:%s:%s@%s' "$lane" "$runner" "$model" "$effort"
}

WORKER_SPECS=()
WORKER_LANES=()
while IFS=$'\t' read -r lname lagent; do
  [ -z "$lname" ] && continue
  WORKER_LANES+=("$lname")
  WORKER_SPECS+=("$(agent_to_spec "$lname" "$lagent")")
done < <(jq -r --arg orch "$ORCH_LANE" '.lanes[] | select(.name != $orch) | "\(.name)\t\(.agent)"' <<<"$PLAN_JSON")

[ ${#WORKER_SPECS[@]} -ge 1 ] || {
  echo "init-run.sh: refusing to start — no non-orchestrator lanes to launch" >&2
  exit 1
}

# ─── Step 5: cmux scaffolding (its own manifest.json, kept out of ours) ────

mkdir -p "$RUN_DIR"
CMUX_DIR="${RUN_DIR}/cmux"
mkdir -p "$CMUX_DIR"
"$PREPARE_RUN" "$CMUX_DIR" "$CWD" "$ORCH_SURFACE" --system-prompt "$WORKER_PROMPT" "${WORKER_SPECS[@]}"

# ─── Step 6: run-state scaffolding — events log, per-lane reply + files log ─
# Never clobbers state a previous init-run.sh call already created, so a
# second call (e.g. to add a lane) is safe.

[ -f "${RUN_DIR}/events.jsonl" ] || : >"${RUN_DIR}/events.jsonl"
for lane in "${WORKER_LANES[@]}"; do
  mkdir -p "${RUN_DIR}/lanes/${lane}"
  [ -f "${RUN_DIR}/lanes/${lane}/reply.md" ] || : >"${RUN_DIR}/lanes/${lane}/reply.md"
  [ -f "${RUN_DIR}/worker-${lane}.files.txt" ] || : >"${RUN_DIR}/worker-${lane}.files.txt"
done

# ─── Step 7: contract sha256 + baseline commit ─────────────────────────────

if command -v sha256sum >/dev/null 2>&1; then
  SHA_CMD=(sha256sum)
else
  SHA_CMD=(shasum -a 256)
fi
CONTRACT_SHA=$("${SHA_CMD[@]}" "${CWD}/${CONTRACT_PATH}" | awk '{print $1}')
BASELINE_COMMIT=$(git -C "$CWD" rev-parse HEAD)

# ─── Step 8: assemble manifest.json (schemas/run-state.schema.json shape) ──

WORKERS_JSON="[]"
for i in "${!WORKER_LANES[@]}"; do
  lane="${WORKER_LANES[$i]}"
  spec="${WORKER_SPECS[$i]}"
  runner="${spec#*:}"
  runner="${runner%%:*}"
  effort="${spec##*@}"
  task=$(jq -r --arg l "$lane" '[.tasks[] | select(.lane == $l)][0].title // empty' <<<"$PLAN_JSON")

  if [ -n "$task" ]; then
    ENTRY=$(jq -n --arg id "$lane" --arg lane "$lane" --arg task "$task" \
      --arg runner "$runner" --arg effort "$effort" \
      '{id:$id, lane:$lane, task:$task, runner:$runner, effort:$effort, status:"pending"}')
  else
    ENTRY=$(jq -n --arg id "$lane" --arg lane "$lane" \
      --arg runner "$runner" --arg effort "$effort" \
      '{id:$id, lane:$lane, runner:$runner, effort:$effort, status:"pending"}')
  fi
  WORKERS_JSON=$(jq -c --argjson e "$ENTRY" '. + [$e]' <<<"$WORKERS_JSON")
done

SHARED_JSON=$(jq -n '$ARGS.positional' --args "${SHARED_ARR[@]}")

jq -n \
  --arg run_id "$(basename "$RUN_DIR")" \
  --arg plan_path "$PLAN" \
  --arg cwd "$CWD" \
  --arg baseline_commit "$BASELINE_COMMIT" \
  --argjson round 0 \
  --argjson max_rounds 3 \
  --arg orch_surface "$ORCH_SURFACE" \
  --arg cv "$CONTRACT_VERSION" --arg cp "$CONTRACT_PATH" --arg ck "$CONTRACT_KIND" \
  --arg cval "$CONTRACT_VALIDATION" --arg csha "$CONTRACT_SHA" \
  --argjson shared "$SHARED_JSON" \
  --argjson workers "$WORKERS_JSON" \
  '{
    schema_version: "1.0.0",
    run_id: $run_id,
    plan_path: $plan_path,
    cwd: $cwd,
    baseline_commit: $baseline_commit,
    round: $round,
    max_rounds: $max_rounds,
    orchestrator_surface: $orch_surface,
    contract: {version:$cv, path:$cp, kind:$ck, validation_command:$cval, sha256:$csha},
    shared_read_only: $shared,
    workers: $workers
  }' >"${RUN_DIR}/manifest.json"

echo "init-run.sh: wrote ${RUN_DIR}/manifest.json for $(basename "$RUN_DIR") (${#WORKER_LANES[@]} lane(s), baseline ${BASELINE_COMMIT})" >&2
