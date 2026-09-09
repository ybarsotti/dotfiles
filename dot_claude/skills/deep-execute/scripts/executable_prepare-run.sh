#!/usr/bin/env bash
# prepare-run.sh — Writes the fixed scaffolding for a deep-execute run:
# the shared system prompt, one prompt/result file pair per worker, and
# manifest.json. Launches nothing — Phase 3 (launch-workers.sh) does that.
#
# Usage:
#   prepare-run.sh RUN_DIR CWD ORCH_SURFACE [--system-prompt FILE] SPEC...
#
# SPEC uses name, name:runner:model, or name:runner:model@effort. Only the
# worker name is used here; runner, model, and effort stay in the manifest
# contract owned by init-run.sh.
#
# Idempotent: re-running with the same args leaves manifest.json and
# system-prompt.txt byte-identical (created_at is read back from an
# existing manifest.json rather than re-stamped with `date`), and never
# clobbers a prompt/result file that already exists — the orchestrator is
# expected to replace the <placeholder> judgement sections in
# worker-<name>.prompt.md by hand before calling launch-workers.sh, and a
# second prepare-run.sh call (e.g. to add a worker) must not overwrite that
# work.

set -eufo pipefail

if [ $# -lt 4 ]; then
  echo "Usage: prepare-run.sh RUN_DIR CWD ORCH_SURFACE [--system-prompt FILE] SPEC..." >&2
  exit 2
fi

RUN_DIR="$1"
CWD="$2"
ORCH_SURFACE="$3"
shift 3

SYSTEM_PROMPT_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --system-prompt)
      if [ $# -lt 2 ]; then
        echo "prepare-run.sh: --system-prompt requires a FILE argument" >&2
        exit 2
      fi
      SYSTEM_PROMPT_OVERRIDE="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "prepare-run.sh: unknown flag '$1'" >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [ $# -lt 1 ]; then
  echo "prepare-run.sh: at least one worker SPEC required" >&2
  exit 2
fi

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

parse_spec() {
  local spec="$1" rest model_spec known ok=0
  case "$spec" in
    *:*:*:*)
      echo "Error: malformed worker spec '${spec}' (too many colons)" >&2
      return 1
      ;;
    *:*:*)
      name=${spec%%:*}
      rest=${spec#*:}
      runner=${rest%%:*}
      model_spec=${rest#*:}
      ;;
    *)
      name="$spec"
      runner=claude
      model_spec=sonnet
      ;;
  esac

  if [ -z "$name" ] || [ -z "$runner" ] || [ -z "$model_spec" ]; then
    echo "Error: malformed worker spec '${spec}' (empty name, runner, or model)" >&2
    return 1
  fi

  case "$runner" in
    claude | codex) ;;
    *)
      echo "Error: unknown runner '${runner}' in worker spec '${spec}'" >&2
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
    for known in low medium high xhigh max ultra; do
      [ "$effort" = "$known" ] && ok=1 && break
    done
    if [ "$ok" -ne 1 ]; then
      echo "Error: unknown effort '${effort}' in worker spec '${spec}'" >&2
      return 1
    fi
  fi

  if [ -z "$model" ]; then
    echo "Error: malformed worker spec '${spec}' (empty model)" >&2
    return 1
  fi
}

# Same dual resolution for the template (deployed vs. source-tree layout is
# identical for templates — no `executable_` prefix — but the skill dir
# itself still needs computing the same way).
TEMPLATE="${SKILL_DIR}/templates/system-prompt.txt"

mkdir -p "$RUN_DIR"

# ─── System prompt: always (re)written from the template/override — it's ──
# fixed scaffolding, never hand-edited, so an unconditional overwrite stays
# idempotent by construction (same input file -> same bytes out).
if [ -n "$SYSTEM_PROMPT_OVERRIDE" ]; then
  if [ ! -f "$SYSTEM_PROMPT_OVERRIDE" ]; then
    echo "prepare-run.sh: --system-prompt file not found: ${SYSTEM_PROMPT_OVERRIDE}" >&2
    exit 2
  fi
  cp "$SYSTEM_PROMPT_OVERRIDE" "${RUN_DIR}/system-prompt.txt"
else
  if [ ! -f "$TEMPLATE" ]; then
    echo "prepare-run.sh: missing template ${TEMPLATE}" >&2
    exit 2
  fi
  cp "$TEMPLATE" "${RUN_DIR}/system-prompt.txt"
fi

# ─── Timestamp: computed once, then read back on every later call so a ────
# re-run's manifest.json is byte-identical instead of drifting with `date`.
MANIFEST="${RUN_DIR}/manifest.json"
if [ -f "$MANIFEST" ]; then
  CREATED_AT=$(jq -r '.created_at' "$MANIFEST")
else
  CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi
RUN_ID="$(basename "$RUN_DIR")"

WORKERS_JSON="[]"
for spec in "$@"; do
  parse_spec "$spec" # sets $name (and $runner/$model/$effort, unused here)
  # name/runner/model/effort come from the dynamically-sourced
  # launch-workers.sh (source=/dev/null above), so shellcheck can't see the
  # assignment — verified by the sourcing itself.
  # shellcheck disable=SC2154
  PROMPT_FILE="${RUN_DIR}/worker-${name}.prompt.md"
  RESULT_FILE="${RUN_DIR}/worker-${name}.result.md"
  DONE_MARKER="${RUN_DIR}/worker-${name}.done"

  # ─── Prompt/result files: created only if missing. The orchestrator ──────
  # fills in the <placeholder> judgement sections by hand before launching;
  # a second prepare-run.sh call (e.g. adding a worker) must not clobber
  # that work on workers that already exist.
  if [ ! -f "$PROMPT_FILE" ]; then
    cat >"$PROMPT_FILE" <<EOF
# Task: ${name}

## Orchestration Info
- Run ID: ${RUN_ID}
- Run directory: ${RUN_DIR}
- Orchestrator surface: ${ORCH_SURFACE}
- Result file: ${RESULT_FILE}
- Done marker: ${DONE_MARKER}

## Task
<Detailed task description — be specific about what to do, not vague>

## Files to Work With
<Explicit list of files and directories, with brief notes on what's relevant in each>

## Context
<Architecture notes, related documentation paths, design decisions the worker needs to know>

## Success Criteria
<Concrete, verifiable definition of done>

## When Finished
1. Write a markdown summary of all changes you made to: ${RESULT_FILE}
2. Include a list of every file you created or modified
3. Write "done" (just that word) to: ${DONE_MARKER}
4. Stay available — do not exit
EOF
  fi

  if [ ! -f "$RESULT_FILE" ]; then
    echo "<!-- pending: ${name} has not reported yet -->" >"$RESULT_FILE"
  fi

  ENTRY=$(jq -n \
    --arg name "$name" \
    --arg prompt_file "$PROMPT_FILE" \
    --arg result_file "$RESULT_FILE" \
    --arg done_marker "$DONE_MARKER" \
    '{name: $name, surface_ref: null, status: "pending", prompt_file: $prompt_file, result_file: $result_file, done_marker: $done_marker}')
  WORKERS_JSON=$(jq -c --argjson entry "$ENTRY" '. + [$entry]' <<<"$WORKERS_JSON")
done

jq -n \
  --arg run_id "$RUN_ID" \
  --arg created_at "$CREATED_AT" \
  --arg cwd "$CWD" \
  --arg orch_surface "$ORCH_SURFACE" \
  --argjson workers "$WORKERS_JSON" \
  '{run_id: $run_id, created_at: $created_at, cwd: $cwd, orchestrator_surface: $orch_surface, worker_pane_ref: null, workers: $workers}' \
  >"$MANIFEST"

echo "Wrote scaffolding for $(jq '.workers | length' "$MANIFEST") worker(s) to ${RUN_DIR}" >&2
