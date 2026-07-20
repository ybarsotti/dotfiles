#!/usr/bin/env bash
# finalize-plan.sh — Phase 3's fixed sequence: validate -> auto-format -> repair -> tick,
# run over the root plan.md and every subplans/*.md. This is the hard gate SKILL.md's
# Phase 3 defers to: a failing run must never be treated as done — read
# finalize-failures.json, fix, rerun this same script, never advance.
#
# Usage:
#   finalize-plan.sh RUN_DIR
#
# For the whole batch (root plan.md + every subplans/*.md) at once:
#   1. validate-plan.sh --json on every file
#   2. if anything failed: auto-format.sh once, then up to 3 repair rounds, each round
#      spawning `runner.sh claude opus` per still-failing file, re-validating the whole
#      batch after each round (a fixed file must never mask a sibling that's still broken)
#   3. once every file fully passes: tick-checklist.sh on each
#
# auto-format.sh operates on the current working directory (the project the plan targets),
# not on RUN_DIR — run this from the project root, same as the rest of the deep-plan pipeline.
#
# Emits RUN_DIR/finalize-failures.json:
#   pass -> {"status":"pass","attempts":N}
#   fail -> {"status":"fail","attempts":3,"failing":["plan.md","subplans/x.md"],"details":[...]}
# and exits 0 / 1 to match.
#
# Runs under `set -uo pipefail`, not `-e`: this must collect failures across the root plan
# and every subplan before giving up, so one failing validator call can never abort the loop
# before the others get a chance to report.

set -uo pipefail

RUN_DIR="${1:-}"
[ -n "$RUN_DIR" ] && [ -d "$RUN_DIR" ] || {
  echo "finalize-plan.sh: usage: finalize-plan.sh RUN_DIR" >&2
  exit 2
}

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Resolve the deployed sibling name first, falling back to the source-tree
# `executable_` name — the prefix is stripped only by `chezmoi apply`, so this
# works both pre-apply (this source tree) and post-apply (a real run dir).
resolve_script() {
  local name="$1"
  local p="${SKILL_DIR}/scripts/${name}"
  [ -f "$p" ] || p="${SKILL_DIR}/scripts/executable_${name}"
  echo "$p"
}
VALIDATE=$(resolve_script validate-plan.sh)
AUTO_FORMAT=$(resolve_script auto-format.sh)
TICK=$(resolve_script tick-checklist.sh)
RUNNER=$(resolve_script runner.sh)

PLAN="${RUN_DIR}/plan.md"
[ -f "$PLAN" ] || { echo "finalize-plan.sh: missing $PLAN" >&2; exit 2; }
[ -f "$VALIDATE" ] || { echo "finalize-plan.sh: missing $VALIDATE" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "finalize-plan.sh: jq required" >&2; exit 2; }

FAILURES_JSON="${RUN_DIR}/finalize-failures.json"

# root + every subplan, each paired with the validate-plan.sh mode flag it needs.
# auto-format.sh and tick-checklist.sh are not guaranteed +x pre-apply (they're never
# invoked directly by anything else), so both are run via `bash`, not exec'd directly.
FILES=("plan.md:--root")
for sub in "$RUN_DIR"/subplans/*.md; do
  [ -f "$sub" ] || continue
  FILES+=("subplans/$(basename "$sub"):--subplan")
done

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

bash "$AUTO_FORMAT" >&2 || true

MAX_REPAIRS=3
ATTEMPT=0
FAILING=()
DETAILS_JSON="[]"

while :; do
  FAILING=()
  DETAILS_JSON="[]"
  for entry in "${FILES[@]}"; do
    rel="${entry%%:*}"
    mode="${entry##*:}"
    RESULT=$("$VALIDATE" "${RUN_DIR}/${rel}" "$mode" --json 2>/dev/null)
    FAILS=$(jq '[.[] | select(.status=="fail")] | length' <<<"$RESULT" 2>/dev/null || echo 1)
    if [ "$FAILS" -gt 0 ]; then
      FAILING+=("$rel")
      DETAILS_JSON=$(jq --arg f "$rel" --argjson r "$RESULT" '. + [{file:$f, results:$r}]' <<<"$DETAILS_JSON")
    fi
  done

  [ "${#FAILING[@]}" -eq 0 ] && break

  if [ "$ATTEMPT" -ge "$MAX_REPAIRS" ]; then
    jq -n --argjson attempts "$ATTEMPT" \
      --argjson failing "$(printf '%s\n' "${FAILING[@]}" | jq -R . | jq -s .)" \
      --argjson details "$DETAILS_JSON" \
      '{status: "fail", attempts: $attempts, failing: $failing, details: $details}' \
      >"$FAILURES_JSON"
    cat "$FAILURES_JSON"
    exit 1
  fi

  ATTEMPT=$((ATTEMPT + 1))
  for rel in "${FAILING[@]}"; do
    ISSUES=$(jq -r --arg f "$rel" \
      '.[] | select(.file==$f) | .results[] | select(.status=="fail") | "- " + .item + ": " + .detail' \
      <<<"$DETAILS_JSON")
    PROMPT="${SCRATCH}/repair-$(echo "$rel" | tr '/' '_').txt"
    {
      echo "The plan file ${RUN_DIR}/${rel} failed validate-plan.sh with these issues:"
      echo "$ISSUES"
      echo
      echo "Edit ${RUN_DIR}/${rel} directly to fix every issue above. Do not touch any other file."
    } >"$PROMPT"
    "$RUNNER" claude opus "$PROMPT" >>"${SCRATCH}/repair.log" 2>&1 || true
  done
done

for entry in "${FILES[@]}"; do
  rel="${entry%%:*}"
  mode="${entry##*:}"
  bash "$TICK" "${RUN_DIR}/${rel}" "$mode" >&2 || true
done

jq -n --argjson attempts "$ATTEMPT" '{status: "pass", attempts: $attempts}' | tee "$FAILURES_JSON"
