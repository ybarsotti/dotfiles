#!/usr/bin/env bash
# decision.sh — records ONE lane decision or assumption as a durable structured
# record, then announces it on the event log.
#
# Usage:
#   decision.sh RUN_DIR LANE TASK --title TITLE
#                                 [--kind decision|assumption]
#                                 [--rationale TEXT|-]
#                                 [--alternative TEXT]...
#                                 [--tradeoff TEXT]...
#
# Why this is not just a longer `event.sh` call: an events.jsonl line must stay
# single-line and under PIPE_BUF for concurrent appends to be atomic (see
# event.sh's header). Rationale, rejected alternatives and tradeoffs are
# multi-line prose that blows through both limits. So the prose lands in its own
# file and only a one-line headline goes on the event log — the log keeps its
# atomicity guarantee, and build-run-report.sh gets the full text.
#
# The record is written as JSON, not Markdown, for the same reason the rest of
# this skill reads JSON: build-run-report.sh consumes these records as data, and
# generated Markdown is never parsed back into execution data anywhere here.
#
# Concurrency: records live under lanes/<lane>/decisions/, and exactly one
# worker owns a lane, so the NNN sequence has a single writer by construction —
# no locking needed. Two lanes writing at once touch different directories.

set -eufo pipefail

if [ $# -lt 3 ]; then
  echo "Usage: decision.sh RUN_DIR LANE TASK --title TITLE [--kind decision|assumption] [--rationale TEXT|-] [--alternative TEXT]... [--tradeoff TEXT]..." >&2
  exit 2
fi

RUN_DIR="$1"
LANE="$2"
TASK="$3"
shift 3

TITLE=""
KIND="decision"
RATIONALE=""
ALTERNATIVES=()
TRADEOFFS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --title)
      [ $# -ge 2 ] || {
        echo "decision.sh: --title requires a value" >&2
        exit 2
      }
      TITLE="$2"
      shift 2
      ;;
    --kind)
      [ $# -ge 2 ] || {
        echo "decision.sh: --kind requires a value" >&2
        exit 2
      }
      KIND="$2"
      shift 2
      ;;
    --rationale)
      [ $# -ge 2 ] || {
        echo "decision.sh: --rationale requires a value (or '-' to read stdin)" >&2
        exit 2
      }
      if [ "$2" = "-" ]; then
        RATIONALE="$(cat)"
      else
        RATIONALE="$2"
      fi
      shift 2
      ;;
    --alternative)
      [ $# -ge 2 ] || {
        echo "decision.sh: --alternative requires a value" >&2
        exit 2
      }
      ALTERNATIVES+=("$2")
      shift 2
      ;;
    --tradeoff)
      [ $# -ge 2 ] || {
        echo "decision.sh: --tradeoff requires a value" >&2
        exit 2
      }
      TRADEOFFS+=("$2")
      shift 2
      ;;
    *)
      printf 'decision.sh: unknown argument %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

case "$KIND" in
  decision | assumption) ;;
  *)
    printf 'decision.sh: unknown kind "%s" (want one of: decision assumption)\n' "$KIND" >&2
    exit 1
    ;;
esac

[ -n "$TITLE" ] || {
  echo "decision.sh: --title is required and must be non-empty" >&2
  exit 1
}
case "$TITLE" in
  *$'\n'* | *$'\r'*)
    echo "decision.sh: --title must be a single line (it becomes the event headline)" >&2
    exit 1
    ;;
esac
[ -n "$RATIONALE" ] || {
  echo "decision.sh: --rationale is required — a decision with no recorded why is not worth recording" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || {
  echo "decision.sh: jq required" >&2
  exit 2
}
[ -d "$RUN_DIR" ] || {
  echo "decision.sh: no such run directory: $RUN_DIR" >&2
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolve both the source-tree name (executable_*) and the deployed name —
# chezmoi apply strips the prefix only in the deployed tree, and this skill is
# exercised from both.
EVENT="${SCRIPT_DIR}/event.sh"
[ -x "$EVENT" ] || EVENT="${SCRIPT_DIR}/executable_event.sh"
[ -x "$EVENT" ] || {
  echo "decision.sh: cannot find event.sh next to this script" >&2
  exit 2
}

DEC_DIR="${RUN_DIR}/lanes/${LANE}/decisions"
mkdir -p "$DEC_DIR"

# Next sequence number: highest existing NNN + 1, so a partially cleaned
# directory never reuses a number that already appeared in the event log.
#
# Enumerated with `find`, deliberately NOT a shell glob: `set -f` above (the
# `f` in `set -eufo pipefail`, which every script in this skill uses) disables
# pathname expansion, so a `for f in "$DEC_DIR"/*.json` loop would silently
# match nothing, leave SEQ at 1, and have each new record overwrite the lane's
# first one.
SEQ=1
while IFS= read -r f; do
  [ -n "$f" ] || continue
  n=$(basename "$f" .json)
  case "$n" in [0-9][0-9][0-9]) ;; *) continue ;; esac
  n=$((10#$n))
  [ "$n" -ge "$SEQ" ] && SEQ=$((n + 1))
done < <(find "$DEC_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null || true)
ID=$(printf '%03d' "$SEQ")
REC="${DEC_DIR}/${ID}.json"

ALT_JSON="[]"
if [ ${#ALTERNATIVES[@]} -gt 0 ]; then
  ALT_JSON=$(jq -n '$ARGS.positional' --args "${ALTERNATIVES[@]}")
fi
TRADE_JSON="[]"
if [ ${#TRADEOFFS[@]} -gt 0 ]; then
  TRADE_JSON=$(jq -n '$ARGS.positional' --args "${TRADEOFFS[@]}")
fi

jq -n \
  --arg id "$ID" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg lane "$LANE" \
  --arg task "$TASK" \
  --arg kind "$KIND" \
  --arg title "$TITLE" \
  --arg rationale "$RATIONALE" \
  --argjson alternatives "$ALT_JSON" \
  --argjson tradeoffs "$TRADE_JSON" \
  '{id:$id, ts:$ts, lane:$lane, task:$task, kind:$kind, title:$title,
    rationale:$rationale, alternatives:$alternatives, tradeoffs:$tradeoffs}' >"$REC"

# The event headline must survive event.sh's single-line + size limits, so the
# title is truncated here rather than letting event.sh reject the whole call and
# lose the record's announcement.
SHORT_TITLE="$TITLE"
if [ "${#SHORT_TITLE}" -gt 200 ]; then
  SHORT_TITLE="${SHORT_TITLE:0:197}..."
fi

"$EVENT" "$RUN_DIR" "$LANE" "$TASK" decision \
  "${KIND}: ${SHORT_TITLE} (lanes/${LANE}/decisions/${ID}.json)"

printf '%s\n' "$REC"
