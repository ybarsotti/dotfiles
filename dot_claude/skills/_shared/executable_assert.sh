#!/usr/bin/env bash
# Shared shell assertion harness for the deep-* pipeline test suites.
# Sourced by tests; must not abort on a failing assertion so that
# assert_summary can still print the final tally.
set -uo pipefail

: "${ASSERT_PASS:=0}"
: "${ASSERT_FAIL:=0}"

# assert_eq ACTUAL EXPECTED LABEL
assert_eq() {
  local actual="$1" expected="$2" label="$3"
  if [ "$actual" = "$expected" ]; then
    ASSERT_PASS=$((ASSERT_PASS + 1))
    echo "ok: ${label}"
  else
    ASSERT_FAIL=$((ASSERT_FAIL + 1))
    echo "FAIL: ${label} (got ${actual}, want ${expected})"
  fi
}

# assert_contains HAYSTACK NEEDLE LABEL
assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [ "${haystack#*"$needle"}" != "$haystack" ]; then
    ASSERT_PASS=$((ASSERT_PASS + 1))
    echo "ok: ${label}"
  else
    ASSERT_FAIL=$((ASSERT_FAIL + 1))
    echo "FAIL: ${label} (got ${haystack}, want to contain ${needle})"
  fi
}

# assert_exit CODE CMD...
assert_exit() {
  local expected="$1"
  shift
  local label="$*"
  local actual
  "$@" >/dev/null 2>&1
  actual=$?
  if [ "$actual" -eq "$expected" ]; then
    ASSERT_PASS=$((ASSERT_PASS + 1))
    echo "ok: ${label}"
  else
    ASSERT_FAIL=$((ASSERT_FAIL + 1))
    echo "FAIL: ${label} (got ${actual}, want ${expected})"
  fi
}

# assert_summary — prints the tally, returns non-zero if any assertion failed.
assert_summary() {
  echo "${ASSERT_PASS} passed, ${ASSERT_FAIL} failed"
  [ "$ASSERT_FAIL" -eq 0 ]
}
