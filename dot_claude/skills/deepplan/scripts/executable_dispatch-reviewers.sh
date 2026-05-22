#!/usr/bin/env bash
# dispatch-reviewers.sh — fan out 4 persona reviewers in parallel against the current plan.
#
# Usage: dispatch-reviewers.sh <run-dir> <iter> [--no-codex]
#
# Reads: <run-dir>/plan.md  + project CLAUDE.md (if present)
# Writes:
#   <run-dir>/verdict-architect-iter<N>.json
#   <run-dir>/verdict-project-developer-iter<N>.json
#   <run-dir>/verdict-flow-mapper-iter<N>.json
#   <run-dir>/verdict-qa-iter<N>.json

set -uo pipefail

RUN_DIR="$1"
ITER="$2"
NO_CODEX="${3:-}"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${SKILL_DIR}/scripts/runner.sh"
PLAN="${RUN_DIR}/plan.md"

[ -f "$PLAN" ] || { echo "dispatch-reviewers.sh: missing $PLAN" >&2; exit 1; }

mkdir -p "${RUN_DIR}/logs"

# Persona → (runner, model)
# Defaults: architect + project-developer on Claude/Opus; flow-mapper + qa on Codex.
# With --no-codex, all four run on Claude/Opus.
declare -a PERSONAS=("architect" "project-developer" "flow-mapper" "qa")
declare -A RUNNER_FOR=(
  ["architect"]="claude:opus"
  ["project-developer"]="claude:opus"
  ["flow-mapper"]="codex:"
  ["qa"]="codex:"
)

if [ "$NO_CODEX" = "--no-codex" ]; then
  RUNNER_FOR["flow-mapper"]="claude:opus"
  RUNNER_FOR["qa"]="claude:opus"
fi

CLAUDE_MD=""
if [ -f "$PWD/CLAUDE.md" ]; then
  CLAUDE_MD="$PWD/CLAUDE.md"
elif [ -f "$HOME/.claude/CLAUDE.md" ]; then
  CLAUDE_MD="$HOME/.claude/CLAUDE.md"
fi

build_prompt() {
  local persona="$1"
  cat "${SKILL_DIR}/personas/${persona}.md"
  printf '\n\n---\n\n## Plan to review\n\n'
  cat "$PLAN"
  if [ -n "$CLAUDE_MD" ]; then
    printf '\n\n---\n\n## Project CLAUDE.md (excerpt)\n\n'
    head -200 "$CLAUDE_MD"
  fi
  printf '\n\n---\n\nEmit ONLY the verdict JSON. No prose around it.\n'
}

PIDS=()
for persona in "${PERSONAS[@]}"; do
  IFS=':' read -r runner model <<< "${RUNNER_FOR[$persona]}"
  prompt=$(mktemp)
  build_prompt "$persona" > "$prompt"
  out="${RUN_DIR}/verdict-${persona}-iter${ITER}.json"
  log="${RUN_DIR}/logs/review-${persona}-iter${ITER}.log"
  (
    "$RUNNER" "$runner" "$model" "$prompt" 600 > "$out" 2> "$log"
    ec=$?
    if [ $ec -ne 0 ]; then
      # Synthesize a CHANGES_REQUESTED verdict on agent failure so the loop can recover.
      jq -n --arg p "$persona" --arg n "agent failed (exit $ec); see log" \
        '{persona:$p, verdict:"CHANGES_REQUESTED", notes:$n, proposed_edits:[]}' > "$out"
    fi
    rm -f "$prompt"
  ) &
  PIDS+=($!)
done

EXIT_CODE=0
for pid in "${PIDS[@]}"; do
  wait "$pid" || EXIT_CODE=1
done

echo "reviewers: dispatched ${#PERSONAS[@]} personas for iter ${ITER}" >&2
exit "$EXIT_CODE"
