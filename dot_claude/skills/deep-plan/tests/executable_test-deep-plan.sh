#!/usr/bin/env bash
set -eufo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
# shellcheck source=/dev/null
. "${ROOT}/dot_claude/skills/_shared/executable_assert.sh"
PARSER="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_plan-to-json.sh"
FANOUT="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_subplan-fanout.sh"
VALIDATE="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_validate-plan.sh"
INVOKE="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_superpowers-invoke.sh"
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

# ─── Task 4: the 21 execution-shape / API-contract / lane-identity ────────
# validators in validate-plan.sh, plus the superpowers-invoke.sh receipt
# mechanism. One fixture mutation per validator, each expected to flip that
# one item (and only that one item, though collateral fails from the same
# mutation are not asserted) to `fail` against an otherwise-valid plan.

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# expect_fail_item ITEM PLAN — asserts validate-plan.sh --root --json records
# ITEM as `fail` for PLAN. Captures the JSON regardless of validate-plan.sh's
# own exit code (it exits 1 whenever anything fails, which is the expected,
# common case here) and never lets a missing/malformed record abort the
# script — the original version of this helper ran a bare `jq -e` outside any
# `if`/`||` guard, which under `set -e` aborted the whole test run exactly
# when it needed to report a problem.
expect_fail_item() {
  local item="$1" plan="$2" json found
  json=$("$VALIDATE" "$plan" --root --json 2>/dev/null) || true
  found=$(jq -r --arg item "$item" \
    'if any(.[]; .item == $item and .status == "fail") then "yes" else "no" end' \
    <<<"$json" 2>/dev/null) || found="no"
  assert_eq "$found" "yes" "${item}: recorded fail"
}

# 1. execution-shape-present — strip the lane table header; the section and
# Mode line survive, but plan-to-json.sh finds zero lanes.
sed '/^| lane | scope | owns (path globs)/d' "$FIXTURE" > "$TMP/no-lane-table.md"
expect_fail_item "execution-shape-present" "$TMP/no-lane-table.md"

# 2. exec-mode-valid
sed 's/- Mode: `parallel`/- Mode: `burst`/' "$FIXTURE" > "$TMP/mode.md"
expect_fail_item "exec-mode-valid" "$TMP/mode.md"

# 3. lanes->=2-if-parallel — drop both non-orchestrator/non-planning lanes.
sed '/^| execution |/d; /^| review |/d' "$FIXTURE" > "$TMP/too-few-lanes.md"
expect_fail_item "lanes->=2-if-parallel" "$TMP/too-few-lanes.md"

# 4. lanes-own-paths-disjoint — give review the same ownership as execution.
sed 's#| `src/review/\*\*` | `src/planning/\*\*`<br>`src/execution/\*\*` | `sonnet high`#| `src/execution/**` | `src/planning/**`<br>`src/execution/**` | `sonnet high`#' \
  "$FIXTURE" > "$TMP/overlap.md"
expect_fail_item "lanes-own-paths-disjoint" "$TMP/overlap.md"

# 5. affected-files-covered-by-exactly-one-lane — point an affected path
# outside every lane's ownership.
sed 's#`src/review/checklist.sh` — final acceptance checklist#`src/unowned/checklist.sh` — final acceptance checklist#' \
  "$FIXTURE" > "$TMP/orphan-path.md"
expect_fail_item "affected-files-covered-by-exactly-one-lane" "$TMP/orphan-path.md"

# 6. lane-agent-in-allowlist
sed 's/| `opus high` | `tests\/planning.sh`/| `gpt-nonexistent low` | `tests\/planning.sh`/' \
  "$FIXTURE" > "$TMP/bad-agent.md"
expect_fail_item "lane-agent-in-allowlist" "$TMP/bad-agent.md"

# 7. lane-test-command-present
sed 's/| `codex gpt-5.6-terra high` | `tests\/execution.sh` | `none` | `orchestrator` |/| `codex gpt-5.6-terra high` | `none` | `none` | `orchestrator` |/' \
  "$FIXTURE" > "$TMP/no-test-cmd.md"
expect_fail_item "lane-test-command-present" "$TMP/no-test-cmd.md"

# 8. contract-present-if-parallel
sed '/^- Contract kind:/d' "$FIXTURE" > "$TMP/no-contract-kind.md"
expect_fail_item "contract-present-if-parallel" "$TMP/no-contract-kind.md"

# 9. contract-endpoints-complete — zero endpoints with no `Endpoints: none`.
sed '/^- Endpoints: none/d' "$FIXTURE" > "$TMP/no-endpoints-decl.md"
expect_fail_item "contract-endpoints-complete" "$TMP/no-endpoints-decl.md"

# 10. contract-no-placeholders
sed 's/- Contract version: `1.0.0`/- Contract version: `1.0.0` <!-- TBD -->/' \
  "$FIXTURE" > "$TMP/contract-tbd.md"
expect_fail_item "contract-no-placeholders" "$TMP/contract-tbd.md"

# 11. contract-version-present
sed 's/- Contract version: `1.0.0`/- Contract version: `v1.0.0`/' \
  "$FIXTURE" > "$TMP/bad-version.md"
expect_fail_item "contract-version-present" "$TMP/bad-version.md"

# 12. tasks-tagged-with-lane
sed '/^\*\*Lane:\*\*/d' "$FIXTURE" > "$TMP/task-lane.md"
expect_fail_item "tasks-tagged-with-lane" "$TMP/task-lane.md"

# 13. every-lane-has-1-task — retag review's only task onto planning.
sed 's/\*\*Lane:\*\* `review`/\*\*Lane:\*\* `planning`/' "$FIXTURE" > "$TMP/lane-no-task.md"
expect_fail_item "every-lane-has-1-task" "$TMP/lane-no-task.md"

# 14. lane-task-files-subset-of-lane-owns — execution's task creates a
# planning-owned path.
sed 's#- Create: `src/execution/runner.sh`#- Create: `src/planning/parser.sh`#' \
  "$FIXTURE" > "$TMP/task-file-wrong-lane.md"
expect_fail_item "lane-task-files-subset-of-lane-owns" "$TMP/task-file-wrong-lane.md"

# 15. lane-names-unique
sed 's/^| review |/| planning |/' "$FIXTURE" > "$TMP/dup-lane.md"
expect_fail_item "lane-names-unique" "$TMP/dup-lane.md"

# 16. exactly-one-orchestrator-lane — orchestrator row's agent stops being
# `orchestrator`, so zero lanes carry that agent.
sed 's/| `orchestrator` | `tests\/orchestrator.sh`/| `opus high` | `tests\/orchestrator.sh`/' \
  "$FIXTURE" > "$TMP/no-orch.md"
expect_fail_item "exactly-one-orchestrator-lane" "$TMP/no-orch.md"

# 17. lane-name-grammar-safe
sed 's/^| planning |/| Planning |/' "$FIXTURE" > "$TMP/bad-lane-name.md"
expect_fail_item "lane-name-grammar-safe" "$TMP/bad-lane-name.md"

# 18. depends-on-lanes-known
sed 's/| `opus high` | `tests\/planning.sh` | `none` | `orchestrator` |/| `opus high` | `tests\/planning.sh` | `none` | `ghost` |/' \
  "$FIXTURE" > "$TMP/unknown-dep.md"
expect_fail_item "depends-on-lanes-known" "$TMP/unknown-dep.md"

# 19. depends-on-no-self
sed 's/^| review | \(.*\) | `none` |$/| review | \1 | `review` |/' "$FIXTURE" > "$TMP/self-dep.md"
expect_fail_item "depends-on-no-self" "$TMP/self-dep.md"

# 20. depends-on-acyclic — planning and execution depend on each other.
sed -e 's/| `opus high` | `tests\/planning.sh` | `none` | `orchestrator` |/| `opus high` | `tests\/planning.sh` | `none` | `execution` |/' \
    -e 's/| `codex gpt-5.6-terra high` | `tests\/execution.sh` | `none` | `orchestrator` |/| `codex gpt-5.6-terra high` | `tests\/execution.sh` | `none` | `planning` |/' \
    "$FIXTURE" > "$TMP/cycle.md"
expect_fail_item "depends-on-acyclic" "$TMP/cycle.md"

# 21. superpowers-ticks-have-receipts — hand-ticked, no receipt.
sed 's/- \[ \] grill-with-docs/- [x] grill-with-docs/' "$FIXTURE" > "$TMP/hand-tick.md"
expect_fail_item "superpowers-ticks-have-receipts" "$TMP/hand-tick.md"

# All 21 pass against the untouched fixture.
VALID_JSON=$("$VALIDATE" "$FIXTURE" --root --json) || true
assert_eq "$(jq -r '.[] | select(.item=="execution-shape-present") | .status' <<<"$VALID_JSON")" pass \
  "valid fixture: execution-shape-present"
FAIL_COUNT_21=$(jq -r --argjson items '[
  "execution-shape-present","exec-mode-valid","lanes->=2-if-parallel",
  "lanes-own-paths-disjoint","affected-files-covered-by-exactly-one-lane",
  "lane-agent-in-allowlist","lane-test-command-present","contract-present-if-parallel",
  "contract-endpoints-complete","contract-no-placeholders","contract-version-present",
  "tasks-tagged-with-lane","every-lane-has-1-task","lane-task-files-subset-of-lane-owns",
  "lane-names-unique","exactly-one-orchestrator-lane","lane-name-grammar-safe",
  "depends-on-lanes-known","depends-on-no-self","depends-on-acyclic",
  "superpowers-ticks-have-receipts"
]' '[.[] | select(.item as $i | $items | index($i)) | select(.status == "fail")] | length' \
  <<<"$VALID_JSON")
assert_eq "$FAIL_COUNT_21" 0 "all 21 validators pass on the untouched valid fixture"

# ─── Serial plans: the 20 execution-shape/lane-identity items record `pass`
# with an `n/a` detail, but superpowers-ticks-have-receipts still runs for
# real (a serial plan is not exempt from receipt integrity). ────────────────

SERIAL_PLAN="$TMP/serial-plan.md"
awk '
  /^## Execution shape/ { print; print "- Mode: `serial`"; skip=1; next }
  /^## API contract/ { skip=0 }
  skip { next }
  { print }
' "$FIXTURE" > "$SERIAL_PLAN"

SERIAL_JSON=$("$VALIDATE" "$SERIAL_PLAN" --root --json) || true
for item in execution-shape-present exec-mode-valid "lanes->=2-if-parallel" \
  lanes-own-paths-disjoint affected-files-covered-by-exactly-one-lane \
  lane-agent-in-allowlist lane-test-command-present contract-present-if-parallel \
  contract-endpoints-complete contract-no-placeholders contract-version-present \
  tasks-tagged-with-lane every-lane-has-1-task lane-task-files-subset-of-lane-owns \
  lane-names-unique exactly-one-orchestrator-lane lane-name-grammar-safe \
  depends-on-lanes-known depends-on-no-self depends-on-acyclic; do
  STATUS=$(jq -r --arg i "$item" '.[] | select(.item == $i) | .status' <<<"$SERIAL_JSON")
  DETAIL=$(jq -r --arg i "$item" '.[] | select(.item == $i) | .detail' <<<"$SERIAL_JSON")
  assert_eq "$STATUS" pass "serial plan: ${item} status"
  assert_contains "$DETAIL" "n/a" "serial plan: ${item} detail"
done

# superpowers-ticks-have-receipts still runs for real in serial mode.
SERIAL_HAND_TICK="$TMP/serial-hand-tick.md"
sed 's/- \[ \] grill-with-docs/- [x] grill-with-docs/' "$SERIAL_PLAN" > "$SERIAL_HAND_TICK"
expect_fail_item "superpowers-ticks-have-receipts" "$SERIAL_HAND_TICK"

# ─── Receipt mechanism: both directions ────────────────────────────────────

# A hand-ticked box (no receipt) fails — already covered by mutation 21
# above; here confirm the OTHER direction: superpowers-invoke.sh's own tick
# passes, because it wrote the receipt that goes with it.
RECEIPT_RUN=$(mktemp -d)
cp "$FIXTURE" "${RECEIPT_RUN}/plan.md"
assert_exit 0 "$INVOKE" "$RECEIPT_RUN" grill-with-docs
assert_exit 0 test -f "${RECEIPT_RUN}/superpowers-receipts.log"
RECEIPT_JSON=$("$VALIDATE" "${RECEIPT_RUN}/plan.md" --root --json) || true
assert_eq "$(jq -r '.[] | select(.item=="superpowers-ticks-have-receipts") | .status' <<<"$RECEIPT_JSON")" pass \
  "a box ticked via superpowers-invoke.sh passes (receipt present)"
assert_contains "$(cat "${RECEIPT_RUN}/plan.md")" "- [x] grill-with-docs" \
  "superpowers-invoke.sh ticked the box"
if command -v stat >/dev/null 2>&1; then
  RECEIPT_PERM=$(stat -f '%Lp' "${RECEIPT_RUN}/superpowers-receipts.log" 2>/dev/null ||
    stat -c '%a' "${RECEIPT_RUN}/superpowers-receipts.log")
  assert_eq "$RECEIPT_PERM" 444 "receipt log is chmod 0444 after append"
fi
rm -rf "$RECEIPT_RUN"

# A second invocation appends a second, hash-chained receipt line rather than
# overwriting the first.
CHAIN_RUN=$(mktemp -d)
cp "$FIXTURE" "${CHAIN_RUN}/plan.md"
assert_exit 0 "$INVOKE" "$CHAIN_RUN" grill-with-docs
assert_exit 0 "$INVOKE" "$CHAIN_RUN" brainstorming
CHAIN_LINES=$(wc -l < "${CHAIN_RUN}/superpowers-receipts.log" | tr -d ' ')
assert_eq "$CHAIN_LINES" 2 "two invocations append two receipt lines"
rm -rf "$CHAIN_RUN"

# An unknown skill name exits 2 and writes nothing.
UNKNOWN_RUN=$(mktemp -d)
cp "$FIXTURE" "${UNKNOWN_RUN}/plan.md"
assert_exit 2 "$INVOKE" "$UNKNOWN_RUN" not-a-real-skill
assert_exit 1 test -f "${UNKNOWN_RUN}/superpowers-receipts.log"
rm -rf "$UNKNOWN_RUN"

assert_summary
