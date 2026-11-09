#!/usr/bin/env bash
# finish-run.sh — the gate on Phase 5, and the delivery of what it produced.
#
# Usage:
#   finish-run.sh RUN_DIR [--qa PATH] [--no-open]
#
# Why this exists. Every other phase of a run refuses to advance on failure: init-run.sh will
# not start on an invalid plan, round-gate.sh will not advance a failing round,
# validate-run-state.sh rejects a write outside a lane. Phase 5 had no such gate, so skipping
# the run report cost nothing and nothing failed — and across three real runs the report was
# never built once. A step with no enforcement at the end of a long unattended chain is the step
# that gets dropped.
#
# It also opens the page with `open` (macOS) instead of only printing a path, which is easy to
# miss in terminal scrollback. Without `open`, or with `--no-open` for a headless or cron run,
# it prints the path.
#
# The gate checks the report was really RENDERED, not merely created: an empty or truncated file
# would otherwise pass a bare existence test and report success on a run with no report.
set -eufo pipefail

RUN_DIR="${1:-}"
if [ -z "$RUN_DIR" ] || [ ! -d "$RUN_DIR" ]; then
	echo "finish-run.sh: usage: finish-run.sh RUN_DIR [--qa PATH] [--no-open]" >&2
	exit 2
fi
shift

QA_REPORT=""
OPEN=1
while [ $# -gt 0 ]; do
	case "$1" in
	--qa)
		[ $# -ge 2 ] || {
			echo "finish-run.sh: --qa requires a PATH" >&2
			exit 2
		}
		QA_REPORT="$2"
		shift 2
		;;
	--no-open)
		OPEN=0
		shift
		;;
	*)
		echo "finish-run.sh: unknown argument '$1'" >&2
		exit 2
		;;
	esac
done

REPORT="${RUN_DIR}/report/index.html"
FAILED=0

if [ ! -f "$REPORT" ]; then
	echo "finish-run.sh: FAIL — no run report at ${REPORT}" >&2
	echo "  build it first: build-run-report.sh ${RUN_DIR} --final-sha <sha> [--review ...] [--qa ...] [--pr ...]" >&2
	exit 1
fi

# `build-run-report.sh` always writes this title. Its absence means the file is a stub, a
# truncated write, or something else entirely — not a report.
if ! grep -q '<title>deep-execute run report</title>' "$REPORT"; then
	echo "finish-run.sh: FAIL — ${REPORT} exists but was not rendered by build-run-report.sh" >&2
	FAILED=1
fi

BYTES=$(wc -c <"$REPORT" | tr -d ' ')
if [ "$BYTES" -lt 2048 ]; then
	echo "finish-run.sh: FAIL — ${REPORT} is only ${BYTES} bytes; a real report is larger" >&2
	FAILED=1
fi

if [ -n "$QA_REPORT" ] && [ ! -f "$QA_REPORT" ]; then
	echo "finish-run.sh: FAIL — QA report named but missing: ${QA_REPORT}" >&2
	FAILED=1
fi

[ "$FAILED" -eq 0 ] || exit 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SET_PHASE="${SCRIPT_DIR}/set-phase.sh"
[ -f "$SET_PHASE" ] || SET_PHASE="${SCRIPT_DIR}/executable_set-phase.sh"
if [ -x "$SET_PHASE" ] && [ -f "${RUN_DIR}/status.json" ]; then
	"$SET_PHASE" "$RUN_DIR" complete >/dev/null
fi

if [ "$OPEN" -eq 1 ] && command -v open >/dev/null 2>&1; then
	open "$REPORT" >/dev/null 2>&1 || echo "finish-run.sh: could not open the report; it is at ${REPORT}" >&2
	if [ -n "$QA_REPORT" ]; then
		open "$QA_REPORT" >/dev/null 2>&1 || true
	fi
fi

echo "run report: ${REPORT}"
[ -n "$QA_REPORT" ] && echo "qa report:  ${QA_REPORT}"
exit 0
