#!/usr/bin/env bash
set -eufo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
# shellcheck source=/dev/null
. "${ROOT}/dot_claude/skills/_shared/executable_assert.sh"
SCHEMA="${ROOT}/dot_claude/skills/deep-execute/schemas/run-state.schema.json"

assert_exit 0 test -f "$SCHEMA"
# shellcheck disable=SC2016  # $schema is a literal jq key, not a shell expansion
assert_exit 0 jq -e '
  .["$schema"] == "https://json-schema.org/draft/2020-12/schema" and
  (.properties.manifest.required | index("baseline_commit")) != null and
  (.properties.event.properties.type.enum | length) == 7
' "$SCHEMA"
assert_summary
