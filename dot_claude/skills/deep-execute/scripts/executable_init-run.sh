#!/usr/bin/env bash
# init-run.sh — scaffolds a deep-execute run directory from an approved
# parallel plan, once.
#
# Usage:
#   init-run.sh PLAN RUN_DIR CWD ORCH_SURFACE [--max-rounds N]
#               [--agent LANE=AGENT]... [--dry-run]
#
#   --max-rounds N      the round cap recorded in manifest.json (default 3)
#   --agent LANE=AGENT  replaces the plan's agent for LANE; AGENT is one line of
#                       agents.allowlist, for example "codex gpt-6-sol medium"
#   --dry-run           scaffolds into a temporary directory, prints the lanes,
#                       agents, contract and expected review count, then deletes
#                       it. RUN_DIR is not touched.
#
# It validates the plan from CWD (relative plan paths resolve against the
# project root), refuses an uncommitted contract or shared file, and writes:
#
#   manifest.json               run state (schemas/run-state.schema.json)
#   status.json                 phase and start time for run-status.sh
#   events.jsonl                the empty event log
#   worker-<lane>.files.txt     the attribution log of each lane
#   lanes/<lane>/replies/       the numbered replies reply.sh publishes
#   lanes/<lane>/decisions/     the records decision.sh writes
#   launch/manifest.json        per lane: runner, model, effort, session id,
#                               brief path, task label, terminal handle
#   launch/system-prompt.txt    the shared worker rules
#   launch/worker-<lane>.prompt.md  the rendered brief of each lane
#
# A second call into the same RUN_DIR fails: a run is resumed, never
# re-initialized, because a new manifest would orphan the event history,
# the session ids and the terminal handles of the first one.
set -eufo pipefail

usage() {
  echo "Usage: init-run.sh PLAN RUN_DIR CWD ORCH_SURFACE [--max-rounds N] [--agent LANE=AGENT]... [--dry-run]" >&2
  exit 2
}
[ $# -ge 4 ] || usage

PLAN_ARG="$1"
RUN_DIR="$2"
CWD="$3"
ORCH_SURFACE="$4"
shift 4

MAX_ROUNDS=3
DRY_RUN=0
OVERRIDES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --max-rounds)
      [ $# -ge 2 ] && [[ "$2" =~ ^[1-9][0-9]*$ ]] || {
        echo "init-run.sh: --max-rounds needs a positive integer" >&2
        exit 2
      }
      MAX_ROUNDS="$2"
      shift 2
      ;;
    --agent)
      [ $# -ge 2 ] && [ "${2#*=}" != "$2" ] || {
        echo "init-run.sh: --agent needs LANE=AGENT" >&2
        exit 2
      }
      OVERRIDES+=("$2")
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    *) usage ;;
  esac
done

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

if [ "$DRY_RUN" -eq 1 ]; then
  DRY_TMP=$(mktemp -d)
  trap 'rm -rf "$DRY_TMP"' EXIT
  RUN_DIR="${DRY_TMP}/run"
elif [ -f "${RUN_DIR}/manifest.json" ]; then
  echo "init-run.sh: refusing to start — ${RUN_DIR} is already a run; resume it with /deep-execute --resume ${RUN_DIR}" >&2
  exit 1
fi

PLAN_DIR_ABS="$(cd "$(dirname "$PLAN_ARG")" && pwd)"
PLAN="${PLAN_DIR_ABS}/$(basename "$PLAN_ARG")"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEEP_PLAN_SCRIPTS="$(cd "${SCRIPT_DIR}/../../deep-plan/scripts" && pwd)"

# script DIR NAME — the deployed name, else the chezmoi source name (executable_*).
script() {
  local dir="$1" name="$2"
  if [ -f "${dir}/${name}" ]; then printf '%s' "${dir}/${name}"; else printf '%s' "${dir}/executable_${name}"; fi
}
VALIDATE_PLAN=$(script "$DEEP_PLAN_SCRIPTS" validate-plan.sh)
PARSER=$(script "$DEEP_PLAN_SCRIPTS" plan-to-json.sh)
PLAN_STAMP=$(script "${SKILL_DIR}/../_shared" plan-stamp.sh)
EVENT_SH=$(script "$SCRIPT_DIR" event.sh)
BOARD_SH=$(script "$SCRIPT_DIR" board.sh)
DECISION_SH=$(script "$SCRIPT_DIR" decision.sh)
WORKER_PROMPT="${SKILL_DIR}/templates/worker-system-prompt.txt"
BRIEF_TEMPLATE="${SKILL_DIR}/templates/worker-brief.md"
ALLOWLIST="${SKILL_DIR}/agents.allowlist"

# ─── Step 1: validate the plan, from the project root it describes ────────

VALIDATE_JSON=$(cd "$CWD" && "$VALIDATE_PLAN" "$PLAN" --root --json) || {
  echo "init-run.sh: refusing to start — plan failed validate-plan.sh --root:" >&2
  echo "$VALIDATE_JSON" | jq -r '.[] | select(.status=="fail") | "  - " + .item + ": " + .detail' >&2
  exit 1
}

# A stamped plan must still be the approved text (_shared/spec-evidence.md
# section 2). An unstamped plan only warns: older plans and fixtures have none.
if [ -f "${PLAN}.approved" ]; then
  bash "$PLAN_STAMP" check "$PLAN" >/dev/null || {
    echo "init-run.sh: refusing to start — the plan changed after its approval (plan-stamp.sh check)" >&2
    exit 1
  }
else
  echo "init-run.sh: warning — $PLAN has no approval stamp" >&2
fi

# ─── Step 2: parse the plan ────────────────────────────────────────────────

PLAN_JSON=$("$PARSER" "$PLAN") || {
  echo "init-run.sh: plan-to-json.sh could not parse $PLAN" >&2
  exit 1
}
[ "$(jq -r '.mode // ""' <<<"$PLAN_JSON")" = "parallel" ] || {
  echo "init-run.sh: refusing to start — plan mode is not 'parallel' (deep-execute only runs parallel plans)" >&2
  exit 1
}
[ "$(jq -r '.contract == null' <<<"$PLAN_JSON")" = "false" ] || {
  echo "init-run.sh: refusing to start — plan declares no API contract (required for a parallel run)" >&2
  exit 1
}

ORCH_LANE=$(jq -r '.orchestrator_lane // ""' <<<"$PLAN_JSON")
CONTRACT_PATH=$(jq -r '.contract.path' <<<"$PLAN_JSON")

SHARED_ARR=()
while IFS= read -r s; do
  [ -n "$s" ] && SHARED_ARR+=("$s")
done < <(jq -r '.shared_read_only[]' <<<"$PLAN_JSON")

# ─── Step 3: the contract and shared files must be committed ──────────────

UNCOMMITTED=""
MISSING=""
for p in "$CONTRACT_PATH" "${SHARED_ARR[@]}"; do
  [ -f "${CWD}/${p}" ] || MISSING="${MISSING}${MISSING:+, }${p}"
  [ -z "$(git -C "$CWD" status --porcelain -- "$p" 2>/dev/null)" ] || UNCOMMITTED="${UNCOMMITTED}${UNCOMMITTED:+, }${p}"
done
[ -z "$MISSING" ] || {
  echo "init-run.sh: refusing to start — missing on disk: $MISSING" >&2
  exit 1
}
[ -z "$UNCOMMITTED" ] || {
  echo "init-run.sh: refusing to start — uncommitted: $UNCOMMITTED" >&2
  exit 1
}

# ─── Step 4: the agent of each lane — the plan's, unless overridden ───────
# Each allowlist line is "<model> <effort>" for claude or "codex <model>
# <effort>". validate-plan.sh already checked the plan's own column.

WORKER_LANES=()
while IFS= read -r l; do
  [ -n "$l" ] && WORKER_LANES+=("$l")
done < <(jq -r --arg orch "$ORCH_LANE" '.lanes[] | select(.name != $orch) | .name' <<<"$PLAN_JSON")
[ ${#WORKER_LANES[@]} -ge 1 ] || {
  echo "init-run.sh: refusing to start — no non-orchestrator lanes to launch" >&2
  exit 1
}

AGENTS_JSON=$(jq -c --arg orch "$ORCH_LANE" '[.lanes[] | select(.name != $orch) | {key: .name, value: .agent}] | from_entries' <<<"$PLAN_JSON")
for o in "${OVERRIDES[@]+"${OVERRIDES[@]}"}"; do
  o_lane="${o%%=*}"
  o_agent="${o#*=}"
  jq -e --arg l "$o_lane" 'has($l)' <<<"$AGENTS_JSON" >/dev/null || {
    echo "init-run.sh: --agent names '${o_lane}', which is not a worker lane of the plan" >&2
    exit 1
  }
  grep -qxF -- "$o_agent" "$ALLOWLIST" || {
    echo "init-run.sh: --agent '${o_agent}' is not a line of ${ALLOWLIST}" >&2
    exit 1
  }
  AGENTS_JSON=$(jq -c --arg l "$o_lane" --arg a "$o_agent" '.[$l] = $a' <<<"$AGENTS_JSON")
done

new_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

# ─── Step 5: run directory, briefs and launch manifest ─────────────────────

LAUNCH_DIR="${RUN_DIR}/launch"
mkdir -p "$LAUNCH_DIR"
: >"${RUN_DIR}/events.jsonl"
cp "$WORKER_PROMPT" "${LAUNCH_DIR}/system-prompt.txt"

# md_list JSON_ARRAY — "`a`, `b`", or "none".
md_list() { jq -r 'if length == 0 then "none" else map("`" + . + "`") | join(", ") end' <<<"$1"; }

LAUNCH_WORKERS="[]"
RUN_WORKERS="[]"
for lane in "${WORKER_LANES[@]}"; do
  mkdir -p "${RUN_DIR}/lanes/${lane}/decisions" "${RUN_DIR}/lanes/${lane}/replies"
  : >"${RUN_DIR}/worker-${lane}.files.txt"

  read -r a b c <<<"$(jq -r --arg l "$lane" '.[$l]' <<<"$AGENTS_JSON")"
  if [ "$a" = "codex" ]; then runner=codex model="$b" effort="$c"; else runner=claude model="$a" effort="$b"; fi

  LANE_JSON=$(jq -c --arg l "$lane" '.lanes[] | select(.name == $l)' <<<"$PLAN_JSON")
  TASKS_JSON=$(jq -c --arg l "$lane" '[.tasks[] | select(.lane == $l)
    | {label: ("\(.number) - \(.title)" | .[0:50]),
       files: ([.files | objects | .[]?[]?] + [.files | arrays | .[]?] | unique)}]' <<<"$PLAN_JSON")
  first_task=$(jq -r '.[0].label // empty' <<<"$TASKS_JSON")
  [ -n "$first_task" ] || first_task="lane ${lane}"
  subplan="${PLAN_DIR_ABS}/subplans/${lane}.md"
  if [ -f "$subplan" ]; then subplan="\`${subplan}\`"; else subplan="none"; fi

  VARS=$(jq -n \
    --arg LANE "$lane" --arg RUN_DIR "$RUN_DIR" --arg CWD "$CWD" --arg PLAN "$PLAN" \
    --arg SUBPLAN "$subplan" --arg EVENT_SH "$EVENT_SH" --arg BOARD_SH "$BOARD_SH" \
    --arg DECISION_SH "$DECISION_SH" \
    --arg SCOPE "$(jq -r '.scope // "No scope line in the plan."' <<<"$LANE_JSON")" \
    --arg OWNS "$(md_list "$(jq -c '.owns' <<<"$LANE_JSON")")" \
    --arg MUST_NOT_TOUCH "$(md_list "$(jq -c '.must_not_touch // []' <<<"$LANE_JSON")")" \
    --arg DEPENDS_ON "$(md_list "$(jq -c '.depends_on // []' <<<"$LANE_JSON")")" \
    --arg TEST_COMMAND "$(jq -r '.test_command // ""' <<<"$LANE_JSON")" \
    --arg CONTRACT_PATH "$CONTRACT_PATH" \
    --arg CONTRACT_VERSION "$(jq -r '.contract.version' <<<"$PLAN_JSON")" \
    --arg CONTRACT_KIND "$(jq -r '.contract.kind' <<<"$PLAN_JSON")" \
    --arg SHARED "$(md_list "$(jq -c '.shared_read_only' <<<"$PLAN_JSON")")" \
    --arg TASKS "$(jq -r 'map("- `\(.label)`" + (if (.files | length) > 0 then " — files: " + (.files | map("`" + . + "`") | join(", ")) else "" end)) | join("\n")' <<<"$TASKS_JSON")" \
    '$ARGS.named')
  BRIEF="${LAUNCH_DIR}/worker-${lane}.prompt.md"
  # split/join replaces literally: no regex, no `&` expansion, whatever the plan text holds.
  jq -rn --rawfile tpl "$BRIEF_TEMPLATE" --argjson vars "$VARS" \
    'reduce ($vars | to_entries[]) as $e ($tpl; split("{{" + $e.key + "}}") | join($e.value))' >"$BRIEF"
  if grep -qE '\{\{[A-Z_]+\}\}' "$BRIEF"; then
    echo "init-run.sh: the brief of lane ${lane} has an unresolved placeholder: ${BRIEF}" >&2
    exit 1
  fi

  LAUNCH_WORKERS=$(jq -c --arg n "$lane" --arg r "$runner" --arg m "$model" --arg e "$effort" \
    --arg s "$(new_uuid)" --arg p "$BRIEF" --arg t "$first_task" \
    '. + [{name: $n, runner: $r, model: $m, effort: $e, session_id: $s, prompt_file: $p, task: $t, block_ref: null}]' \
    <<<"$LAUNCH_WORKERS")
  RUN_WORKERS=$(jq -c --arg l "$lane" --arg r "$runner" --arg e "$effort" \
    --arg t "$(jq -r --arg l "$lane" '[.tasks[] | select(.lane == $l)][0].title // empty' <<<"$PLAN_JSON")" \
    '. + [{id: $l, lane: $l, runner: $r, effort: $e, status: "pending"} + (if $t == "" then {} else {task: $t} end)]' \
    <<<"$RUN_WORKERS")
done
jq -n --argjson w "$LAUNCH_WORKERS" '{workers: $w}' >"${LAUNCH_DIR}/manifest.json"

# ─── Step 6: manifest.json and status.json ────────────────────────────────

if command -v sha256sum >/dev/null 2>&1; then SHA_CMD=(sha256sum); else SHA_CMD=(shasum -a 256); fi
CONTRACT_SHA=$("${SHA_CMD[@]}" "${CWD}/${CONTRACT_PATH}" | awk '{print $1}')
BASELINE_COMMIT=$(git -C "$CWD" rev-parse HEAD)

jq -n \
  --arg run_id "$(basename "$RUN_DIR")" --arg plan_path "$PLAN" --arg cwd "$CWD" \
  --arg baseline "$BASELINE_COMMIT" --argjson max_rounds "$MAX_ROUNDS" \
  --arg orch_surface "$ORCH_SURFACE" --arg csha "$CONTRACT_SHA" \
  --argjson plan "$PLAN_JSON" --argjson shared "$(jq -c '.shared_read_only' <<<"$PLAN_JSON")" \
  --argjson workers "$RUN_WORKERS" \
  '{
    schema_version: "1.0.0",
    run_id: $run_id,
    plan_path: $plan_path,
    cwd: $cwd,
    baseline_commit: $baseline,
    checkpoint_commit: $baseline,
    round: 1,
    max_rounds: $max_rounds,
    orchestrator_surface: $orch_surface,
    contract: ($plan.contract | {version, path, kind, validation_command} + {sha256: $csha}),
    shared_read_only: $shared,
    workers: $workers
  }' >"${RUN_DIR}/manifest.json"

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n --arg task_label "$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || basename "$CWD")" \
  --arg started "$NOW" --arg orch "$ORCH_LANE" \
  '{schema_version:"1.0.0", task_label:$task_label, started_at:$started,
    phase:"execution", phase_started_at:$started, orchestrator_lane:$orch}' \
  >"${RUN_DIR}/status.json"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry run: nothing was written outside a temporary directory"
  echo "contract: ${CONTRACT_PATH} $(jq -r '.contract.version' <<<"$PLAN_JSON")"
  jq -r '.workers[] | "lane \(.name): \(.runner) \(.model) \(.effort) — first task \(.task)"' "${LAUNCH_DIR}/manifest.json"
  echo "rounds: up to ${MAX_ROUNDS}"
  echo "reviews: up to $((MAX_ROUNDS + 1)) /deep-review runs (one per round, one over the whole run)"
  exit 0
fi

echo "init-run.sh: wrote ${RUN_DIR}/manifest.json for $(basename "$RUN_DIR") (${#WORKER_LANES[@]} lane(s), baseline ${BASELINE_COMMIT})" >&2
