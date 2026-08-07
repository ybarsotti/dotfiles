#!/usr/bin/env bash
# Tests for run-viewer.py, the read-only live viewer over a /deep-execute run
# directory. The assertions that earn their keep are the ones covering things
# a reader cannot eyeball: that the lane-status fold matches board.sh's
# sort-by-ts rather than "last line wins", that a malformed line cannot take
# the endpoint down, and that a run id from the URL cannot escape --runs-dir.
set -eufo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
# shellcheck source=/dev/null
. "${ROOT}/dot_claude/skills/_shared/executable_assert.sh"

# Both the source-tree name and the deployed one, so the suite works before and
# after `chezmoi apply` strips the executable_ prefix.
VIEWER="${ROOT}/dot_claude/skills/deep-execute/scripts/executable_run-viewer.py"
[ -f "$VIEWER" ] || VIEWER="${ROOT}/dot_claude/skills/deep-execute/scripts/run-viewer.py"
EVENT="${ROOT}/dot_claude/skills/deep-execute/scripts/executable_event.sh"
[ -f "$EVENT" ] || EVENT="${ROOT}/dot_claude/skills/deep-execute/scripts/event.sh"

# The LaunchAgent calls /usr/bin/python3 by absolute path, so that is the
# interpreter the syntax gate must use. PATH python3 is a different, newer
# build here; parsing under it would pass and still ship a broken agent.
PY=/usr/bin/python3
[ -x "$PY" ] || PY=$(command -v python3)

WORK=$(mktemp -d)
RUNS="${WORK}/runs"
VIEWER_PID=""
cleanup() {
  [ -n "$VIEWER_PID" ] && kill "$VIEWER_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

# ─── Fixtures ─────────────────────────────────────────────────────────────

mkdir -p "${RUNS}/demo/lanes/backend/decisions"
cat >"${RUNS}/demo/manifest.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "run_id": "demo",
  "plan_path": "/tmp/plan.md",
  "cwd": "/tmp/repo",
  "baseline_commit": "0123456789abcdef0123456789abcdef01234567",
  "round": 2,
  "max_rounds": 3,
  "orchestrator_surface": "surface:test",
  "contract": {
    "version": "1.2.0",
    "path": "contract.schema.json",
    "kind": "json-schema",
    "validation_command": "jq -e .",
    "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
  },
  "shared_read_only": ["contract.schema.json"],
  "workers": [
    {"id":"backend","lane":"backend","task":"Model","runner":"claude","effort":"high","status":"pending"},
    {"id":"frontend","lane":"frontend","task":"UI","runner":"codex","effort":"medium","status":"pending"}
  ]
}
JSON

# The backend lane's LAST-APPENDED line carries an EARLIER ts than the line
# before it. "last line wins" would report progress; board.sh sorts by ts and
# reports done. This fixture is the whole point of the fold assertion.
cat >"${RUNS}/demo/events.jsonl" <<'JSON'
{"ts":"2026-08-07T10:00:00Z","lane":"backend","task":"Model","type":"task_start","msg":"starting"}
{"ts":"2026-08-07T10:00:30Z","lane":"backend","task":"Model","type":"done","msg":"finished"}
{"ts":"2026-08-07T10:00:10Z","lane":"backend","task":"Model","type":"progress","msg":"out-of-order line"}
{"ts":"2026-08-07T10:01:00Z","lane":"frontend","task":"UI","type":"blocked","msg":"contract unclear"}
JSON

cat >"${RUNS}/demo/lanes/backend/decisions/001.json" <<'JSON'
{"id":"001","ts":"2026-08-07T10:00:20Z","lane":"backend","task":"Model",
 "kind":"decision","title":"Store totals in cents","rationale":"Float money rounds wrong.",
 "alternatives":["numeric(12,2) — still needs app-side rounding"],
 "tradeoffs":["Every read site must divide by 100"]}
JSON

# A run scaffolded but never started: manifest, no events.jsonl.
mkdir -p "${RUNS}/empty"
sed 's/"run_id": "demo"/"run_id": "empty"/' "${RUNS}/demo/manifest.json" >"${RUNS}/empty/manifest.json"

# Three ways a line can be broken, all of which must degrade to invalid_event
# rather than failing the request.
mkdir -p "${RUNS}/broken"
sed 's/"run_id": "demo"/"run_id": "broken"/' "${RUNS}/demo/manifest.json" >"${RUNS}/broken/manifest.json"
cat >"${RUNS}/broken/events.jsonl" <<'JSON'
{not json
{"ts":"2026-08-07T10:00:00Z","task":"Model","type":"done","msg":"missing lane"}
{"ts":"2026-08-07T10:00:01Z","lane":"backend","task":"Model","type":"bogus","msg":"unknown type"}
{"ts":"2026-08-07T10:00:02Z","lane":"backend","task":"Model","type":"done","msg":"the good one"}
JSON

# A directory without a manifest is not a run and must not be listed or served.
mkdir -p "${RUNS}/notarun"

# Marker stamped after every fixture is written and before the viewer starts,
# so the "wrote nothing" assertion at the end compares against the right
# instant. Comparing against manifest.json would flag the fixtures themselves.
touch "${WORK}/before-serving"

# ─── Start the viewer on an ephemeral port ────────────────────────────────

OUT="${WORK}/viewer.out"
"$PY" "$VIEWER" --runs-dir "$RUNS" --port 0 >"$OUT" 2>"${WORK}/viewer.err" &
VIEWER_PID=$!

BASE=""
for _ in $(seq 1 50); do
  BASE=$(head -1 "$OUT" 2>/dev/null || true)
  [ -n "$BASE" ] && break
  sleep 0.1
done
assert_eq "$([ -n "$BASE" ] && echo yes || echo no)" yes \
  "viewer prints its bound URL on stdout so tests never guess a port"

get() { curl -sS --max-time 10 "${BASE}$1"; }
code() { curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "${BASE}$1"; }

# ─── Health and the snapshot ──────────────────────────────────────────────

assert_eq "$(get /healthz)" "ok" "GET /healthz returns ok"

SNAP=$(get /api/run/demo)
assert_eq "$(jq -r '.run_id' <<<"$SNAP")" "demo" "snapshot carries run_id"
assert_eq "$(jq -r '.round' <<<"$SNAP")" "2" "snapshot carries round"
assert_eq "$(jq -r '.contract.version' <<<"$SNAP")" "1.2.0" "snapshot carries contract version"
assert_eq "$(jq -r '.lanes | length' <<<"$SNAP")" "2" "snapshot lists both lanes"
assert_eq "$(jq -r '.events | length' <<<"$SNAP")" "4" "snapshot carries every event"

# workers[].status is "pending" forever because no script updates it. Surfacing
# it on a live page would be a lie, so it must not be in the payload at all.
assert_eq "$(jq -r '[.lanes[] | has("status")] | any' <<<"$SNAP")" "false" \
  "snapshot drops workers[].status, which no script ever updates"

# The fold: sorted by ts, so the out-of-order trailing line loses to the
# earlier-appended `done`.
assert_eq "$(jq -r '.lane_status[] | select(.lane=="backend") | .status' <<<"$SNAP")" "done" \
  "lane status sorts by ts rather than taking the last appended line"
assert_eq "$(jq -r '.lane_status[] | select(.lane=="frontend") | .status' <<<"$SNAP")" "blocked" \
  "lane status reports the frontend lane as blocked"

assert_eq "$(jq -r '.decisions | length' <<<"$SNAP")" "1" "snapshot carries the decision record"
assert_eq "$(jq -r '.decisions[0].title' <<<"$SNAP")" "Store totals in cents" \
  "decision record keeps its title"
assert_eq "$(jq -r '.decisions[0].alternatives | length' <<<"$SNAP")" "1" \
  "decision record keeps the alternatives it rejected"

# ─── A run with no events yet ─────────────────────────────────────────────

EMPTY=$(get /api/run/empty)
assert_eq "$(jq -r '.events | length' <<<"$EMPTY")" "0" "a run with no events.jsonl returns no events"
assert_eq "$(jq -r '.events_file_present' <<<"$EMPTY")" "false" \
  "a missing events.jsonl is reported as absent, not as an error"
assert_eq "$(code /api/run/empty)" "200" "a run with no events.jsonl still serves 200"

# ─── Malformed lines ──────────────────────────────────────────────────────

BROKEN=$(get /api/run/broken)
assert_eq "$(code /api/run/broken)" "200" "one malformed line does not take the endpoint down"
assert_eq "$(jq -r '[.events[] | select(.type=="invalid_event")] | length' <<<"$BROKEN")" "3" \
  "each of the three broken lines surfaces as invalid_event"
assert_eq "$(jq -r '[.events[] | select(.type=="done")] | length' <<<"$BROKEN")" "1" \
  "the valid line is still parsed alongside the broken ones"

# ─── The trust boundary ───────────────────────────────────────────────────

assert_eq "$(code /api/run/nope)" "404" "an unknown run id is 404"
assert_eq "$(code /api/run/notarun)" "404" "a directory without a manifest is not a run"
assert_eq "$(code /api/run/..)" "404" "a bare .. is rejected"
assert_eq "$(code /api/run/%2e%2e%2f%2e%2e%2fetc)" "404" "an encoded traversal is rejected"
assert_eq "$(code /nope)" "404" "an unknown path is 404"

# ─── Static gates ─────────────────────────────────────────────────────────

assert_exit 0 "$PY" -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$VIEWER"

# The viewer must never write into a run directory. Nothing here should have
# changed after all those requests.
assert_eq "$(find "$RUNS" -newer "${WORK}/before-serving" | wc -l | tr -d ' ')" "0" \
  "the viewer wrote nothing into the runs directory"

assert_summary
