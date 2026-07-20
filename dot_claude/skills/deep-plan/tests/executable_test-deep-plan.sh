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

assert_summary
