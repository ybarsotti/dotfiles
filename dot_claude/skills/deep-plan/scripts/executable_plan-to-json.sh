#!/usr/bin/env bash
# plan-to-json.sh — canonical parser: reads a deep-plan plan.md and prints one
# JSON object describing its execution shape, API contract, affected files,
# and lane-tagged tasks. This is the single source of truth for lane
# ownership — validate-plan.sh and the deep-execute runtime both read plan
# structure through this script; never re-derive it by hand elsewhere.
#
# Usage:
#   plan-to-json.sh <plan.md>
#
# Missing `## Execution shape` / `## API contract` sections degrade
# gracefully (mode/orchestrator_lane/contract null, lanes/shared_read_only
# empty, task.lane null) so older, serial-only plans still parse. Only a
# missing file, or a missing jq, is fatal (exit 2).

set -eufo pipefail

PLAN="$1"
[ -f "$PLAN" ] || {
  echo "plan-to-json.sh: missing $PLAN" >&2
  exit 2
}
command -v jq >/dev/null 2>&1 || {
  echo "plan-to-json.sh: jq required" >&2
  exit 2
}

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
LANES_NDJSON="${SCRATCH}/lanes.ndjson"
TASKS_NDJSON="${SCRATCH}/tasks.ndjson"
: >"$LANES_NDJSON"
: >"$TASKS_NDJSON"

section_body() {
  awk -v h="$1" '$0 == "## " h {inside=1; next} /^## / {inside=0} inside' "$PLAN"
}

# strip_cell: trims whitespace, strips backticks, turns <br> into newlines,
# and unescapes \| — the cleanup every table/bullet cell needs before it
# becomes a JSON string or a jq -Rsc split.
strip_cell() {
  printf '%s' "$1" | awk '
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      gsub(/`/, "")
      gsub(/<br>/, "\n")
      gsub(/\\\|/, "|")
      print
    }'
}

# cell_array CELL — a stripped, possibly multi-line cell -> compact JSON array.
cell_array() {
  strip_cell "$1" | jq -Rsc 'split("\n") | map(select(length > 0))'
}

# cell_string CELL — a stripped scalar cell -> JSON string.
cell_string() {
  jq -Rn --arg v "$(strip_cell "$1")" '$v'
}

# ─── Execution shape ────────────────────────────────────────────────────────

EXEC_BODY=$(section_body "Execution shape")

MODE=$(printf '%s\n' "$EXEC_BODY" | awk -F'`' '/^- Mode:/ {print $2; exit}')
ORCHESTRATOR_LANE=$(printf '%s\n' "$EXEC_BODY" | awk -F'`' '/^- Orchestrator lane:/ {print $2; exit}')
SHARED_READ_ONLY_JSON=$(printf '%s\n' "$EXEC_BODY" | awk -F'`' '
  /^- Shared,/ { for (i = 2; i <= NF; i += 2) print $i }
' | jq -Rsc 'split("\n") | map(select(length > 0))')

MODE_JSON=null
[ -n "$MODE" ] && MODE_JSON=$(cell_string "$MODE")
ORCHESTRATOR_LANE_JSON=null
[ -n "$ORCHESTRATOR_LANE" ] && ORCHESTRATOR_LANE_JSON=$(cell_string "$ORCHESTRATOR_LANE")

LANES=$(printf '%s\n' "$EXEC_BODY" | awk -F'|' '
  /^\|[[:space:]]*lane[[:space:]]*\|/ {table=1; next}
  table && /^\|[-[:space:]]+\|/ {next}
  table && /^\|/ {
    for (i=2; i<=9; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $2,$3,$4,$5,$6,$7,$8,$9
    next
  }
  table {exit}')

while IFS=$'\t' read -r l_name l_scope l_owns l_must l_agent l_test l_mock l_deps; do
  [ -z "$l_name" ] && continue

  DEPS_JSON="[]"
  [ "$(strip_cell "$l_deps")" != "none" ] && DEPS_JSON=$(cell_array "$l_deps")
  MOCK_JSON=null
  [ "$(strip_cell "$l_mock")" != "none" ] && MOCK_JSON=$(cell_string "$l_mock")

  jq -n \
    --arg name "$(strip_cell "$l_name")" \
    --arg scope "$(strip_cell "$l_scope")" \
    --argjson owns "$(cell_array "$l_owns")" \
    --argjson must_not_touch "$(cell_array "$l_must")" \
    --arg agent "$(strip_cell "$l_agent")" \
    --arg test_command "$(strip_cell "$l_test")" \
    --argjson mock_command "$MOCK_JSON" \
    --argjson depends_on "$DEPS_JSON" \
    '{name:$name, scope:$scope, owns:$owns, must_not_touch:$must_not_touch,
      agent:$agent, test_command:$test_command, mock_command:$mock_command,
      depends_on:$depends_on}' >>"$LANES_NDJSON"
done <<<"$LANES"

LANES_JSON=$(jq -sc '.' <"$LANES_NDJSON")

# ─── API contract ───────────────────────────────────────────────────────────

# Stop at the first `### ` subheading: some plans (this pipeline's own) nest an
# illustrative example table under the contract section for future plan authors —
# that documentation is not this plan's own declared contract.
CONTRACT_BODY=$(section_body "API contract" | awk '/^### / {exit} {print}')

CONTRACT_VERSION=$(printf '%s\n' "$CONTRACT_BODY" | awk -F'`' '/^- Contract version:/ {print $2; exit}')
CONTRACT_PATH=$(printf '%s\n' "$CONTRACT_BODY" | awk -F'`' '/^- Materialized contract:/ {print $2; exit}')
CONTRACT_KIND=$(printf '%s\n' "$CONTRACT_BODY" | awk -F'`' '/^- Contract kind:/ {print $2; exit}')
CONTRACT_VALIDATION=$(printf '%s\n' "$CONTRACT_BODY" | awk -F'`' '/^- Contract validation command:/ {print $2; exit}')

ENDPOINT_ROWS=$(printf '%s\n' "$CONTRACT_BODY" | awk -F'|' '
  /^\|[[:space:]]*endpoint[[:space:]]*\|/ {table=1; next}
  table && /^\|[-[:space:]]+\|/ {next}
  table && /^\|/ {
    for (i=2; i<=7; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
    printf "%s\t%s\t%s\t%s\t%s\t%s\n", $2,$3,$4,$5,$6,$7
    next
  }
  table {exit}')

ENDPOINTS_NDJSON="${SCRATCH}/endpoints.ndjson"
: >"$ENDPOINTS_NDJSON"
while IFS=$'\t' read -r e_id e_method e_path e_status e_req e_resp; do
  [ -z "$e_id" ] && continue
  jq -n \
    --arg endpoint "$(strip_cell "$e_id")" \
    --arg method "$(strip_cell "$e_method")" \
    --arg full_path "$(strip_cell "$e_path")" \
    --arg status_codes "$(strip_cell "$e_status")" \
    --arg request_shape "$(strip_cell "$e_req")" \
    --arg response_shape "$(strip_cell "$e_resp")" \
    '{endpoint:$endpoint, method:$method, full_path:$full_path,
      status_codes:$status_codes, request_shape:$request_shape,
      response_shape:$response_shape}' >>"$ENDPOINTS_NDJSON"
done <<<"$ENDPOINT_ROWS"
ENDPOINTS_JSON=$(jq -sc '.' <"$ENDPOINTS_NDJSON")

CONTRACT_JSON=null
if [ -n "$CONTRACT_VERSION$CONTRACT_PATH$CONTRACT_KIND$CONTRACT_VALIDATION" ]; then
  CONTRACT_JSON=$(jq -n \
    --arg version "$(strip_cell "$CONTRACT_VERSION")" \
    --arg path "$(strip_cell "$CONTRACT_PATH")" \
    --arg kind "$(strip_cell "$CONTRACT_KIND")" \
    --arg validation_command "$(strip_cell "$CONTRACT_VALIDATION")" \
    --argjson endpoints "$ENDPOINTS_JSON" \
    '{version:$version, path:$path, kind:$kind,
      validation_command:$validation_command, endpoints:$endpoints}')
fi

# ─── Affected files ─────────────────────────────────────────────────────────

AFFECTED_JSON=$(section_body "Affected files" |
  awk -F'`' '/^- / && NF >= 3 { print $2 }' |
  jq -Rsc 'split("\n") | map(select(length > 0))')

# ─── Tasks (`### Task N:` blocks, tagged by the `**Lane:**` line under them) ─

TASKS_RAW=$(awk '
  function flush() {
    if (num == "") return
    gsub(/\t/, " ", title)
    printf "%s\t%s\t%s\t%s\t%s\t%s\n", num, title, lane, create, modify, verify
  }
  # Skip fenced code blocks: task steps often show illustrative
  # `**Lane:**`/`- Create:`-shaped example lines inside ``` fences that must
  # not be mistaken for the enclosing task metadata.
  /^```/ { infence = !infence; next }
  infence { next }
  /^### Task [0-9]+:/ {
    flush()
    num = $0; sub(/^### Task /, "", num); sub(/:.*/, "", num)
    title = $0; sub(/^### Task [0-9]+: /, "", title)
    lane = ""; create = ""; modify = ""; verify = ""
    next
  }
  /^## / && num != "" { flush(); num = ""; next }
  num != "" && lane == "" && /^\*\*Lane:\*\*/ {
    n = split($0, a, "`"); if (n >= 2) lane = a[2]
    next
  }
  num != "" && /^- Create: `/ {
    n = split($0, a, "`"); if (n >= 2) create = (create == "" ? a[2] : create "\037" a[2])
    next
  }
  num != "" && /^- Modify: `/ {
    n = split($0, a, "`"); if (n >= 2) modify = (modify == "" ? a[2] : modify "\037" a[2])
    next
  }
  num != "" && /^- Verify: `/ {
    n = split($0, a, "`"); if (n >= 2) verify = (verify == "" ? a[2] : verify "\037" a[2])
    next
  }
  END { flush() }
' "$PLAN")

# paths_to_json RAW — a \037-joined path list (as produced above) -> JSON array.
paths_to_json() {
  jq -Rn --arg s "$1" --arg sep "$(printf '\037')" \
    '$s | split($sep) | map(select(length > 0))'
}

while IFS=$'\t' read -r t_num t_title t_lane t_create t_modify t_verify; do
  [ -z "$t_num" ] && continue
  LANE_JSON=null
  [ -n "$t_lane" ] && LANE_JSON=$(jq -Rn --arg v "$t_lane" '$v')
  jq -n \
    --argjson number "$t_num" \
    --arg title "$t_title" \
    --argjson lane "$LANE_JSON" \
    --argjson create "$(paths_to_json "$t_create")" \
    --argjson modify "$(paths_to_json "$t_modify")" \
    --argjson verify "$(paths_to_json "$t_verify")" \
    '{number:$number, title:$title, lane:$lane,
      files:{create:$create, modify:$modify, verify:$verify}}' >>"$TASKS_NDJSON"
done <<<"$TASKS_RAW"

TASKS_JSON=$(jq -sc '.' <"$TASKS_NDJSON")

# ─── Assemble ────────────────────────────────────────────────────────────────

jq -n \
  --argjson mode "$MODE_JSON" \
  --argjson orchestrator_lane "$ORCHESTRATOR_LANE_JSON" \
  --argjson shared_read_only "$SHARED_READ_ONLY_JSON" \
  --argjson lanes "$LANES_JSON" \
  --argjson contract "$CONTRACT_JSON" \
  --argjson affected_files "$AFFECTED_JSON" \
  --argjson tasks "$TASKS_JSON" \
  '{mode:$mode, orchestrator_lane:$orchestrator_lane, shared_read_only:$shared_read_only,
    lanes:$lanes, contract:$contract, affected_files:$affected_files, tasks:$tasks}'
