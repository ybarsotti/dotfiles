#!/usr/bin/env bash
set -eufo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
# shellcheck source=/dev/null
. "${ROOT}/dot_claude/skills/_shared/executable_assert.sh"
PARSER="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_plan-to-json.sh"
FANOUT="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_subplan-fanout.sh"
FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/valid-parallel-plan.md"
ESCAPED_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/lane-escaped-pipe.md"
UNESCAPED_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/lane-unescaped-pipe.md"
SHORT_ROW_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/lane-short-row.md"
ENDPOINT_ESCAPED_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/endpoint-escaped-pipe.md"
ENDPOINT_UNESCAPED_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/endpoint-unescaped-pipe.md"
FANOUT_MALFORMED_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/fanout-malformed-lane.md"
FANOUT_NO_SHAPE_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/fanout-no-execution-shape.md"

JSON=$("$PARSER" "$FIXTURE")
assert_eq "$(jq -r '.mode' <<<"$JSON")" parallel "mode"
assert_eq "$(jq '.lanes | length' <<<"$JSON")" 4 "lane count"
assert_eq "$(jq -r '.contract.version' <<<"$JSON")" 1.0.0 "contract version"
assert_eq "$(jq '.tasks | all(.lane != null)' <<<"$JSON")" true "task lanes"

# ─── Value-level assertions (a shape-only check accepts wrong values) ──────

assert_eq "$(jq -c '[.lanes[].name]' <<<"$JSON")" \
  '["orchestrator","planning","execution","review"]' "exact ordered lane names"
assert_eq "$(jq -r '.tasks[] | select(.number==2) | .lane' <<<"$JSON")" \
  planning "task 2's exact lane"
assert_eq "$(jq -c '.lanes[] | select(.name=="orchestrator") | .depends_on' <<<"$JSON")" \
  '[]' "orchestrator lane depends_on: none -> []"
assert_eq "$(jq -c '.lanes[] | select(.name=="orchestrator") | .mock_command' <<<"$JSON")" \
  null "orchestrator lane mock_command: none -> null"
assert_eq "$(jq -c '.lanes[] | select(.name=="planning") | .depends_on' <<<"$JSON")" \
  '["orchestrator"]' "planning lane depends_on: real value maps through"

# ─── Finding 1: an escaped pipe (\|) in a lane cell round-trips to a ───────
# literal `|` instead of silently splitting the row.

ESCAPED_JSON=$("$PARSER" "$ESCAPED_FIXTURE")
assert_eq "$(jq -r '.lanes[0].test_command' <<<"$ESCAPED_JSON")" \
  "pytest | tee out.log" "escaped pipe round-trips to a literal | in the cell"
assert_eq "$(jq '.lanes | length' <<<"$ESCAPED_JSON")" 1 "escaped-pipe row still parses as one lane"

# ─── Finding 2: an UNescaped pipe, or a short row, must fail loudly rather ─
# than parse silently with shifted/defaulted columns.

assert_exit 1 "$PARSER" "$UNESCAPED_FIXTURE"
assert_exit 1 "$PARSER" "$SHORT_ROW_FIXTURE"

UNESCAPED_STDERR=$("$PARSER" "$UNESCAPED_FIXTURE" 2>&1 >/dev/null || true)
assert_contains "$UNESCAPED_STDERR" "malformed lane row" \
  "unescaped-pipe row fails with a diagnostic naming the offending row"
SHORT_ROW_STDERR=$("$PARSER" "$SHORT_ROW_FIXTURE" 2>&1 >/dev/null || true)
assert_contains "$SHORT_ROW_STDERR" "malformed lane row" \
  "short row fails with a diagnostic naming the offending row"

# ─── Finding 3: subplan-fanout.sh must resolve the parser in the source ───
# tree (executable_plan-to-json.sh) as well as the deployed tree
# (plan-to-json.sh), and produce one subplan per declared LANE — not
# directory-grouped chapters — for a plan with a parallel Execution shape.

FANOUT_RUN=$(mktemp -d)
cp "$FIXTURE" "${FANOUT_RUN}/plan.md"
"$FANOUT" "$FANOUT_RUN" >/dev/null
FANOUT_FILES=$(ls "${FANOUT_RUN}/subplans" | sort | tr '\n' ',')
assert_eq "$FANOUT_FILES" "execution.md,orchestrator.md,planning.md,review.md," \
  "subplan-fanout produces one subplan per lane, not directory chapters"
rm -rf "$FANOUT_RUN"

# ─── Round 2, Finding 1: the API contract endpoint table has the identical ─
# unescaped-`|` hazard as the lane table — an ordinary TypeScript union in
# `response_shape` (e.g. `string | number`) must round-trip when escaped,
# and fail loudly when it isn't.

ENDPOINT_ESCAPED_JSON=$("$PARSER" "$ENDPOINT_ESCAPED_FIXTURE")
assert_eq "$(jq -r '.contract.endpoints[0].response_shape' <<<"$ENDPOINT_ESCAPED_JSON")" \
  "string | number" "escaped pipe in an endpoint cell round-trips to a literal |"
assert_eq "$(jq '.contract.endpoints | length' <<<"$ENDPOINT_ESCAPED_JSON")" 1 \
  "escaped-pipe endpoint row still parses as one endpoint"

assert_exit 1 "$PARSER" "$ENDPOINT_UNESCAPED_FIXTURE"
ENDPOINT_UNESCAPED_STDERR=$("$PARSER" "$ENDPOINT_UNESCAPED_FIXTURE" 2>&1 >/dev/null || true)
assert_contains "$ENDPOINT_UNESCAPED_STDERR" "malformed endpoint row" \
  "unescaped-pipe endpoint row fails with a diagnostic naming the offending row"

# ─── Round 2, Finding 2: subplan-fanout.sh must propagate a genuine parser ─
# failure instead of silently degrading to legacy directory grouping — and
# must keep degrading, with no error, for a plan that legitimately has no
# `## Execution shape` section at all.

MALFORMED_FANOUT_RUN=$(mktemp -d)
cp "$FANOUT_MALFORMED_FIXTURE" "${MALFORMED_FANOUT_RUN}/plan.md"
assert_exit 1 "$FANOUT" "$MALFORMED_FANOUT_RUN"
MALFORMED_FANOUT_STDERR=$("$FANOUT" "$MALFORMED_FANOUT_RUN" 2>&1 >/dev/null || true)
assert_contains "$MALFORMED_FANOUT_STDERR" "malformed lane row" \
  "subplan-fanout.sh surfaces the parser's diagnostic instead of swallowing it"
rm -rf "$MALFORMED_FANOUT_RUN"

NO_SHAPE_FANOUT_RUN=$(mktemp -d)
cp "$FANOUT_NO_SHAPE_FIXTURE" "${NO_SHAPE_FANOUT_RUN}/plan.md"
assert_exit 0 "$FANOUT" "$NO_SHAPE_FANOUT_RUN"
NO_SHAPE_FANOUT_FILES=$(ls "${NO_SHAPE_FANOUT_RUN}/subplans" | sort | tr '\n' ',')
assert_eq "$NO_SHAPE_FANOUT_FILES" "docs.md,src.md," \
  "a plan with no Execution shape section still fans out via legacy directory grouping"
rm -rf "$NO_SHAPE_FANOUT_RUN"

# ─── Round 2, Finding 3: a raw `\001` byte in the plan file must be ────────
# rejected, not silently treated as the internal pipe-escape sentinel.

SENTINEL_FIXTURE=$(mktemp)
printf '# Sentinel byte fixture\n\nRaw byte follows: [\001]\n' >"$SENTINEL_FIXTURE"
assert_exit 1 "$PARSER" "$SENTINEL_FIXTURE"
SENTINEL_STDERR=$("$PARSER" "$SENTINEL_FIXTURE" 2>&1 >/dev/null || true)
assert_contains "$SENTINEL_STDERR" '\001' \
  "a raw 0x01 byte in the plan is rejected with a clear diagnostic"
rm -f "$SENTINEL_FIXTURE"

assert_summary
