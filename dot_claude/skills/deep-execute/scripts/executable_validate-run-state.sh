#!/usr/bin/env bash
# validate-run-state.sh — deterministic boundary + schema validation for a
# deep-execute run directory.
#
# Usage:
#   validate-run-state.sh RUN_DIR [--json]
#
# Emits 9 records via the same `record item status detail` + `--json` + exit-1
# contract as deep-plan's validate-plan.sh: manifest-schema-valid,
# events-schema-valid, events-line-size-valid, worker-file-logs-valid,
# changed-files-owned, changed-files-attributed-once, contract-untouched,
# shared-files-untouched, baseline-diff-owned. Exit 0 iff all pass.
#
# baseline-diff-owned is the safety-critical item. The changed-file set it
# checks is the UNION of `git diff --name-only --no-renames BASELINE..HEAD`
# and `git status --porcelain=v1 --untracked-files=all`, both NUL-delimited
# so paths with spaces, tabs, unicode or renames survive intact. Workers are
# told never to run git — but one that disobeys and commits its work leaves
# a clean worktree, which a status-only check would wave through. Diffing
# against the round's baseline commit closes that hole: a commit still shows
# up in the baseline diff even once the worktree is clean again.
# changed-files-owned runs the same ownership match over `git status` alone
# (no baseline diff) as a second, faster signal — redundant by design, so a
# gap in one check's git plumbing doesn't silently become a gap in both.
#
# Lane ownership (`owns` globs) is not duplicated into manifest.json — it
# lives in the plan, and plan-to-json.sh is re-invoked here to read it, the
# same way validate-plan.sh does. The orchestrator lane is excluded from the
# ownership set entirely: it isn't a monitored cmux worker (it's the one
# running this script), so any change under its own territory mid-round is
# itself suspicious, not exempt — it correctly shows up as "unowned".

set -uo pipefail

RESULTS=()
record() {
  local item="$1" status="$2" detail="$3"
  RESULTS+=("$(jq -n --arg i "$item" --arg s "$status" --arg d "$detail" \
    '{item:$i, status:$s, detail:$d}')")
}

if [ $# -lt 1 ]; then
  echo "Usage: validate-run-state.sh RUN_DIR [--json]" >&2
  exit 2
fi
RUN_DIR="$1"
shift
JSON_OUT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON_OUT=1; shift ;;
    *)
      echo "validate-run-state.sh: unknown flag '$1'" >&2
      exit 2
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  echo "validate-run-state.sh: jq required" >&2
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEEP_PLAN_SCRIPTS="$(cd "${SCRIPT_DIR}/../../deep-plan/scripts" && pwd)"

# owns_match / owns_overlap / valid_owns_pattern — shared with validate-plan.sh
# and subplan-fanout.sh via owns-lib.sh (see that file: two hand-copies of
# this already drifted apart once). No `executable_` prefix on owns-lib.sh,
# so it deploys under the same name in both trees — no fallback needed.
# shellcheck source=/dev/null
. "${DEEP_PLAN_SCRIPTS}/owns-lib.sh"

PARSER="${DEEP_PLAN_SCRIPTS}/plan-to-json.sh"
[ -f "$PARSER" ] || PARSER="${DEEP_PLAN_SCRIPTS}/executable_plan-to-json.sh"

MANIFEST="${RUN_DIR}/manifest.json"
EVENTS="${RUN_DIR}/events.jsonl"

# ─── 1. manifest-schema-valid ──────────────────────────────────────────────
# Hand-rolled against schemas/run-state.schema.json's `manifest` definition —
# no generic JSON-Schema validator is available without a new dependency, so
# every required field, enum and additionalProperties:false boundary from
# that schema is checked explicitly here.

MANIFEST_OK=1
if [ ! -f "$MANIFEST" ] || ! jq -e . "$MANIFEST" >/dev/null 2>&1; then
  record "manifest-schema-valid" "fail" "missing or invalid JSON: $MANIFEST"
  MANIFEST_OK=0
else
  ISSUES=""
  manifest_check() {
    jq -e "$2" "$MANIFEST" >/dev/null 2>&1 || ISSUES="${ISSUES}${ISSUES:+, }$1"
  }
  manifest_check "schema_version" '.schema_version == "1.0.0"'
  manifest_check "run_id" '(.run_id | type == "string") and (.run_id | length > 0)'
  manifest_check "plan_path" '(.plan_path | type == "string") and (.plan_path | length > 0)'
  manifest_check "cwd" '(.cwd | type == "string") and (.cwd | length > 0)'
  manifest_check "baseline_commit" '(.baseline_commit | type == "string") and (.baseline_commit | test("^[0-9a-f]{40}$"))'
  manifest_check "round" '(.round | type == "number") and (.round == (.round | floor)) and (.round >= 0)'
  manifest_check "max_rounds" '(.max_rounds | type == "number") and (.max_rounds == (.max_rounds | floor)) and (.max_rounds >= 1)'
  manifest_check "orchestrator_surface" '(.orchestrator_surface | type == "string") and (.orchestrator_surface | length > 0)'
  manifest_check "contract" '.contract | type == "object"'
  manifest_check "contract.version" '(.contract.version | type == "string") and (.contract.version | length > 0)'
  manifest_check "contract.path" '(.contract.path | type == "string") and (.contract.path | length > 0)'
  manifest_check "contract.kind" '(.contract.kind == "openapi") or (.contract.kind == "typescript") or (.contract.kind == "json-schema") or (.contract.kind == "command")'
  manifest_check "contract.validation_command" '(.contract.validation_command | type == "string") and (.contract.validation_command | length > 0)'
  manifest_check "contract.sha256" '(.contract.sha256 | type == "string") and (.contract.sha256 | test("^[0-9a-f]{64}$"))'
  manifest_check "contract.no-extra-keys" '(.contract | type == "object") and ((.contract | keys_unsorted | sort) == (["kind","path","sha256","validation_command","version"] | sort))'
  manifest_check "shared_read_only" '(.shared_read_only | type == "array") and (.shared_read_only | all(type == "string" and length > 0))'
  manifest_check "workers" '.workers | type == "array"'
  manifest_check "workers[].shape" '(.workers | type == "array") and (.workers | all(
      (.id | type == "string" and length > 0) and
      (.lane | type == "string" and length > 0) and
      (.runner == "claude" or .runner == "codex") and
      (.effort == "low" or .effort == "medium" or .effort == "high" or .effort == "xhigh" or .effort == "max") and
      (.status == "pending" or .status == "running" or .status == "waiting" or .status == "blocked" or .status == "done" or .status == "crashed") and
      ((keys_unsorted - ["id","lane","task","runner","effort","status"]) == [])
    ))'
  manifest_check "no-extra-keys" '(keys_unsorted - ["schema_version","run_id","plan_path","cwd","baseline_commit","round","max_rounds","orchestrator_surface","contract","shared_read_only","workers"]) == []'

  if [ -z "$ISSUES" ]; then
    record "manifest-schema-valid" "pass" "all required fields present, well-typed, no extra keys"
  else
    record "manifest-schema-valid" "fail" "$ISSUES"
    MANIFEST_OK=0
  fi
fi

# ─── 2/3. events-schema-valid / events-line-size-valid ─────────────────────
# Independent of the manifest: reads events.jsonl on its own. Redundant with
# event.sh's own write-time checks by design — this is what catches a line
# that reached the file some other way (a worker disobeying "report only
# through event.sh" and appending directly).

SCHEMA_ISSUES=""
SIZE_ISSUES=""
if [ -f "$EVENTS" ]; then
  LINE_NO=0
  while IFS= read -r line || [ -n "$line" ]; do
    LINE_NO=$((LINE_NO + 1))
    [ -z "$line" ] && continue

    BYTES=$(printf '%s\n' "$line" | wc -c | tr -d ' ')
    [ "$BYTES" -lt 4096 ] || SIZE_ISSUES="${SIZE_ISSUES}${SIZE_ISSUES:+, }line ${LINE_NO} (${BYTES} bytes)"

    jq -e '
      (.ts | type == "string") and (.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
      (.lane | type == "string" and length > 0) and
      (.task | type == "string" and length > 0) and
      (.type == "task_start" or .type == "task_done" or .type == "progress" or .type == "question" or .type == "waiting" or .type == "blocked" or .type == "done") and
      (.msg | type == "string") and (.msg | test("^[^\r\n]*$")) and (.msg | length <= 3000) and
      ((keys_unsorted - ["ts","lane","task","type","msg"]) == [])
    ' <<<"$line" >/dev/null 2>&1 || SCHEMA_ISSUES="${SCHEMA_ISSUES}${SCHEMA_ISSUES:+, }line ${LINE_NO}"
  done <"$EVENTS"
fi

if [ -z "$SCHEMA_ISSUES" ]; then
  record "events-schema-valid" "pass" "every event line matches the event schema"
else
  record "events-schema-valid" "fail" "$SCHEMA_ISSUES"
fi
if [ -z "$SIZE_ISSUES" ]; then
  record "events-line-size-valid" "pass" "every event line is under 4096 bytes"
else
  record "events-line-size-valid" "fail" "$SIZE_ISSUES"
fi

# ─── Prerequisites for the git/plan-derived checks ─────────────────────────

GIT_OK=0
PLAN_OK=0
if [ "$MANIFEST_OK" -eq 1 ]; then
  CWD=$(jq -r '.cwd' "$MANIFEST")
  BASELINE=$(jq -r '.baseline_commit' "$MANIFEST")
  PLAN_PATH=$(jq -r '.plan_path' "$MANIFEST")
  CONTRACT_REL=$(jq -r '.contract.path' "$MANIFEST")
  CONTRACT_SHA=$(jq -r '.contract.sha256' "$MANIFEST")

  SHARED_ARR=()
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    SHARED_ARR+=("$s")
  done < <(jq -r '.shared_read_only[]' "$MANIFEST" 2>/dev/null)

  [ -d "$CWD" ] && git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1 && GIT_OK=1
  [ -f "$PLAN_PATH" ] && PLAN_OK=1
  if [ "$PLAN_OK" -eq 1 ]; then
    PLAN_JSON=$("$PARSER" "$PLAN_PATH" 2>/dev/null) || PLAN_OK=0
  fi
fi

if [ "$GIT_OK" -eq 1 ] && [ "$PLAN_OK" -eq 1 ]; then
  ORCH_LANE=$(jq -r '.orchestrator_lane // ""' <<<"$PLAN_JSON")

  # Ownership set excludes the orchestrator lane on purpose — see header note.
  LANE_ARR=()
  PATTERN_ARR=()
  while IFS=$'\t' read -r lname pat; do
    [ -z "$pat" ] && continue
    LANE_ARR+=("$lname")
    PATTERN_ARR+=("$pat")
  done < <(jq -r --arg orch "$ORCH_LANE" '.lanes[] | select(.name != $orch) | .name as $n | .owns[] | "\($n)\t\(.)"' <<<"$PLAN_JSON")
  OWNS_N=${#PATTERN_ARR[@]}

  # owner_of PATH — sets OWNER_COUNT and OWNER_NAMES (comma-joined) for every
  # worker lane whose owns pattern matches PATH.
  owner_of() {
    local path="$1" i=0 matched="" cnt=0
    while [ "$i" -lt "$OWNS_N" ]; do
      if owns_match "$path" "${PATTERN_ARR[$i]}"; then
        cnt=$((cnt + 1))
        matched="${matched}${matched:+,}${LANE_ARR[$i]}"
      fi
      i=$((i + 1))
    done
    OWNER_COUNT=$cnt
    OWNER_NAMES="$matched"
  }

  # is_excluded PATH — the contract file and every shared read-only file are
  # validated by their own dedicated checks below, not by ownership matching
  # (they are explicitly nobody's writable territory during a round, even
  # when a lane legitimately authored them earlier in the plan).
  is_excluded() {
    local path="$1" s
    [ "$path" = "$CONTRACT_REL" ] && return 0
    for s in "${SHARED_ARR[@]}"; do
      [ "$path" = "$s" ] && return 0
    done
    return 1
  }

  # ─── Changed-file sets ────────────────────────────────────────────────
  declare -A CHANGED_STATUS=()
  while IFS= read -r -d '' entry; do
    [ -z "$entry" ] && continue
    xy_status="${entry:0:2}"
    xy_path="${entry:3}"
    CHANGED_STATUS["$xy_path"]=1
    case "$xy_status" in
      R* | C*)
        # porcelain -z emits a second NUL-terminated record (the rename/copy
        # source) immediately after; --no-renames upstream in the union set
        # never emits this, but git status itself can still report R/C.
        IFS= read -r -d '' xy_src || true
        [ -n "${xy_src:-}" ] && CHANGED_STATUS["$xy_src"]=1
        ;;
    esac
  done < <(git -C "$CWD" status --porcelain=v1 -z --untracked-files=all 2>/dev/null)

  declare -A CHANGED_UNION=()
  for k in "${!CHANGED_STATUS[@]}"; do CHANGED_UNION["$k"]=1; done
  if git -C "$CWD" cat-file -e "${BASELINE}^{commit}" 2>/dev/null; then
    while IFS= read -r -d '' path; do
      [ -z "$path" ] && continue
      CHANGED_UNION["$path"]=1
    done < <(git -C "$CWD" diff --name-only --no-renames -z "${BASELINE}..HEAD" 2>/dev/null)
  fi

  # ─── worker-file-logs-valid ─────────────────────────────────────────────
  # worker-<lane>.files.txt is attribution input, not authorization — an
  # entry must (a) be a syntactically real repo-relative path, (b) fall
  # inside the LOGGING lane's own ownership (catches a lane logging a path
  # that was never its territory), and (c) correspond to a path this git
  # view actually shows changed (catches a lane logging a write it never
  # made).
  LOGS_BAD=""
  for f in "${RUN_DIR}"/worker-*.files.txt; do
    [ -f "$f" ] || continue
    flog_base="$(basename "$f")"
    flog_lane="${flog_base#worker-}"
    flog_lane="${flog_lane%.files.txt}"
    while IFS= read -r p || [ -n "$p" ]; do
      [ -z "$p" ] && continue
      case "$p" in
        /*)
          LOGS_BAD="${LOGS_BAD}${LOGS_BAD:+; }${flog_lane}:${p}(absolute-path)"
          continue
          ;;
        *'*'*)
          LOGS_BAD="${LOGS_BAD}${LOGS_BAD:+; }${flog_lane}:${p}(wildcard-not-a-real-path)"
          continue
          ;;
        *'..'*)
          LOGS_BAD="${LOGS_BAD}${LOGS_BAD:+; }${flog_lane}:${p}(path-traversal)"
          continue
          ;;
      esac
      own_ok=0
      oi=0
      while [ "$oi" -lt "$OWNS_N" ]; do
        if [ "${LANE_ARR[$oi]}" = "$flog_lane" ] && owns_match "$p" "${PATTERN_ARR[$oi]}"; then
          own_ok=1
          break
        fi
        oi=$((oi + 1))
      done
      if [ "$own_ok" -eq 0 ]; then
        LOGS_BAD="${LOGS_BAD}${LOGS_BAD:+; }${flog_lane}:${p}(outside-own-ownership)"
        continue
      fi
      if [ -z "${CHANGED_UNION[$p]:-}" ]; then
        LOGS_BAD="${LOGS_BAD}${LOGS_BAD:+; }${flog_lane}:${p}(logged-but-never-actually-changed)"
      fi
    done <"$f"
  done
  if [ -z "$LOGS_BAD" ]; then
    record "worker-file-logs-valid" "pass" "every logged path is a real repo-relative path, inside its own lane's ownership, and reflects an actual change"
  else
    record "worker-file-logs-valid" "fail" "$LOGS_BAD"
  fi

  # ─── changed-files-owned (status-only) / baseline-diff-owned (union) ────
  BAD_STATUS=""
  for path in "${!CHANGED_STATUS[@]}"; do
    is_excluded "$path" && continue
    owner_of "$path"
    [ "$OWNER_COUNT" -eq 1 ] || BAD_STATUS="${BAD_STATUS}${BAD_STATUS:+; }${path}(matches=${OWNER_COUNT}:${OWNER_NAMES:-none})"
  done
  if [ -z "$BAD_STATUS" ]; then
    record "changed-files-owned" "pass" "every uncommitted change is owned by exactly one lane (or exempt)"
  else
    record "changed-files-owned" "fail" "$BAD_STATUS"
  fi

  BAD_UNION=""
  for path in "${!CHANGED_UNION[@]}"; do
    is_excluded "$path" && continue
    owner_of "$path"
    [ "$OWNER_COUNT" -eq 1 ] || BAD_UNION="${BAD_UNION}${BAD_UNION:+; }${path}(matches=${OWNER_COUNT}:${OWNER_NAMES:-none})"
  done
  if [ -z "$BAD_UNION" ]; then
    record "baseline-diff-owned" "pass" "every baseline-diff change (committed or not) is owned by exactly one lane (or exempt)"
  else
    record "baseline-diff-owned" "fail" "$BAD_UNION"
  fi

  # ─── contract-untouched ──────────────────────────────────────────────────
  # Checked last, and by content hash first: a hash match is a stronger
  # signal than "absent from git status/diff" (which a same-bytes rewrite
  # can dodge), so it's the primary test; presence in the baseline-diff
  # union is a second, independent signal on top of it.
  CONTRACT_ABS="${CWD}/${CONTRACT_REL}"
  if command -v sha256sum >/dev/null 2>&1; then
    SHA_CMD=(sha256sum)
  else
    SHA_CMD=(shasum -a 256)
  fi
  CONTRACT_ISSUE=""
  if [ ! -f "$CONTRACT_ABS" ]; then
    CONTRACT_ISSUE="contract file missing: $CONTRACT_REL"
  else
    ACTUAL_SHA=$("${SHA_CMD[@]}" "$CONTRACT_ABS" | awk '{print $1}')
    [ "$ACTUAL_SHA" = "$CONTRACT_SHA" ] || CONTRACT_ISSUE="contract sha256 changed: manifest=${CONTRACT_SHA} actual=${ACTUAL_SHA}"
  fi
  if [ -z "$CONTRACT_ISSUE" ] && [ -n "${CHANGED_UNION[$CONTRACT_REL]:-}" ]; then
    CONTRACT_ISSUE="contract path present in the baseline-diff/status set even though its content hash is unchanged: $CONTRACT_REL"
  fi
  if [ -z "$CONTRACT_ISSUE" ]; then
    record "contract-untouched" "pass" "sha256 matches manifest (${CONTRACT_SHA}) and path absent from the changed-file set"
  else
    record "contract-untouched" "fail" "$CONTRACT_ISSUE"
  fi

  # ─── shared-files-untouched ───────────────────────────────────────────────
  SHARED_BAD=""
  for s in "${SHARED_ARR[@]}"; do
    [ -n "${CHANGED_UNION[$s]:-}" ] && SHARED_BAD="${SHARED_BAD}${SHARED_BAD:+, }${s}"
  done
  if [ -z "$SHARED_BAD" ]; then
    record "shared-files-untouched" "pass" "no shared read-only file appears in the changed-file set"
  else
    record "shared-files-untouched" "fail" "modified: $SHARED_BAD"
  fi

  # ─── changed-files-attributed-once ───────────────────────────────────────
  # Only meaningful for paths that are legitimately owned by exactly one
  # lane — an unowned path is already flagged by baseline-diff-owned, and
  # flagging it again here as "unattributed" would just be noise.
  declare -A LOG_COUNT=()
  declare -A LOG_LANES=()
  for f in "${RUN_DIR}"/worker-*.files.txt; do
    [ -f "$f" ] || continue
    alog_base="$(basename "$f")"
    alog_lane="${alog_base#worker-}"
    alog_lane="${alog_lane%.files.txt}"
    while IFS= read -r p || [ -n "$p" ]; do
      [ -z "$p" ] && continue
      LOG_COUNT["$p"]=$((${LOG_COUNT["$p"]:-0} + 1))
      LOG_LANES["$p"]="${LOG_LANES[$p]:-}${LOG_LANES[$p]:+,}${alog_lane}"
    done <"$f"
  done

  ATTR_BAD=""
  for path in "${!CHANGED_UNION[@]}"; do
    is_excluded "$path" && continue
    owner_of "$path"
    [ "$OWNER_COUNT" -eq 1 ] || continue
    acnt=${LOG_COUNT["$path"]:-0}
    [ "$acnt" -eq 1 ] || ATTR_BAD="${ATTR_BAD}${ATTR_BAD:+; }${path}(owner=${OWNER_NAMES},attributed=${acnt}:${LOG_LANES[$path]:-none})"
  done
  if [ -z "$ATTR_BAD" ]; then
    record "changed-files-attributed-once" "pass" "every lane-owned changed path is logged by exactly one lane"
  else
    record "changed-files-attributed-once" "fail" "$ATTR_BAD"
  fi
else
  DETAIL="prerequisite failed: manifest-ok=${MANIFEST_OK} git-ok=${GIT_OK} plan-ok=${PLAN_OK}"
  for item in worker-file-logs-valid changed-files-owned changed-files-attributed-once \
    contract-untouched shared-files-untouched baseline-diff-owned; do
    record "$item" "fail" "$DETAIL"
  done
fi

# ─── Output ─────────────────────────────────────────────────────────────

ALL_JSON=$(printf '%s\n' "${RESULTS[@]}" | jq -s '.')
FAILS=$(echo "$ALL_JSON" | jq '[.[] | select(.status == "fail")] | length')

if [ "$JSON_OUT" -eq 1 ]; then
  echo "$ALL_JSON"
else
  printf "## validate-run-state: %s\n\n" "$RUN_DIR"
  echo "$ALL_JSON" | jq -r '.[] | "- [" + (if .status == "pass" then "x" else " " end) + "] " + .item + " — " + .detail'
  echo
  if [ "$FAILS" -eq 0 ]; then
    echo "verdict: ALL PASS"
  else
    echo "verdict: $FAILS FAIL"
  fi
fi

[ "$FAILS" -eq 0 ] && exit 0 || exit 1
