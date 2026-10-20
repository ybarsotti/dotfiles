#!/usr/bin/env bash
# check-stale.sh — does this report still describe the working tree?
#
# Usage: check-stale.sh <run-dir> [scope]
#
# collect-context.sh writes the sha256 of the reviewed diff into <run-dir>/diff.sha256 and
# the scope into <run-dir>/scope. This script rebuilds the diff for the same scope and
# compares. A report that was true for an older diff is the quiet failure this catches: the
# findings still read as current, and nothing in the file says the code moved on.
#
# Exit 0  the report matches the working tree.
# Exit 1  the code changed after the review. Re-run the panel.
# Exit 2  the run cannot be checked (no hash recorded, or the diff is now empty).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="${1:?usage: check-stale.sh <run-dir> [scope]}"
RECORDED_FILE="${RUN_DIR}/diff.sha256"

if [ ! -f "$RECORDED_FILE" ]; then
  printf 'check-stale: %s has no diff.sha256. The run predates the staleness check.\n' "$RUN_DIR" >&2
  exit 2
fi

RECORDED=$(cat "$RECORDED_FILE")
SCOPE="${2:-}"
if [ -z "$SCOPE" ]; then
  [ -f "${RUN_DIR}/scope" ] || { printf 'check-stale: no scope recorded; pass it as the second argument.\n' >&2; exit 2; }
  SCOPE=$(cat "${RUN_DIR}/scope")
fi

# Rebuild through collect-context.sh rather than reimplementing the scope rules. It owns
# how a scope becomes a diff, including the PR and single-file forms.
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

if ! "${SCRIPT_DIR}/collect-context.sh" "$TMP_DIR" "$SCOPE" >/dev/null 2>&1; then
  printf 'check-stale: cannot rebuild the diff for scope %s. The branch or the PR may be gone.\n' "$SCOPE" >&2
  exit 2
fi

CURRENT=$(cat "${TMP_DIR}/diff.sha256")

if [ "$RECORDED" = "$CURRENT" ]; then
  printf 'check-stale: report is current (scope %s, diff %s).\n' "$SCOPE" "${CURRENT:0:12}"
  exit 0
fi

printf 'check-stale: the code changed after this review.\n' >&2
printf '  reviewed diff: %s\n' "${RECORDED:0:12}" >&2
printf '  current diff:  %s\n' "${CURRENT:0:12}" >&2
printf '  scope:         %s\n' "$SCOPE" >&2
printf 'Re-run the panel on the current diff. Do not act on the findings in %s.\n' "$RUN_DIR" >&2
exit 1
