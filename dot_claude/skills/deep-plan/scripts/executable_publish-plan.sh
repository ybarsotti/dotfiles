#!/usr/bin/env bash
# publish-plan.sh — copies the approved plan into the project with everything
# that validates it, stamps the copy and validates it there.
#
# Usage:
#   publish-plan.sh RUN_DIR DEST_DIR
#
# RUN_DIR is the deep-plan run directory; DEST_DIR is usually
# $PROJECT_ROOT/docs/superpowers/plans/YYYY-MM-DD-<slug>. It copies plan.md,
# subplans/, codeintel-status.json and superpowers-receipts.log: the last two
# are read by `validate-plan.sh --root` (code-intel-bootstrapped and
# superpowers-ticks-have-receipts), and /deep-execute's init-run.sh runs that
# check on the published copy. Then it runs `plan-stamp.sh approve` on the
# copy and `validate-plan.sh --root` from the project root that holds DEST_DIR.
#
# It prints the published plan path. The caller commits DEST_DIR.
# Exit 1 when a bundle file is missing or the copy fails validation.
set -eufo pipefail

[ $# -eq 2 ] || {
  echo "Usage: publish-plan.sh RUN_DIR DEST_DIR" >&2
  exit 2
}
RUN_DIR="$1"
DEST="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_PLAN="${SCRIPT_DIR}/validate-plan.sh"
[ -f "$VALIDATE_PLAN" ] || VALIDATE_PLAN="${SCRIPT_DIR}/executable_validate-plan.sh"
PLAN_STAMP="${SCRIPT_DIR}/../../_shared/plan-stamp.sh"
[ -f "$PLAN_STAMP" ] || PLAN_STAMP="${SCRIPT_DIR}/../../_shared/executable_plan-stamp.sh"

for f in plan.md codeintel-status.json; do
  [ -f "${RUN_DIR}/${f}" ] || {
    echo "publish-plan.sh: missing ${RUN_DIR}/${f}" >&2
    exit 1
  }
done

mkdir -p "$DEST"
cp "${RUN_DIR}/plan.md" "${RUN_DIR}/codeintel-status.json" "$DEST/"
[ ! -f "${RUN_DIR}/superpowers-receipts.log" ] || cp "${RUN_DIR}/superpowers-receipts.log" "$DEST/"
[ ! -d "${RUN_DIR}/subplans" ] || cp -R "${RUN_DIR}/subplans" "$DEST/"

PLAN="$(cd "$DEST" && pwd)/plan.md"
bash "$PLAN_STAMP" approve "$PLAN" >/dev/null

ROOT=$(git -C "$DEST" rev-parse --show-toplevel 2>/dev/null) || {
  echo "publish-plan.sh: ${DEST} is not inside a git repository" >&2
  exit 1
}
RESULT=$(cd "$ROOT" && "$VALIDATE_PLAN" "$PLAN" --root --json) || {
  echo "publish-plan.sh: the published copy fails validate-plan.sh --root:" >&2
  jq -r '.[] | select(.status == "fail") | "  - " + .item + ": " + .detail' <<<"$RESULT" >&2
  exit 1
}
printf '%s\n' "$PLAN"
