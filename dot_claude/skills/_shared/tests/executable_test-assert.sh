#!/usr/bin/env bash
# Self-test for the shared assertion harness (executable_assert.sh).
# Regression coverage for the bug where assert_exit ran the tested command
# as a bare statement, so a failing command aborted the whole script under
# `set -e` before the pass/fail comparison ever ran.
set -eufo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
ASSERT_SH="${ROOT}/dot_claude/skills/_shared/executable_assert.sh"

# shellcheck source=/dev/null
. "$ASSERT_SH"

# run_case SNIPPET — runs SNIPPET in a fresh bash process that sources the
# harness under `set -eufo pipefail`, mirroring real test scripts. Captures
# combined output/exit code into CASE_OUTPUT/CASE_EXIT without letting a
# non-zero exit trip the outer script's own -e.
run_case() {
  local snippet="$1"
  local out
  local rc=0
  out=$(bash -c '
    set -eufo pipefail
    # shellcheck source=/dev/null
    . "$1"
    eval "$2"
  ' _ "$ASSERT_SH" "$snippet" 2>&1) || rc=$?
  CASE_OUTPUT="$out"
  CASE_EXIT="$rc"
}

# --- assert_exit must not abort the caller under `set -e` ---
run_case 'echo before; assert_exit 0 false; echo after; assert_summary'
assert_contains "$CASE_OUTPUT" "before" "assert_exit survivor: reaches the statement before the failing assertion"
assert_contains "$CASE_OUTPUT" "FAIL:" "assert_exit survivor: prints a FAIL: line instead of aborting"
assert_contains "$CASE_OUTPUT" "after" "assert_exit survivor: execution continues past the failing assertion"
assert_contains "$CASE_OUTPUT" "0 passed, 1 failed" "assert_exit survivor: tally reflects the one failure"
assert_eq "$CASE_EXIT" "1" "assert_exit survivor: assert_summary exits non-zero on failure"

# --- asserting an expected non-zero exit must itself pass ---
run_case 'assert_exit 1 false; assert_summary'
assert_contains "$CASE_OUTPUT" "ok:" "assert_exit 1 false: passes (expected non-zero exit observed)"
assert_contains "$CASE_OUTPUT" "1 passed, 0 failed" "assert_exit 1 false: tally shows one pass"
assert_eq "$CASE_EXIT" "0" "assert_exit 1 false: assert_summary exits zero (no failures)"

# --- baseline: asserting an expected zero exit still passes ---
run_case 'assert_exit 0 true; assert_summary'
assert_contains "$CASE_OUTPUT" "ok:" "assert_exit 0 true: passes"
assert_eq "$CASE_EXIT" "0" "assert_exit 0 true: assert_summary exits zero"

# --- assert_eq / assert_contains: pass cases ---
run_case 'assert_eq "foo" "foo" "eq pass"; assert_contains "needle-in-haystack" "needle" "contains pass"; assert_summary'
assert_contains "$CASE_OUTPUT" "ok: eq pass" "assert_eq: pass case prints ok:"
assert_contains "$CASE_OUTPUT" "ok: contains pass" "assert_contains: pass case prints ok:"
assert_contains "$CASE_OUTPUT" "2 passed, 0 failed" "assert_eq/assert_contains: tally shows both passes"
assert_eq "$CASE_EXIT" "0" "assert_eq/assert_contains: assert_summary exits zero"

# --- assert_eq / assert_contains: fail cases ---
run_case 'assert_eq "foo" "bar" "eq fail"; assert_contains "haystack" "missing" "contains fail"; assert_summary'
assert_contains "$CASE_OUTPUT" "FAIL: eq fail" "assert_eq: fail case prints FAIL:"
assert_contains "$CASE_OUTPUT" "FAIL: contains fail" "assert_contains: fail case prints FAIL:"
assert_contains "$CASE_OUTPUT" "0 passed, 2 failed" "assert_eq/assert_contains: tally shows both failures"
assert_eq "$CASE_EXIT" "1" "assert_eq/assert_contains: assert_summary exits non-zero on failure"

assert_summary
