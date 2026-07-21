#!/usr/bin/env bash
set -eufo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
# shellcheck source=/dev/null
. "${ROOT}/dot_claude/skills/_shared/executable_assert.sh"
PARSER="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_plan-to-json.sh"
FANOUT="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_subplan-fanout.sh"
VALIDATE="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_validate-plan.sh"
INVOKE="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_superpowers-invoke.sh"
VALIDATE_DRAFT="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_validate-draft.sh"
DISPATCH="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_dispatch-planners.sh"
RUNNER="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_runner.sh"
PARSE_ARGS="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_parse-args.sh"
FINALIZE="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_finalize-plan.sh"
SKILL_MD="${ROOT}/dot_claude/skills/deep-plan/SKILL.md"
VALID_DRAFT_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/draft-valid-minimal.md"
UNBALANCED_FENCES_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/draft-unbalanced-fences.md"
FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/valid-parallel-plan.md"
ESCAPED_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/lane-escaped-pipe.md"
UNESCAPED_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/lane-unescaped-pipe.md"
SHORT_ROW_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/lane-short-row.md"
ENDPOINT_ESCAPED_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/endpoint-escaped-pipe.md"
ENDPOINT_UNESCAPED_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/endpoint-unescaped-pipe.md"
FANOUT_MALFORMED_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/fanout-malformed-lane.md"
FANOUT_NO_SHAPE_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/fanout-no-execution-shape.md"
TYPO_HEADING_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/execution-shape-typo-heading.md"
ABSENT_SHAPE_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/execution-shape-absent.md"
FENCED_SHAPE_FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/execution-shape-fenced-example.md"
OWNS_LIB="${ROOT}/dot_claude/skills/deep-plan/scripts/owns-lib.sh"

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
FANOUT_FILES=$(find "${FANOUT_RUN}/subplans" -maxdepth 1 -type f -exec basename {} \; | sort | tr '\n' ',')
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
NO_SHAPE_FANOUT_FILES=$(find "${NO_SHAPE_FANOUT_RUN}/subplans" -maxdepth 1 -type f -exec basename {} \; | sort | tr '\n' ',')
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
# shellcheck disable=SC2016 # literal backticked plan text in the sed pattern, not a command substitution
sed 's/- Mode: `parallel`/- Mode: `burst`/' "$FIXTURE" > "$TMP/mode.md"
expect_fail_item "exec-mode-valid" "$TMP/mode.md"

# 3. lanes->=2-if-parallel — drop both non-orchestrator/non-planning lanes.
sed '/^| execution |/d; /^| review |/d' "$FIXTURE" > "$TMP/too-few-lanes.md"
expect_fail_item "lanes->=2-if-parallel" "$TMP/too-few-lanes.md"

# 4. lanes-own-paths-disjoint — give review the same ownership as execution.
# shellcheck disable=SC2016 # literal backticked plan text in the sed pattern, not a command substitution
sed 's#| `src/review/\*\*` | `src/planning/\*\*`<br>`src/execution/\*\*` | `sonnet high`#| `src/execution/**` | `src/planning/**`<br>`src/execution/**` | `sonnet high`#' \
  "$FIXTURE" > "$TMP/overlap.md"
expect_fail_item "lanes-own-paths-disjoint" "$TMP/overlap.md"

# 5. affected-files-covered-by-exactly-one-lane — point an affected path
# outside every lane's ownership.
# shellcheck disable=SC2016 # literal backticked plan text in the sed pattern, not a command substitution
sed 's#`src/review/checklist.sh` — final acceptance checklist#`src/unowned/checklist.sh` — final acceptance checklist#' \
  "$FIXTURE" > "$TMP/orphan-path.md"
expect_fail_item "affected-files-covered-by-exactly-one-lane" "$TMP/orphan-path.md"

# 6. lane-agent-in-allowlist
# shellcheck disable=SC2016 # literal backticked plan text in the sed pattern, not a command substitution
sed 's/| `opus high` | `tests\/planning.sh`/| `gpt-nonexistent low` | `tests\/planning.sh`/' \
  "$FIXTURE" > "$TMP/bad-agent.md"
expect_fail_item "lane-agent-in-allowlist" "$TMP/bad-agent.md"

# 7. lane-test-command-present
# shellcheck disable=SC2016 # literal backticked plan text in the sed pattern, not a command substitution
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
# shellcheck disable=SC2016 # literal backticked plan text in the sed pattern, not a command substitution
sed 's/- Contract version: `1.0.0`/- Contract version: `1.0.0` <!-- TBD -->/' \
  "$FIXTURE" > "$TMP/contract-tbd.md"
expect_fail_item "contract-no-placeholders" "$TMP/contract-tbd.md"

# 11. contract-version-present
# shellcheck disable=SC2016 # literal backticked plan text in the sed pattern, not a command substitution
sed 's/- Contract version: `1.0.0`/- Contract version: `v1.0.0`/' \
  "$FIXTURE" > "$TMP/bad-version.md"
expect_fail_item "contract-version-present" "$TMP/bad-version.md"

# 12. tasks-tagged-with-lane
sed '/^\*\*Lane:\*\*/d' "$FIXTURE" > "$TMP/task-lane.md"
expect_fail_item "tasks-tagged-with-lane" "$TMP/task-lane.md"

# 13. every-lane-has-1-task — retag review's only task onto planning.
# shellcheck disable=SC2016 # literal backticked plan text in the sed pattern, not a command substitution
sed 's/\*\*Lane:\*\* `review`/\*\*Lane:\*\* `planning`/' "$FIXTURE" > "$TMP/lane-no-task.md"
expect_fail_item "every-lane-has-1-task" "$TMP/lane-no-task.md"

# 14. lane-task-files-subset-of-lane-owns — execution's task creates a
# planning-owned path.
# shellcheck disable=SC2016 # literal backticked plan text in the sed pattern, not a command substitution
sed 's#- Create: `src/execution/runner.sh`#- Create: `src/planning/parser.sh`#' \
  "$FIXTURE" > "$TMP/task-file-wrong-lane.md"
expect_fail_item "lane-task-files-subset-of-lane-owns" "$TMP/task-file-wrong-lane.md"

# 15. lane-names-unique
sed 's/^| review |/| planning |/' "$FIXTURE" > "$TMP/dup-lane.md"
expect_fail_item "lane-names-unique" "$TMP/dup-lane.md"

# 16. exactly-one-orchestrator-lane — orchestrator row's agent stops being
# `orchestrator`, so zero lanes carry that agent.
# shellcheck disable=SC2016 # literal backticked plan text in the sed pattern, not a command substitution
sed 's/| `orchestrator` | `tests\/orchestrator.sh`/| `opus high` | `tests\/orchestrator.sh`/' \
  "$FIXTURE" > "$TMP/no-orch.md"
expect_fail_item "exactly-one-orchestrator-lane" "$TMP/no-orch.md"

# 17. lane-name-grammar-safe
sed 's/^| planning |/| Planning |/' "$FIXTURE" > "$TMP/bad-lane-name.md"
expect_fail_item "lane-name-grammar-safe" "$TMP/bad-lane-name.md"

# 18. depends-on-lanes-known
# shellcheck disable=SC2016 # literal backticked plan text in the sed pattern, not a command substitution
sed 's/| `opus high` | `tests\/planning.sh` | `none` | `orchestrator` |/| `opus high` | `tests\/planning.sh` | `none` | `ghost` |/' \
  "$FIXTURE" > "$TMP/unknown-dep.md"
expect_fail_item "depends-on-lanes-known" "$TMP/unknown-dep.md"

# 19. depends-on-no-self
# shellcheck disable=SC2016 # literal backticked plan text in the sed pattern, not a command substitution
sed 's/^| review | \(.*\) | `none` |$/| review | \1 | `review` |/' "$FIXTURE" > "$TMP/self-dep.md"
expect_fail_item "depends-on-no-self" "$TMP/self-dep.md"

# 20. depends-on-acyclic — planning and execution depend on each other.
# shellcheck disable=SC2016 # literal backticked plan text in the sed pattern, not a command substitution
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

# ─── C3: SERIAL must key off actual absence of a lane table (LANE_COUNT==0),
# not off the `Mode:` value — one deleted `- Mode: `parallel`` line, with the
# lane table left intact, used to exempt a real 4-lane plan from all 20
# execution-shape/lane-identity validators (`n/a — serial plan`, reporting
# `pass` on a plan with e.g. a genuine duplicate lane name). ────────────────

# 1. Lane table present, `Mode:` line deleted → exec-mode-valid FAILS (not
# n/a) — MODE_VAL is empty, and an empty lane table no longer buys a
# free pass.
# shellcheck disable=SC2016 # literal backticked plan text in the sed pattern, not a command substitution
sed '/^- Mode: `parallel`/d' "$FIXTURE" > "$TMP/no-mode.md"
NO_MODE_JSON=$("$VALIDATE" "$TMP/no-mode.md" --root --json) || true
assert_eq "$(jq -r '.[] | select(.item=="exec-mode-valid") | .status' <<<"$NO_MODE_JSON")" fail \
  "C3: lane table present + no Mode line -> exec-mode-valid fails (not n/a)"
assert_eq "$(jq -r '.[] | select(.item=="execution-shape-present") | .status' <<<"$NO_MODE_JSON")" pass \
  "C3: lane table present + no Mode line -> execution-shape-present still passes (lanes ARE present)"

# 2. Same, plus a genuine duplicate lane name -> lane-names-unique FAILS
# instead of sliding into the n/a serial exemption.
# shellcheck disable=SC2016 # literal backticked plan text in the sed pattern, not a command substitution
sed '/^- Mode: `parallel`/d; s/^| review |/| planning |/' "$FIXTURE" > "$TMP/no-mode-dup.md"
expect_fail_item "lane-names-unique" "$TMP/no-mode-dup.md"

# 3. Genuinely no `## Execution shape` section at all -> all 20 items still
# record `n/a — serial plan` and validate-plan.sh doesn't fail because of
# them (the exemption is legitimate here).
NO_SHAPE_JSON=$("$VALIDATE" "$ABSENT_SHAPE_FIXTURE" --root --json) || true
for item in execution-shape-present exec-mode-valid "lanes->=2-if-parallel" \
  lanes-own-paths-disjoint affected-files-covered-by-exactly-one-lane \
  lane-agent-in-allowlist lane-test-command-present contract-present-if-parallel \
  contract-endpoints-complete contract-no-placeholders contract-version-present \
  tasks-tagged-with-lane every-lane-has-1-task lane-task-files-subset-of-lane-owns \
  lane-names-unique exactly-one-orchestrator-lane lane-name-grammar-safe \
  depends-on-lanes-known depends-on-no-self depends-on-acyclic; do
  STATUS=$(jq -r --arg i "$item" '.[] | select(.item == $i) | .status' <<<"$NO_SHAPE_JSON")
  assert_eq "$STATUS" pass "C3: genuinely absent Execution shape: ${item} still n/a-passes"
done

# 4. An explicit `- Mode: `serial`` plan with NO lane table stays exempted
# (this is exactly what SERIAL_PLAN above already is — no lane table
# survives its construction — so the pre-existing loop above already pins
# this; assert LANE_COUNT is genuinely 0 for it as a direct pin on the gate
# condition itself).
SERIAL_PLAN_JSON=$("$PARSER" "$SERIAL_PLAN")
assert_eq "$(jq '.lanes | length' <<<"$SERIAL_PLAN_JSON")" 0 \
  "C3: explicit Mode: serial plan genuinely has zero lanes (the gate's actual condition)"

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

# ─── C2: owns_match / owns_overlap direct regression coverage ─────────────
# A reviewer once reverted the `*/'**'` quoting fix in BOTH (then-duplicate)
# copies of owns_match and the full suite still reported 100 passed, 0
# failed — nothing pinned the behavior. These pin it directly against the
# shared library both validate-plan.sh and subplan-fanout.sh now source, so
# there is exactly one copy left to protect (not two that can drift apart).
# shellcheck source=/dev/null
. "$OWNS_LIB"

# Exact path containing a slash must NOT match an unrelated owner (the bug:
# unquoted `*/**` degrades to two glob `*`s, matching ANY string containing
# a `/`, which is nearly every real repo path).
assert_exit 1 owns_match "src/shared/contract.schema.json" "src/planning/**"
# `dir/**` matches dir itself and anything nested under it.
assert_exit 0 owns_match "src/planning" "src/planning/**"
assert_exit 0 owns_match "src/planning/anything/deep" "src/planning/**"
# A path that merely shares a string prefix must NOT match: `a/bc` is not
# owned by `a/b` — this is exactly the shape the unquoted-glob bug would
# have falsely matched (both contain a `/`).
assert_exit 1 owns_match "a/bc" "a/b"
# Pattern with no slash at all — exact match only.
assert_exit 0 owns_match "justfile" "justfile"
assert_exit 1 owns_match "justfile" "other-file"

# owns_overlap: equal patterns, a prefix covering an exact path under it, and
# genuinely disjoint patterns/paths.
assert_exit 0 owns_overlap "src/planning/**" "src/planning/**"
assert_exit 0 owns_overlap "src/planning/**" "src/planning/sub/file.sh"
assert_exit 1 owns_overlap "src/planning/**" "src/execution/**"
assert_exit 1 owns_overlap "a/b" "a/bc"

# The two former copies are now one: neither script defines its own
# `owns_match()` anymore, both source owns-lib.sh. This pins the
# deduplication decision so a future edit can't silently reintroduce a
# second, driftable copy.
assert_eq "$(grep -c 'owns_match()' "${ROOT}/dot_claude/skills/deep-plan/scripts/executable_validate-plan.sh")" 0 \
  "validate-plan.sh no longer defines its own owns_match (sources owns-lib.sh)"
assert_eq "$(grep -c 'owns_match()' "${ROOT}/dot_claude/skills/deep-plan/scripts/executable_subplan-fanout.sh")" 0 \
  "subplan-fanout.sh no longer defines its own owns_match (sources owns-lib.sh)"

# ─── C1: receipt hash chain anchored to a git commit SHA ───────────────────
# compute_receipt_hash PREV_HASH TS SKILL SHA — mirrors superpowers-invoke.sh's
# own algorithm exactly, so tests can mint receipts with a genuinely valid
# chain hash but a deliberately bad repo-sha (to isolate the SHA check from
# the chain check).
compute_receipt_hash() {
  local prev="$1" ts="$2" skill="$3" sha="$4" payload
  payload=$(printf '%s\t%s\t%s' "$ts" "$skill" "$sha")
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s%s' "$prev" "$payload" | sha256sum | awk '{print $1}'
  else
    printf '%s%s' "$prev" "$payload" | shasum -a 256 | awk '{print $1}'
  fi
}

# A hand-forged receipt (hand-appended line, hash not derived from the chain)
# must fail — this is the exact forgery the CRITICAL finding demonstrated:
# `printf '...\tbrainstorming\tdeadbeef...\n' >> superpowers-receipts.log`
# then hand-tick the box used to report `pass`.
FORGE_RUN=$(mktemp -d)
cp "$FIXTURE" "${FORGE_RUN}/plan.md"
printf '2026-07-20T00:00:00Z\tgrill-with-docs\tno-git\tdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' \
  >>"${FORGE_RUN}/superpowers-receipts.log"
sed 's/- \[ \] grill-with-docs/- [x] grill-with-docs/' "${FORGE_RUN}/plan.md" >"${FORGE_RUN}/plan.md.new"
mv "${FORGE_RUN}/plan.md.new" "${FORGE_RUN}/plan.md"
FORGE_JSON=$("$VALIDATE" "${FORGE_RUN}/plan.md" --root --json) || true
assert_eq "$(jq -r '.[] | select(.item=="superpowers-ticks-have-receipts") | .status' <<<"$FORGE_JSON")" fail \
  "hand-forged receipt (hash not derived from the chain) fails validation"
assert_contains "$(jq -r '.[] | select(.item=="superpowers-ticks-have-receipts") | .detail' <<<"$FORGE_JSON")" \
  "hash chain broken" "forged receipt: detail names the broken chain"
rm -rf "$FORGE_RUN"

# A chain-valid receipt naming a repo-sha that isn't a real commit fails.
BADSHA_RUN=$(mktemp -d)
cp "$FIXTURE" "${BADSHA_RUN}/plan.md"
TS1="2026-07-20T00:00:00Z"
FAKE_SHA="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
HASH1=$(compute_receipt_hash "" "$TS1" "grill-with-docs" "$FAKE_SHA")
printf '%s\t%s\t%s\t%s\n' "$TS1" "grill-with-docs" "$FAKE_SHA" "$HASH1" >>"${BADSHA_RUN}/superpowers-receipts.log"
sed 's/- \[ \] grill-with-docs/- [x] grill-with-docs/' "${BADSHA_RUN}/plan.md" >"${BADSHA_RUN}/plan.md.new"
mv "${BADSHA_RUN}/plan.md.new" "${BADSHA_RUN}/plan.md"
BADSHA_JSON=$("$VALIDATE" "${BADSHA_RUN}/plan.md" --root --json) || true
assert_eq "$(jq -r '.[] | select(.item=="superpowers-ticks-have-receipts") | .status' <<<"$BADSHA_JSON")" fail \
  "a chain-valid receipt naming a non-existent commit fails"
assert_contains "$(jq -r '.[] | select(.item=="superpowers-ticks-have-receipts") | .detail' <<<"$BADSHA_JSON")" \
  "not-a-commit" "detail names the invalid sha as not-a-commit"
rm -rf "$BADSHA_RUN"

# A chain-valid receipt naming a REAL commit that is NOT an ancestor of
# current HEAD also fails. `git commit-tree` mints a genuine, harmless
# dangling commit object (HEAD as its parent, so it's a descendant, not an
# ancestor, of HEAD) without touching any branch or the working tree.
NONANCESTOR_RUN=$(mktemp -d)
cp "$FIXTURE" "${NONANCESTOR_RUN}/plan.md"
CHILD_SHA=$(git -C "$ROOT" commit-tree -p HEAD -m "scratch: non-ancestor receipt test (dangling, safe to gc)" "HEAD^{tree}")
TS2="2026-07-20T00:00:01Z"
HASH2=$(compute_receipt_hash "" "$TS2" "grill-with-docs" "$CHILD_SHA")
printf '%s\t%s\t%s\t%s\n' "$TS2" "grill-with-docs" "$CHILD_SHA" "$HASH2" >>"${NONANCESTOR_RUN}/superpowers-receipts.log"
sed 's/- \[ \] grill-with-docs/- [x] grill-with-docs/' "${NONANCESTOR_RUN}/plan.md" >"${NONANCESTOR_RUN}/plan.md.new"
mv "${NONANCESTOR_RUN}/plan.md.new" "${NONANCESTOR_RUN}/plan.md"
NONANCESTOR_JSON=$("$VALIDATE" "${NONANCESTOR_RUN}/plan.md" --root --json) || true
assert_eq "$(jq -r '.[] | select(.item=="superpowers-ticks-have-receipts") | .status' <<<"$NONANCESTOR_JSON")" fail \
  "a chain-valid receipt naming a real, non-ancestor commit fails"
assert_contains "$(jq -r '.[] | select(.item=="superpowers-ticks-have-receipts") | .detail' <<<"$NONANCESTOR_JSON")" \
  "not-ancestor-of-HEAD" "detail names the commit as not-ancestor-of-HEAD"
rm -rf "$NONANCESTOR_RUN"

# A legitimately superpowers-invoke.sh-written receipt still passes, and now
# carries the 4-field <ts>\t<skill>\t<repo-sha>\t<chain-hash> format.
LEGIT_RUN=$(mktemp -d)
cp "$FIXTURE" "${LEGIT_RUN}/plan.md"
assert_exit 0 "$INVOKE" "$LEGIT_RUN" grill-with-docs
LEGIT_JSON=$("$VALIDATE" "${LEGIT_RUN}/plan.md" --root --json) || true
assert_eq "$(jq -r '.[] | select(.item=="superpowers-ticks-have-receipts") | .status' <<<"$LEGIT_JSON")" pass \
  "a legitimately superpowers-invoke.sh-written receipt passes"
LEGIT_FIELDS=$(awk -F'\t' '{print NF}' "${LEGIT_RUN}/superpowers-receipts.log")
assert_eq "$LEGIT_FIELDS" 4 "receipt line has 4 tab-separated fields (ts, skill, repo-sha, chain-hash)"
rm -rf "$LEGIT_RUN"

# ─── I1: Handoff items are not required to approve the plan, but a forged ──
# tick on one still fails superpowers-ticks-have-receipts (ticks are checked
# everywhere in the section, required-or-not). All 3 REQUIRED items must be
# resolved first (receipted or declined) so this isolates the Handoff
# behavior instead of also failing on the fixture's own bare required items.

HANDOFF_RUN=$(mktemp -d)
cp "$FIXTURE" "${HANDOFF_RUN}/plan.md"
assert_exit 0 "$INVOKE" "$HANDOFF_RUN" grill-with-docs
assert_exit 0 "$INVOKE" "$HANDOFF_RUN" brainstorming
assert_exit 0 "$INVOKE" "$HANDOFF_RUN" writing-plans
HANDOFF_JSON=$("$VALIDATE" "${HANDOFF_RUN}/plan.md" --root --json) || true
assert_eq "$(jq -r '.[] | select(.item=="superpowers-all-invoked") | .status' <<<"$HANDOFF_JSON")" pass \
  "unticked Handoff items do not fail superpowers-all-invoked (once the required items are resolved)"

sed 's/- \[ \] using-git-worktrees/- [x] using-git-worktrees/' "${HANDOFF_RUN}/plan.md" >"${HANDOFF_RUN}/plan.md.new"
mv "${HANDOFF_RUN}/plan.md.new" "${HANDOFF_RUN}/plan.md"
HANDOFF_FORGE_JSON=$("$VALIDATE" "${HANDOFF_RUN}/plan.md" --root --json) || true
assert_eq "$(jq -r '.[] | select(.item=="superpowers-ticks-have-receipts") | .status' <<<"$HANDOFF_FORGE_JSON")" fail \
  "a forged tick on a Handoff item still fails superpowers-ticks-have-receipts"
assert_eq "$(jq -r '.[] | select(.item=="superpowers-all-invoked") | .status' <<<"$HANDOFF_FORGE_JSON")" pass \
  "a forged Handoff tick doesn't affect superpowers-all-invoked (Handoff isn't required)"
rm -rf "$HANDOFF_RUN"

# ─── I2: the declination annotation is loosened to a word-boundary match ───
# on "not invoked" — no semicolon required, and the alternate real-world
# phrasing "— not invoked as a skill; ..." now resolves the item. The other
# two required items are declined with the standard form so the assertion
# below isolates the alternate wording rather than also failing on them.

DECLINE_ALT_RUN="$TMP/decline-alt-wording.md"
sed -e 's/- \[ \] grill-with-docs/- [ ] grill-with-docs — not invoked; --skip-grill was passed/' \
    -e 's/- \[ \] brainstorming/- [ ] brainstorming — not invoked; trivial change/' \
    -e 's/- \[ \] writing-plans/- [ ] writing-plans — not invoked as a skill; already covered by prior draft/' \
    "$FIXTURE" >"$DECLINE_ALT_RUN"
DECLINE_JSON=$("$VALIDATE" "$DECLINE_ALT_RUN" --root --json) || true
assert_eq "$(jq -r '.[] | select(.item=="superpowers-all-invoked") | .status' <<<"$DECLINE_JSON")" pass \
  "'— not invoked as a skill; ...' declination form now resolves the item"

# ─── Q1: a near-miss "## Execution shape" heading (typo/wrong level) fails ──
# loudly instead of silently degrading to serial/legacy behavior; a
# genuinely absent heading still degrades quietly.

assert_exit 1 "$PARSER" "$TYPO_HEADING_FIXTURE"
TYPO_STDERR=$("$PARSER" "$TYPO_HEADING_FIXTURE" 2>&1 >/dev/null || true)
assert_contains "$TYPO_STDERR" "heading looks like '## Execution shape'" \
  "a near-miss Execution shape heading fails with a diagnostic naming the offending line"

assert_exit 0 "$PARSER" "$ABSENT_SHAPE_FIXTURE"
ABSENT_JSON=$("$PARSER" "$ABSENT_SHAPE_FIXTURE")
assert_eq "$(jq -r 'if .mode == null then "null" else .mode end' <<<"$ABSENT_JSON")" null \
  "a genuinely absent Execution shape section still degrades quietly (mode: null)"

# ─── Q2: a fenced illustrative "## Execution shape" example is never ──────
# mistaken for a real declaration (the same fence-unaware-declaration bug
# class already fixed once for `**Lane:**`, swept here for every other
# declaration-parsing site named in the finding).

assert_exit 0 "$PARSER" "$FENCED_SHAPE_FIXTURE"
FENCED_JSON=$("$PARSER" "$FENCED_SHAPE_FIXTURE")
assert_eq "$(jq -r 'if .mode == null then "null" else .mode end' <<<"$FENCED_JSON")" null \
  "a fenced illustrative Execution shape example is not treated as a real declaration"

# ─── Task 5: fail loudly on an empty or truncated planner draft ───────────
#
# /deep-plan dispatched two planner agents to draft the plan this project is
# executing. Both produced EMPTY draft files, and dispatch-planners.sh
# exited 0 — root cause: runner.sh hardcoded `--max-turns 8` and
# dispatch-planners.sh hardcoded a 900s timeout, not enough headroom for a
# planner that must invoke the Skill tool, read it, then write a full plan;
# and the dispatcher only failed when BOTH planners failed, so one silent
# failure was invisible. This section pins: the raised budgets, a
# validate-draft.sh that rejects empty AND mid-generation-truncated drafts
# by content (not just by size), and dispatch-planners.sh now failing
# whenever any ENABLED planner's draft is invalid.

# The budgets themselves — asserted by source inspection so a future edit
# that quietly lowers them back down fails a test, not just a live run.
assert_exit 0 grep -q 'DEEP_PLAN_PLANNER_TIMEOUT:-1800' "$DISPATCH"
assert_exit 0 grep -q 'DEEP_PLAN_CLAUDE_MAX_TURNS:-20' "$RUNNER"

: > "$TMP/empty.md"
printf '# Partial Plan\n\n## Implementation tasks\n' > "$TMP/truncated.md"
assert_exit 1 "$VALIDATE_DRAFT" "$TMP/empty.md" --json
assert_exit 1 "$VALIDATE_DRAFT" "$TMP/truncated.md" --json
assert_exit 1 "$VALIDATE_DRAFT" "$UNBALANCED_FENCES_FIXTURE" --json
assert_exit 0 "$VALIDATE_DRAFT" "$VALID_DRAFT_FIXTURE" --json

# expect_draft_item ITEM STATUS DRAFT — asserts validate-draft.sh --json
# records ITEM as STATUS for DRAFT. A shape-only check (e.g. "5 items
# present") would pass a draft that fails for the wrong reason; this pins
# which specific item fires, mirroring expect_fail_item's role above for
# validate-plan.sh.
expect_draft_item() {
  local item="$1" want="$2" draft="$3" json got
  json=$("$VALIDATE_DRAFT" "$draft" --json 2>/dev/null) || true
  got=$(jq -r --arg item "$item" \
    'map(select(.item == $item)) | if length > 0 then .[0].status else "MISSING" end' \
    <<<"$json" 2>/dev/null) || got="MISSING"
  assert_eq "$got" "$want" "$(basename "$draft"): ${item}"
}

# The truncated fixture stops right after the tasks heading: header and
# tail never render at all, and no task block exists yet.
expect_draft_item "draft-non-empty" "pass" "$TMP/truncated.md"
expect_draft_item "draft-header-complete" "fail" "$TMP/truncated.md"
expect_draft_item "draft-tasks-complete" "fail" "$TMP/truncated.md"
expect_draft_item "draft-tail-complete" "fail" "$TMP/truncated.md"

# The unbalanced-fences fixture has a real header and task block before its
# unclosed ``` — isolating that this specific mutation flips the fence
# check (collateral fails on other items from the same unclosed block, e.g.
# the checklist getting swallowed into the "still open" fence, are not
# asserted here, matching the Task 4 convention above).
expect_draft_item "draft-header-complete" "pass" "$UNBALANCED_FENCES_FIXTURE"
expect_draft_item "draft-tasks-complete" "pass" "$UNBALANCED_FENCES_FIXTURE"
expect_draft_item "draft-fences-balanced" "fail" "$UNBALANCED_FENCES_FIXTURE"

# The valid fixture passes every item, not just the aggregate exit code.
for item in draft-non-empty draft-header-complete draft-tasks-complete \
  draft-tail-complete draft-fences-balanced; do
  expect_draft_item "$item" "pass" "$VALID_DRAFT_FIXTURE"
done

# ─── Task 5 review fix: draft-tail-complete against a shape, not a vocabulary ──
#
# A reviewer built three adversarial drafts — each a real header + real task
# block + a well-formed checklist truncated one character/word/sentence into
# its final item name — and ran the SHIPPED validate-draft.sh against them.
# All three passed with exit 0: the old "well-formed last line" regex
# (`^- \[[ xX]\] [a-z][a-z0-9-]*([[:space:]].*)?$`) only required the line to
# START like a checklist item, so `- [ ] lane-cont` satisfied it just as well
# as a genuine, complete item name. draft-tail-complete now checks the last
# line's item name against CHECKLIST_VOCAB (read from the templates), a
# closed set a shape regex cannot consult.
# shellcheck disable=SC2016 # literal markdown fixture text, no expansion wanted
TAIL_BASE='# Sample Feature Implementation Plan

**Goal:** Ship the sample feature end to end.

**Architecture:** A single service change behind an existing adapter boundary.

**Tech Stack:** Bash, jq.

## Implementation tasks

### Task 1: Do the thing

**Files:**

- Create: `src/thing.sh`

**Interfaces:**

- `thing.sh ARG` — does the thing.

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run it and watch it fail**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run it and watch it pass**

## Checklist (machine-validated; do NOT hand-edit — call tick-checklist.sh)
- [ ] mermaid-present
- [ ] tasks-≥1
- [ ] no-tbd-placeholders
- [ ] superpowers-all-invoked
'

# Truncated one character into an item name after the canary.
printf '%s%s\n' "$TAIL_BASE" '- [ ] l' > "$TMP/adv-onechar.md"
# Truncated mid-word.
printf '%s%s\n' "$TAIL_BASE" '- [ ] lane-cont' > "$TMP/adv-midword.md"
# Truncated mid-sentence in trailing text.
printf '%s%s\n' "$TAIL_BASE" \
  '- [ ] lane-contract-present and this sentence trails off mid way through beca' \
  > "$TMP/adv-midsentence.md"
expect_draft_item "draft-tail-complete" "fail" "$TMP/adv-onechar.md"
expect_draft_item "draft-tail-complete" "fail" "$TMP/adv-midword.md"
expect_draft_item "draft-tail-complete" "fail" "$TMP/adv-midsentence.md"

# A last line ending on a complete, known item name still passes.
printf '%s%s\n' "$TAIL_BASE" '- [ ] no-tbd-placeholders' > "$TMP/adv-known-tail.md"
expect_draft_item "draft-tail-complete" "pass" "$TMP/adv-known-tail.md"

# A last line ending on a complete but UNKNOWN item name still fails — this
# is what pins the check to the templates' vocabulary rather than merely
# "any word after the canary."
printf '%s%s\n' "$TAIL_BASE" '- [ ] totally-made-up-item' > "$TMP/adv-unknown-tail.md"
expect_draft_item "draft-tail-complete" "fail" "$TMP/adv-unknown-tail.md"

# ─── Task 5 review fix: draft-tasks-complete requires task BODIES, not just
# bare `### Task N:` headings ────────────────────────────────────────────────
#
# A draft with three bare task headings, zero Files/Interfaces/Steps content,
# and a well-formed Checklist used to pass all five checks — a planner that
# ran dry after emitting an outline of task titles was accepted as complete.
# draft-tasks-complete now reuses validate-plan.sh's task_body_issues (shared
# via task-body-lib.sh) so a bare heading fails the same way it already does
# in validate-plan.sh's tasks-have-files-and-interfaces / tasks-have-tdd-steps.
cat > "$TMP/bare-headings.md" <<'HEREDOC'
# Sample Feature Implementation Plan

**Goal:** Ship the sample feature end to end.

**Architecture:** A single service change behind an existing adapter boundary.

**Tech Stack:** Bash, jq.

## Implementation tasks

### Task 1: Do the thing

### Task 2: Do another thing

### Task 3: Do a third thing

## Checklist (machine-validated; do NOT hand-edit — call tick-checklist.sh)
- [ ] mermaid-present
- [ ] tasks-≥1
- [ ] no-tbd-placeholders
- [ ] superpowers-all-invoked
HEREDOC
expect_draft_item "draft-tasks-complete" "fail" "$TMP/bare-headings.md"

# The three real session drafts (this run's own planner outputs) must still
# pass every item — including draft-opus.md's embedded NUL byte, which
# requires the existing `grep -a` handling to stay intact.
REAL_DRAFTS_DIR="${HOME}/.claude/deep-plan-runs/20260720-142952-a8257c"
if [ -d "$REAL_DRAFTS_DIR" ]; then
  for real in draft-opus.md draft-codex.md plan.md; do
    for item in draft-non-empty draft-header-complete draft-tasks-complete \
      draft-tail-complete draft-fences-balanced; do
      expect_draft_item "$item" "pass" "${REAL_DRAFTS_DIR}/${real}"
    done
  done
fi

# ─── PATH stubs for `claude` and `codex` ───────────────────────────────────
# dispatch-planners.sh/runner.sh must never invoke the real CLIs from this
# test suite. Both stubs drain stdin (the real CLIs read the prompt from
# stdin) and are controlled entirely by env vars, so one pair of scripts
# covers every scenario below. A STUB_ERROR exit (97) is reserved for the
# stub's own misuse — e.g. codex invoked without --output-last-message —
# so a broken stub is never mistaken for the dispatch behavior under test.
STUB_DIR=$(mktemp -d)

cat > "${STUB_DIR}/claude" <<'STUBEOF'
#!/usr/bin/env bash
set -uo pipefail
cat >/dev/null || { echo "STUB_ERROR(claude): failed to drain stdin" >&2; exit 97; }
if [ -n "${STUB_CLAUDE_OUTPUT:-}" ]; then
  [ -f "$STUB_CLAUDE_OUTPUT" ] || {
    echo "STUB_ERROR(claude): STUB_CLAUDE_OUTPUT not found: $STUB_CLAUDE_OUTPUT" >&2
    exit 97
  }
  cat "$STUB_CLAUDE_OUTPUT"
fi
exit "${STUB_CLAUDE_EXIT:-0}"
STUBEOF
chmod +x "${STUB_DIR}/claude"

cat > "${STUB_DIR}/codex" <<'STUBEOF'
#!/usr/bin/env bash
set -uo pipefail
LAST_MSG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output-last-message) LAST_MSG="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cat >/dev/null || { echo "STUB_ERROR(codex): failed to drain stdin" >&2; exit 97; }
if [ -z "$LAST_MSG" ]; then
  echo "STUB_ERROR(codex): no --output-last-message flag seen" >&2
  exit 97
fi
if [ -n "${STUB_CODEX_OUTPUT:-}" ]; then
  [ -f "$STUB_CODEX_OUTPUT" ] || {
    echo "STUB_ERROR(codex): STUB_CODEX_OUTPUT not found: $STUB_CODEX_OUTPUT" >&2
    exit 97
  }
  cat "$STUB_CODEX_OUTPUT" > "$LAST_MSG"
fi
exit "${STUB_CODEX_EXIT:-0}"
STUBEOF
chmod +x "${STUB_DIR}/codex"

# Stub sanity check, isolated from dispatch-planners.sh entirely: proves the
# stubs themselves behave before anything downstream depends on them, so a
# broken stub fails here first with its own label, not disguised as a
# dispatch-level assertion.
STUB_CLAUDE_STDOUT=$(printf 'stub prompt\n' | STUB_CLAUDE_OUTPUT="$VALID_DRAFT_FIXTURE" "${STUB_DIR}/claude")
assert_eq "$STUB_CLAUDE_STDOUT" "$(cat "$VALID_DRAFT_FIXTURE")" \
  "claude stub echoes STUB_CLAUDE_OUTPUT verbatim"
STUB_LAST_MSG="$TMP/stub-last-msg.md"
printf 'stub prompt\n' | STUB_CODEX_OUTPUT="$VALID_DRAFT_FIXTURE" \
  "${STUB_DIR}/codex" --output-last-message "$STUB_LAST_MSG" - >/dev/null
assert_eq "$(cat "$STUB_LAST_MSG")" "$(cat "$VALID_DRAFT_FIXTURE")" \
  "codex stub writes STUB_CODEX_OUTPUT to --output-last-message verbatim"
assert_exit 97 env -u STUB_CODEX_OUTPUT "${STUB_DIR}/codex" < /dev/null
EMPTY_STUB_FILE="$TMP/empty-stub-draft.md"
: > "$EMPTY_STUB_FILE"

# ─── dispatch-planners.sh end-to-end, against the stubs ────────────────────

# Baseline: both planners produce a valid draft -> dispatch succeeds. Proves
# the raised budgets and new per-planner validation didn't break the happy
# path.
BOTH_VALID_RUN=$(mktemp -d)
DISPATCH_EXIT=0
STUB_CLAUDE_OUTPUT="$VALID_DRAFT_FIXTURE" STUB_CODEX_OUTPUT="$VALID_DRAFT_FIXTURE" \
  DEEP_PLAN_PLANNER_TIMEOUT=30 PATH="${STUB_DIR}:${PATH}" \
  "$DISPATCH" "$BOTH_VALID_RUN" "stub task" \
  >"${BOTH_VALID_RUN}/stdout.log" 2>"${BOTH_VALID_RUN}/stderr.log" || DISPATCH_EXIT=$?
assert_eq "$DISPATCH_EXIT" 0 "both planners valid: dispatch-planners.sh exits 0"
rm -rf "$BOTH_VALID_RUN"

# The original incident, reproduced: BOTH planners are enabled, and ONE
# (codex) writes an empty draft while its process still exits 0 — exactly
# what a starved-budget `claude`/`codex` CLI call does. Before this task,
# gating on process exit codes alone meant one valid planner (opus) masked
# this and dispatch-planners.sh exited 0. It must now exit non-zero.
ONE_EMPTY_RUN=$(mktemp -d)
DISPATCH_EXIT=0
STUB_CLAUDE_OUTPUT="$VALID_DRAFT_FIXTURE" STUB_CODEX_OUTPUT="$EMPTY_STUB_FILE" \
  DEEP_PLAN_PLANNER_TIMEOUT=30 PATH="${STUB_DIR}:${PATH}" \
  "$DISPATCH" "$ONE_EMPTY_RUN" "stub task" \
  >"${ONE_EMPTY_RUN}/stdout.log" 2>"${ONE_EMPTY_RUN}/stderr.log" || DISPATCH_EXIT=$?
assert_eq "$DISPATCH_EXIT" 1 \
  "one enabled planner (codex) emits an empty draft: dispatch-planners.sh now exits non-zero (was 0)"
assert_eq "$(wc -c < "${ONE_EMPTY_RUN}/draft-codex.md" | tr -d '[:space:]')" 0 \
  "the empty codex draft really is 0 bytes (reproduces the incident's exact symptom)"
rm -rf "$ONE_EMPTY_RUN"

# The mirror case: opus (never optional, no --no-codex-equivalent flag for
# it) writes a truncated draft while codex is valid — also fails.
OPUS_TRUNCATED_RUN=$(mktemp -d)
DISPATCH_EXIT=0
STUB_CLAUDE_OUTPUT="$TMP/truncated.md" STUB_CODEX_OUTPUT="$VALID_DRAFT_FIXTURE" \
  DEEP_PLAN_PLANNER_TIMEOUT=30 PATH="${STUB_DIR}:${PATH}" \
  "$DISPATCH" "$OPUS_TRUNCATED_RUN" "stub task" \
  >"${OPUS_TRUNCATED_RUN}/stdout.log" 2>"${OPUS_TRUNCATED_RUN}/stderr.log" || DISPATCH_EXIT=$?
assert_eq "$DISPATCH_EXIT" 1 "opus draft truncated: dispatch-planners.sh exits non-zero even with a valid codex draft"
rm -rf "$OPUS_TRUNCATED_RUN"

# --no-codex: codex is never launched and its absence must not fail the
# dispatch — a disabled planner is not an "enabled planner producing an
# invalid draft".
NO_CODEX_RUN=$(mktemp -d)
DISPATCH_EXIT=0
STUB_CLAUDE_OUTPUT="$VALID_DRAFT_FIXTURE" \
  DEEP_PLAN_PLANNER_TIMEOUT=30 PATH="${STUB_DIR}:${PATH}" \
  "$DISPATCH" "$NO_CODEX_RUN" "stub task" --no-codex \
  >"${NO_CODEX_RUN}/stdout.log" 2>"${NO_CODEX_RUN}/stderr.log" || DISPATCH_EXIT=$?
assert_eq "$DISPATCH_EXIT" 0 "--no-codex with a valid opus draft: dispatch-planners.sh exits 0"
assert_eq "$([ -f "${NO_CODEX_RUN}/draft-codex.md" ] && echo yes || echo no)" no \
  "--no-codex: codex is never launched, no draft-codex.md is written"
rm -rf "$NO_CODEX_RUN"

rm -rf "$STUB_DIR"

# ─── Task 6: parse-args.sh — Phase 0's fixed argument grammar ──────────────

PARSE_SAMPLE=$("$PARSE_ARGS" "--ticket FBIT-1 --no-codex build X")
assert_eq "$(jq -r '.ticket' <<<"$PARSE_SAMPLE")" "FBIT-1" "parse-args: --ticket value"
assert_eq "$(jq -r '.no_codex' <<<"$PARSE_SAMPLE")" "true" "parse-args: --no-codex sets no_codex=true"
assert_eq "$(jq -r '.max_plan_iter' <<<"$PARSE_SAMPLE")" "3" "parse-args: --max-plan-iter defaults to 3"
assert_eq "$(jq -r '.task_description' <<<"$PARSE_SAMPLE")" "build X" \
  "parse-args: positional words after flags become task_description"
assert_eq "$(jq -r '.skip_grill' <<<"$PARSE_SAMPLE")" "false" "parse-args: --skip-grill defaults false"
assert_eq "$(jq -r '.dry_run' <<<"$PARSE_SAMPLE")" "false" "parse-args: --dry-run defaults false"

assert_exit 2 "$PARSE_ARGS" "--bogus-flag build X"
PARSE_UNKNOWN_STDERR=$("$PARSE_ARGS" "--bogus-flag build X" 2>&1 >/dev/null || true)
assert_contains "$PARSE_UNKNOWN_STDERR" "unknown flag" \
  "parse-args: unknown flag exits 2 with a diagnostic naming it"

PARSE_EMPTY=$("$PARSE_ARGS" "")
assert_eq "$(jq -r '.task_description' <<<"$PARSE_EMPTY")" "" "parse-args: empty input -> empty task_description"
assert_eq "$(jq -r '.ticket' <<<"$PARSE_EMPTY")" "" "parse-args: empty input -> empty ticket"
assert_eq "$(jq -r '.max_plan_iter' <<<"$PARSE_EMPTY")" "3" "parse-args: empty input still defaults max_plan_iter"

# Quotes and multi-word content inside the task description must survive
# round-trip literally — $ARGUMENTS is a flat token stream, not shell syntax
# to re-parse, so embedded quote characters are not stripped.
PARSE_QUOTED=$("$PARSE_ARGS" 'fix the "foo bar" module now')
assert_eq "$(jq -r '.task_description' <<<"$PARSE_QUOTED")" 'fix the "foo bar" module now' \
  "parse-args: quotes/spaces inside the description round-trip literally"

# ─── Fix: --max-plan-iter 0 silently disabled the entire Phase 2 review ────
# loop (loop condition is `ITER > --max-plan-iter`, so 0 trips on the very
# first iteration) — well-formed JSON, destructive value, exit 0. Reject
# values < 1 with the same diagnostic style as the existing negative/
# non-numeric check, and clamp the top end too: arbitrarily large values
# were passing through un-clamped to `jq --argjson`.

assert_exit 2 "$PARSE_ARGS" "--max-plan-iter 0 build X"
PARSE_ZERO_STDERR=$("$PARSE_ARGS" "--max-plan-iter 0 build X" 2>&1 >/dev/null || true)
assert_contains "$PARSE_ZERO_STDERR" "max-plan-iter" \
  "parse-args: --max-plan-iter 0 exits 2 with a diagnostic naming the flag"

PARSE_ONE=$("$PARSE_ARGS" "--max-plan-iter 1 build X")
assert_eq "$(jq -r '.max_plan_iter' <<<"$PARSE_ONE")" "1" \
  "parse-args: --max-plan-iter 1 is accepted (the floor)"

assert_exit 2 "$PARSE_ARGS" "--max-plan-iter 21 build X"
PARSE_OVER_STDERR=$("$PARSE_ARGS" "--max-plan-iter 21 build X" 2>&1 >/dev/null || true)
assert_contains "$PARSE_OVER_STDERR" "max-plan-iter" \
  "parse-args: a value above the ceiling exits 2 with a diagnostic naming the flag"

PARSE_CEIL=$("$PARSE_ARGS" "--max-plan-iter 20 build X")
assert_eq "$(jq -r '.max_plan_iter' <<<"$PARSE_CEIL")" "20" \
  "parse-args: --max-plan-iter 20 is accepted (the ceiling)"

# A value long enough to overflow bash's 64-bit arithmetic must not wrap
# around into an accepted small number — reject on digit count before ever
# evaluating it as arithmetic.
assert_exit 2 "$PARSE_ARGS" "--max-plan-iter 99999999999999999999999999 build X"

# A leading zero must not be misread as octal by bash arithmetic (010 is
# decimal 10, not 8) — the accepted value normalizes to canonical decimal.
PARSE_LEADING_ZERO=$("$PARSE_ARGS" "--max-plan-iter 010 build X")
assert_eq "$(jq -r '.max_plan_iter' <<<"$PARSE_LEADING_ZERO")" "10" \
  "parse-args: a leading-zero value is read as decimal, not octal"

# ─── Fix: repeated flags — last occurrence wins (documented convention) ────
PARSE_REPEATED=$("$PARSE_ARGS" "--ticket FBIT-1 --ticket FBIT-2 build X")
assert_eq "$(jq -r '.ticket' <<<"$PARSE_REPEATED")" "FBIT-2" \
  "parse-args: a repeated flag's last occurrence wins"

# ─── Fix: an embedded newline collapses to a single space in ───────────────
# task_description, same as any other run of whitespace — $ARGUMENTS is a
# flat token stream and gets word-split on whitespace (space, tab, newline)
# before reassembly, not preserved as shell/text syntax.
PARSE_NEWLINE=$("$PARSE_ARGS" "$(printf 'fix the\nmodule now')")
assert_eq "$(jq -r '.task_description' <<<"$PARSE_NEWLINE")" "fix the module now" \
  "parse-args: an embedded newline collapses to a single space in task_description"

# ─── Task 6: finalize-plan.sh — Phase 3's fixed validate/repair/tick sequence ──

FIN_STUB_DIR=$(mktemp -d)
cat > "${FIN_STUB_DIR}/claude" <<'STUBEOF'
#!/usr/bin/env bash
# No-op repair stub: drains the prompt and exits 0 without touching any
# file — the repair-loop tests below only assert finalize-plan.sh's own
# control flow (looping, aggregation, exit code), not that a real agent's
# edits land.
cat >/dev/null
exit 0
STUBEOF
chmod +x "${FIN_STUB_DIR}/claude"

# shellcheck disable=SC2016 # literal markdown fixture text, no expansion wanted
FIN_ROOT_ONE_SUB='# Widget Refactor Implementation Plan

REQUIRED SUB-SKILL: superpowers:writing-plans

**Goal:** Ship the widget refactor.
**Architecture:** Adapter-based.
**Tech Stack:** bash, jq.

## Clarifying questions
_no ambiguity_

## Global Constraints
- Follow existing shellcheck conventions.

## Flow diagram
```mermaid
sequenceDiagram
  participant A as Caller
  participant B as Callee
  A->>B: call
  B-->>A: response
  A->>B: ack
```

## Implementation tasks

### Task 1: Do the thing
**Files:**
- Modify: `foo.sh`

**Interfaces:**
- `foo()` does the thing.

- [ ] **Step 1:** write failing test
- [ ] **Step 2:** run it red
- [ ] **Step 3:** implement
- [ ] **Step 4:** run it green

## TDD test list
- `test one` — checks one
- `test two` — checks two
- `test three` — checks three
- Mock only the outermost boundaries (network, 3rd-party APIs); inner services run real.

## Edge cases & failure modes
- edge one
- edge two
- edge three
- edge four

## Abstractions decision log
| Decision | Rationale | Alternative |
|----------|-----------|-------------|
| Use adapter | isolates vendor | direct call |

## Affected files
- `foo.sh`

## Subplans
- [good](subplans/good.md)

## Rationale & key decisions
Chose the adapter approach to isolate vendor churn.

## Documentation impact
none — no docs describe this logic

## QA / test-execution
no

## Verification
- run the tests

## Superpowers invoked
- [ ] grill-with-docs — not invoked; test fixture
- [ ] brainstorming — not invoked; test fixture
- [ ] writing-plans — not invoked; test fixture

## Checklist (machine-validated; do NOT hand-edit — call tick-checklist.sh --root)
- [ ] mermaid-present
- [ ] mermaid-has-entry-and-exit
- [ ] tdd-list-≥3
- [ ] edges-≥4
- [ ] code-intel-bootstrapped
- [ ] clarifying-questions-asked
- [ ] tasks-≥1
- [ ] tasks-have-files-and-interfaces
- [ ] tasks-have-tdd-steps
- [ ] no-tbd-placeholders
- [ ] writing-plans-header
- [ ] global-constraints-present
- [ ] adapter-decision-log-≥1-row
- [ ] affected-files-paths-exist
- [ ] subplans-section-non-empty
- [ ] each-subplan-file-exists
- [ ] each-subplan-has-flow-and-tdd
- [ ] rationale-present
- [ ] mocking-policy-stated
- [ ] docs-impact-listed
- [ ] qa-flag-set
- [ ] superpowers-all-invoked
'

# shellcheck disable=SC2016 # literal markdown fixture text, no expansion wanted
FIN_GOOD_SUBPLAN='# Subplan: good

**Lane:** `misc`

## Clarifying questions
_no ambiguity_

## Flow diagram
```mermaid
sequenceDiagram
  participant A as Caller
  participant B as Callee
  A->>B: call
  B-->>A: response
  A->>B: ack
```

## Implementation tasks

### Task 1: Do the thing
**Files:**
- Modify: `foo.sh`

**Interfaces:**
- `foo()` does the thing.

- [ ] **Step 1:** write failing test
- [ ] **Step 2:** run it red
- [ ] **Step 3:** implement
- [ ] **Step 4:** run it green

## TDD test list
- `test one` — checks one
- `test two` — checks two
- `test three` — checks three

## Edge cases & failure modes
- edge one
- edge two
- edge three
- edge four

## Verification
- run the tests

## Checklist (machine-validated; do NOT hand-edit — call tick-checklist.sh --subplan)
- [ ] mermaid-present
- [ ] mermaid-has-entry-and-exit
- [ ] tasks-≥1
- [ ] tasks-have-files-and-interfaces
- [ ] tasks-have-tdd-steps
- [ ] tdd-list-≥3
- [ ] edges-≥4
- [ ] no-tbd-placeholders
'

# Missing mermaid/TDD/edges/clarifying-questions on purpose: the no-op stub
# above never fixes it, so this file must still be failing after 3 repairs.
# shellcheck disable=SC2016 # literal markdown fixture text, no expansion wanted
FIN_BAD_SUBPLAN='# Subplan: bad

**Lane:** `misc`

## Implementation tasks

### Task 1: Do the thing
**Files:**
- Modify: `bar.sh`

**Interfaces:**
- `bar()` does the thing.

- [ ] **Step 1:** write failing test
- [ ] **Step 2:** run it red
- [ ] **Step 3:** implement
- [ ] **Step 4:** run it green

## Verification
- run the tests
'

# count_unticked_checklist FILE — `- [ ] ` lines inside `## Checklist` only.
# The fixtures also carry `- [ ] **Step N:**` TDD boxes and deliberately
# unticked `## Superpowers invoked` declinations, neither of which
# tick-checklist.sh ever touches — counting the whole file would flag those
# as "not ticked" even on a fully passing run.
count_unticked_checklist() {
  awk '/^## Checklist/ { flag=1; next } /^## / && flag { flag=0 } flag' "$1" | grep -c '^\- \[ \] '
}

fin_new_run_dir() {
  local d
  d=$(mktemp -d)
  printf '{"timestamp":"2026-07-20T00:00:00Z","gitnexus":"fresh","graphify":"fresh"}\n' \
    >"${d}/codeintel-status.json"
  mkdir -p "${d}/subplans"
  echo "$d"
}

# Passing case: root + one already-valid subplan needs zero repairs.
#
# finalize-plan.sh's auto-format.sh step formats+commits the *current working
# directory* (the project the plan targets), not RUN_DIR — invoking it from
# this repo's own root would run `just format` and auto-commit across the
# whole dev tree. Run from RUN_DIR itself instead: a bare mktemp -d has no
# Justfile/package.json/etc. for auto-format.sh to detect, so it's a no-op,
# and finalize-plan.sh's own control flow (what's under test here) doesn't
# depend on cwd otherwise.
FIN_PASS_RUN=$(fin_new_run_dir)
printf '%s' "$FIN_ROOT_ONE_SUB" >"${FIN_PASS_RUN}/plan.md"
printf '%s' "$FIN_GOOD_SUBPLAN" >"${FIN_PASS_RUN}/subplans/good.md"
FIN_PASS_EXIT=0
(cd "$FIN_PASS_RUN" && PATH="${FIN_STUB_DIR}:${PATH}" "$FINALIZE" "$FIN_PASS_RUN") \
  >"${FIN_PASS_RUN}/stdout.log" 2>&1 || FIN_PASS_EXIT=$?
assert_eq "$FIN_PASS_EXIT" 0 "finalize-plan.sh: all-passing run exits 0"
assert_eq "$(jq -r '.status' "${FIN_PASS_RUN}/finalize-failures.json")" "pass" \
  "finalize-plan.sh: all-passing run emits status=pass"
assert_eq "$(jq -r '.attempts' "${FIN_PASS_RUN}/finalize-failures.json")" "0" \
  "finalize-plan.sh: all-passing run needed zero repair attempts"
assert_eq "$(count_unticked_checklist "${FIN_PASS_RUN}/plan.md")" "0" \
  "finalize-plan.sh: passing run ticks every root checklist item (no [ ] left)"
assert_eq "$(count_unticked_checklist "${FIN_PASS_RUN}/subplans/good.md")" "0" \
  "finalize-plan.sh: passing run ticks every subplan checklist item (no [ ] left)"
rm -rf "$FIN_PASS_RUN"

# Failing case: root + one good subplan + one permanently-broken subplan.
# The root plan's own each-subplan-has-flow-and-tdd check cascades to a
# root failure too, once the bad subplan is linked in — both must be named.
FIN_ROOT_TWO_SUB=$(printf '%s' "$FIN_ROOT_ONE_SUB" | sed 's#- \[good\](subplans/good.md)#- [good](subplans/good.md)\n- [bad](subplans/bad.md)#')
FIN_FAIL_RUN=$(fin_new_run_dir)
printf '%s' "$FIN_ROOT_TWO_SUB" >"${FIN_FAIL_RUN}/plan.md"
printf '%s' "$FIN_GOOD_SUBPLAN" >"${FIN_FAIL_RUN}/subplans/good.md"
printf '%s' "$FIN_BAD_SUBPLAN" >"${FIN_FAIL_RUN}/subplans/bad.md"
FIN_FAIL_EXIT=0
(cd "$FIN_FAIL_RUN" && PATH="${FIN_STUB_DIR}:${PATH}" "$FINALIZE" "$FIN_FAIL_RUN") \
  >"${FIN_FAIL_RUN}/stdout.log" 2>&1 || FIN_FAIL_EXIT=$?
assert_eq "$FIN_FAIL_EXIT" 1 "finalize-plan.sh: one permanently-broken subplan exits 1"
assert_eq "$(jq -r '.status' "${FIN_FAIL_RUN}/finalize-failures.json")" "fail" \
  "finalize-plan.sh: broken-subplan run emits status=fail"
assert_eq "$(jq -r '.attempts' "${FIN_FAIL_RUN}/finalize-failures.json")" "3" \
  "finalize-plan.sh: gives up after exactly 3 repair attempts"
assert_eq "$(jq -c '.failing | sort' "${FIN_FAIL_RUN}/finalize-failures.json")" \
  '["plan.md","subplans/bad.md"]' \
  "finalize-plan.sh: failure JSON names both the root and the broken subplan"
rm -rf "$FIN_FAIL_RUN"

rm -rf "$FIN_STUB_DIR"

# ─── Task 6: SKILL.md was slimmed and the Phase 4 handoff retargeted ───────

assert_eq "$([ "$(wc -l <"$SKILL_MD" | tr -d ' ')" -lt 346 ] && echo yes || echo no)" yes \
  "SKILL.md: line count is under the pre-slimming baseline of 346"
assert_contains "$(cat "$SKILL_MD")" "/deep-execute" \
  "SKILL.md: Phase 4 handoff points at /deep-execute"

# ─── Fix: must-survive rules pinned so the line-count metric can't be ──────
# satisfied by deleting load-bearing prose instead of restating it tighter.
# The two checks above only assert SKILL.md got *shorter* and still
# mentions /deep-execute — every other rule in the file could be deleted
# and this test would stay green (verified by hand: all of it currently
# survives, but a hand check does not survive the next edit). Each
# assertion below pins one rule this project has already treated as a
# recurring defect shape when it silently vanishes: the honest-receipts
# framing, the hard-gate rule, outer-boundary-only mocking, the sole
# authority to tick a Superpowers box, and the flag names themselves.
# When task 8 (cmux-orchestrator) and task 12 (deep-review) apply the same
# slimming to their own SKILL.md, extend THIS block — not the line-count
# check — with the equivalent load-bearing phrases from those files.

SKILL_MD_TEXT="$(cat "$SKILL_MD")"
assert_contains "$SKILL_MD_TEXT" "proves the script ran, not that the skill itself ran" \
  "SKILL.md: honest-receipts framing survives (tick proves the script ran, not the skill)"
assert_contains "$SKILL_MD_TEXT" "hard gate" \
  "SKILL.md: a failing finalize-plan.sh status is still called a hard gate"
assert_contains "$SKILL_MD_TEXT" "never advance" \
  "SKILL.md: the hard-gate rule still says never advance on a failing status"
assert_contains "$SKILL_MD_TEXT" "outermost boundaries" \
  "SKILL.md: TDD policy still says mocks only the outermost boundaries"
# shellcheck disable=SC2016 # literal `"$RUN_DIR"` text being matched, not expanded
assert_contains "$SKILL_MD_TEXT" 'scripts/superpowers-invoke.sh "$RUN_DIR" <skill>' \
  "SKILL.md: superpowers-invoke.sh is still named by its invocation form"
# shellcheck disable=SC2016 # literal backticked text being matched, not a command substitution
assert_contains "$SKILL_MD_TEXT" 'is the only thing permitted to tick a `## Superpowers invoked` box' \
  "SKILL.md: superpowers-invoke.sh is still the only thing permitted to tick that box"
assert_contains "$SKILL_MD_TEXT" "--no-codex" \
  "SKILL.md: the --no-codex flag is still documented"
assert_contains "$SKILL_MD_TEXT" "--skip-grill" \
  "SKILL.md: the --skip-grill flag is still documented"
assert_contains "$SKILL_MD_TEXT" "--max-plan-iter" \
  "SKILL.md: the --max-plan-iter flag is still documented"

assert_summary
