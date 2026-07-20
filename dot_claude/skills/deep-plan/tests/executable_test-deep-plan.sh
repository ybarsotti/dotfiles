#!/usr/bin/env bash
set -eufo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
# shellcheck source=/dev/null
. "${ROOT}/dot_claude/skills/_shared/executable_assert.sh"
PARSER="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_plan-to-json.sh"
FIXTURE="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/valid-parallel-plan.md"

JSON=$("$PARSER" "$FIXTURE")
assert_eq "$(jq -r '.mode' <<<"$JSON")" parallel "mode"
assert_eq "$(jq '.lanes | length' <<<"$JSON")" 4 "lane count"
assert_eq "$(jq -r '.contract.version' <<<"$JSON")" 1.0.0 "contract version"
assert_eq "$(jq '.tasks | all(.lane != null)' <<<"$JSON")" true "task lanes"
assert_summary
