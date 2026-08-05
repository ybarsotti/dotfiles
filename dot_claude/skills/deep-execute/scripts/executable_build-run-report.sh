#!/usr/bin/env bash
# build-run-report.sh — renders a self-contained HTML report for a finished
# deep-execute run: what was built, which decisions and assumptions each lane
# recorded, where the run drifted from the approved plan, and how it was
# verified.
#
# Usage:
#   build-run-report.sh RUN_DIR [--out PATH] [--final-sha SHA]
#                               [--review PATH] [--qa PATH] [--pr URL]
#                               [--title TEXT]
#
#   --out PATH        where to write (default RUN_DIR/report/index.html)
#   --final-sha SHA   the frozen SHA the run ended on (default: HEAD of the
#                     manifest's cwd, if it still resolves)
#   --review PATH     a /deep-review report.md to embed
#   --qa PATH         the /qa-execute index.html to link as evidence
#   --pr URL          the pull request this run opened
#   --title TEXT      report heading (default: the run id)
#
# Every input is read from disk — manifest.json, events.jsonl, the per-lane
# decision records, the approved plan, git — so this is reproducible after the
# fact and safe to re-run. Nothing here re-derives state by asking a model.
#
# Scope, stated plainly: this reports what the run RECORDED. A decision a lane
# never wrote through decision.sh does not appear, and no absence here is
# evidence that a decision was not made. The same caveat the skill already
# carries about self-declared attribution applies to this report's per-lane
# sections.

set -eufo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: build-run-report.sh RUN_DIR [--out PATH] [--final-sha SHA] [--review PATH] [--qa PATH] [--pr URL] [--title TEXT]" >&2
  exit 2
fi

RUN_DIR="$1"
shift

OUT=""
FINAL_SHA=""
REVIEW=""
QA=""
PR=""
TITLE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      [ $# -ge 2 ] || {
        echo "build-run-report.sh: --out requires a PATH" >&2
        exit 2
      }
      OUT="$2"
      shift 2
      ;;
    --final-sha)
      [ $# -ge 2 ] || {
        echo "build-run-report.sh: --final-sha requires a SHA" >&2
        exit 2
      }
      FINAL_SHA="$2"
      shift 2
      ;;
    --review)
      [ $# -ge 2 ] || {
        echo "build-run-report.sh: --review requires a PATH" >&2
        exit 2
      }
      REVIEW="$2"
      shift 2
      ;;
    --qa)
      [ $# -ge 2 ] || {
        echo "build-run-report.sh: --qa requires a PATH" >&2
        exit 2
      }
      QA="$2"
      shift 2
      ;;
    --pr)
      [ $# -ge 2 ] || {
        echo "build-run-report.sh: --pr requires a URL" >&2
        exit 2
      }
      PR="$2"
      shift 2
      ;;
    --title)
      [ $# -ge 2 ] || {
        echo "build-run-report.sh: --title requires a value" >&2
        exit 2
      }
      TITLE="$2"
      shift 2
      ;;
    *)
      printf 'build-run-report.sh: unknown argument %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  echo "build-run-report.sh: jq required" >&2
  exit 2
}
[ -d "$RUN_DIR" ] || {
  echo "build-run-report.sh: no such run directory: $RUN_DIR" >&2
  exit 2
}

MANIFEST="${RUN_DIR}/manifest.json"
[ -f "$MANIFEST" ] || {
  echo "build-run-report.sh: no manifest.json in $RUN_DIR — is this a deep-execute run directory?" >&2
  exit 1
}
jq -e . "$MANIFEST" >/dev/null 2>&1 || {
  echo "build-run-report.sh: manifest.json is not valid JSON: $MANIFEST" >&2
  exit 1
}

EVENTS="${RUN_DIR}/events.jsonl"
[ -n "$OUT" ] || OUT="${RUN_DIR}/report/index.html"
mkdir -p "$(dirname "$OUT")"

RUN_ID=$(jq -r '.run_id // "unknown"' "$MANIFEST")
PLAN_PATH=$(jq -r '.plan_path // ""' "$MANIFEST")
CWD=$(jq -r '.cwd // ""' "$MANIFEST")
BASELINE=$(jq -r '.baseline_commit // ""' "$MANIFEST")
ROUND=$(jq -r '.round // 0' "$MANIFEST")
MAX_ROUNDS=$(jq -r '.max_rounds // 0' "$MANIFEST")
CONTRACT_VERSION=$(jq -r '.contract.version // ""' "$MANIFEST")
CONTRACT_PATH=$(jq -r '.contract.path // ""' "$MANIFEST")
CONTRACT_KIND=$(jq -r '.contract.kind // ""' "$MANIFEST")
CONTRACT_SHA=$(jq -r '.contract.sha256 // ""' "$MANIFEST")
[ -n "$TITLE" ] || TITLE="$RUN_ID"
GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ─── Helpers ───────────────────────────────────────────────────────────────

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
escs() { printf '%s' "${1-}" | esc; }

emit() { printf '%s\n' "$*" >>"$OUT"; }

# pre_block TEXT — free-text prose (rationale, a plan section, a review report)
# rendered verbatim inside <pre>. This script deliberately does NOT implement a
# Markdown renderer: showing the source exactly as written is honest, and a
# half-parser that silently mangles a table or a code fence is not.
pre_block() {
  {
    printf '<pre class="txt">'
    printf '%s' "${1-}" | esc
    printf '</pre>\n'
  } >>"$OUT"
}

# plan_section HEADING — the body of one `## HEADING` section of the plan.
plan_section() {
  [ -f "$PLAN_PATH" ] || return 0
  awk -v want="## $1" '
    $0 == want { grabbing = 1; next }
    grabbing && /^## / { exit }
    grabbing { print }
  ' "$PLAN_PATH"
}

# ─── Git: what was actually built between baseline and the frozen SHA ──────

GIT_OK=0
if [ -n "$CWD" ] && [ -d "$CWD" ] && git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
  GIT_OK=1
  if [ -z "$FINAL_SHA" ]; then
    FINAL_SHA=$(git -C "$CWD" rev-parse HEAD 2>/dev/null || echo "")
  fi
fi

DIFF_NOTE=""
DIFF_ROWS=""
FILES_CHANGED=0
ADDED=0
REMOVED=0
COMMIT_COUNT=""
if [ "$GIT_OK" = "1" ] && [ -n "$BASELINE" ] && [ -n "$FINAL_SHA" ]; then
  if git -C "$CWD" cat-file -e "${BASELINE}^{commit}" 2>/dev/null &&
    git -C "$CWD" cat-file -e "${FINAL_SHA}^{commit}" 2>/dev/null; then
    DIFF_ROWS=$(git -C "$CWD" diff --numstat "$BASELINE" "$FINAL_SHA" 2>/dev/null || true)
    COMMIT_COUNT=$(git -C "$CWD" rev-list --count "${BASELINE}..${FINAL_SHA}" 2>/dev/null || echo "")
    if [ -n "$DIFF_ROWS" ]; then
      while IFS=$'\t' read -r a r _p; do
        [ -z "${_p:-}" ] && continue
        FILES_CHANGED=$((FILES_CHANGED + 1))
        case "$a" in '' | *[!0-9]*) a=0 ;; esac
        case "$r" in '' | *[!0-9]*) r=0 ;; esac
        ADDED=$((ADDED + a))
        REMOVED=$((REMOVED + r))
      done <<<"$DIFF_ROWS"
    fi
  else
    DIFF_NOTE="baseline or final commit no longer resolves in ${CWD} — diff omitted"
  fi
elif [ "$GIT_OK" != "1" ]; then
  DIFF_NOTE="the manifest's cwd is not a reachable git repository — diff omitted"
else
  DIFF_NOTE="no frozen SHA available — pass --final-sha to include the diff"
fi

# ─── Plan-derived lane shape (owns / depends_on / test_command) ────────────
# The manifest tracks runner/effort/status; the lane BOUNDARIES live in the
# plan's Execution shape. Parsed through deep-plan's own parser rather than
# re-derived here, so the report can never disagree with what init-run.sh read.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEEP_PLAN_SCRIPTS="${SCRIPT_DIR}/../../deep-plan/scripts"
PARSER="${DEEP_PLAN_SCRIPTS}/plan-to-json.sh"
[ -f "$PARSER" ] || PARSER="${DEEP_PLAN_SCRIPTS}/executable_plan-to-json.sh"

PLAN_JSON=""
PLAN_NOTE=""
if [ -f "$PLAN_PATH" ] && [ -x "$PARSER" ]; then
  PLAN_JSON=$("$PARSER" "$PLAN_PATH" 2>/dev/null || echo "")
fi
if [ -z "$PLAN_JSON" ]; then
  if [ ! -f "$PLAN_PATH" ]; then
    PLAN_NOTE="the approved plan is no longer at ${PLAN_PATH} — lane boundaries and plan rationale omitted"
  else
    PLAN_NOTE="deep-plan's plan-to-json.sh could not parse ${PLAN_PATH} — lane boundaries omitted"
  fi
fi

PLAN_CONTRACT_VERSION=""
if [ -n "$PLAN_JSON" ]; then
  PLAN_CONTRACT_VERSION=$(jq -r '.contract.version // ""' <<<"$PLAN_JSON")
fi

# ─── Write the document ────────────────────────────────────────────────────

: >"$OUT"

cat >>"$OUT" <<'HTML_HEAD'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>deep-execute run report</title>
<style>
:root {
  --bg: #ffffff; --fg: #1c1c1e; --muted: #6b7280; --line: #e5e7eb;
  --card: #f9fafb; --accent: #2563eb; --warn: #b45309; --bad: #b91c1c; --good: #15803d;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #16181d; --fg: #e6e6e6; --muted: #9aa1ad; --line: #2c313a;
    --card: #1d2027; --accent: #7aa2f7; --warn: #e0af68; --bad: #f7768e; --good: #9ece6a;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0; padding: 2rem 1.25rem 5rem; background: var(--bg); color: var(--fg);
  font: 15px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
}
main { max-width: 60rem; margin: 0 auto; }
h1 { font-size: 1.7rem; margin: 0 0 .25rem; }
h2 { font-size: 1.15rem; margin: 2.5rem 0 .75rem; padding-bottom: .35rem; border-bottom: 1px solid var(--line); }
h3 { font-size: 1rem; margin: 1.5rem 0 .4rem; }
p { margin: .5rem 0; }
a { color: var(--accent); }
.sub { color: var(--muted); margin: 0 0 1.5rem; font-size: .9rem; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(13rem, 1fr)); gap: .75rem; margin: 1rem 0; }
.kv { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: .7rem .85rem; }
.kv .k { display: block; color: var(--muted); font-size: .75rem; text-transform: uppercase; letter-spacing: .04em; }
.kv .v { display: block; margin-top: .2rem; word-break: break-word; font-variant-numeric: tabular-nums; }
.scroll { overflow-x: auto; -webkit-overflow-scrolling: touch; }
table { border-collapse: collapse; width: 100%; min-width: 30rem; font-size: .9rem; }
th, td { text-align: left; padding: .45rem .6rem; border-bottom: 1px solid var(--line); vertical-align: top; }
th { color: var(--muted); font-weight: 600; font-size: .78rem; text-transform: uppercase; letter-spacing: .04em; }
code, pre, .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
pre.txt {
  background: var(--card); border: 1px solid var(--line); border-radius: 8px;
  padding: .8rem .9rem; overflow-x: auto; white-space: pre-wrap; word-break: break-word;
  font-size: .85rem; margin: .5rem 0;
}
.badge { display: inline-block; padding: .05rem .45rem; border-radius: 999px; font-size: .75rem; border: 1px solid var(--line); }
.b-done { color: var(--good); border-color: var(--good); }
.b-blocked, .b-question { color: var(--warn); border-color: var(--warn); }
.b-decision { color: var(--accent); border-color: var(--accent); }
.note { color: var(--muted); font-size: .88rem; font-style: italic; }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: .9rem 1rem; margin: .8rem 0; }
.card h3 { margin-top: 0; }
ul { margin: .35rem 0 .35rem 1.1rem; padding: 0; }
li { margin: .2rem 0; }
details { margin: .6rem 0; }
summary { cursor: pointer; color: var(--accent); }
footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid var(--line); color: var(--muted); font-size: .82rem; }
</style>
</head>
<body>
<main>
HTML_HEAD

emit "<h1>$(escs "$TITLE")</h1>"
emit "<p class=\"sub\">deep-execute run report &middot; generated $(escs "$GENERATED_AT")</p>"

# ─── Run facts ─────────────────────────────────────────────────────────────

emit '<h2>Run</h2>'
emit '<div class="grid">'
emit "<div class=\"kv\"><span class=\"k\">Run id</span><span class=\"v mono\">$(escs "$RUN_ID")</span></div>"
emit "<div class=\"kv\"><span class=\"k\">Rounds used</span><span class=\"v\">$(escs "$ROUND") of $(escs "$MAX_ROUNDS") allowed</span></div>"
emit "<div class=\"kv\"><span class=\"k\">Baseline commit</span><span class=\"v mono\">$(escs "${BASELINE:0:12}")</span></div>"
emit "<div class=\"kv\"><span class=\"k\">Final commit</span><span class=\"v mono\">$(escs "${FINAL_SHA:0:12}")</span></div>"
emit "<div class=\"kv\"><span class=\"k\">Contract</span><span class=\"v mono\">$(escs "$CONTRACT_VERSION") ($(escs "$CONTRACT_KIND"))</span></div>"
emit "<div class=\"kv\"><span class=\"k\">Contract file</span><span class=\"v mono\">$(escs "$CONTRACT_PATH")</span></div>"
emit '</div>'
emit "<p class=\"note\">Plan: <span class=\"mono\">$(escs "$PLAN_PATH")</span><br>Worktree: <span class=\"mono\">$(escs "$CWD")</span><br>Contract sha256: <span class=\"mono\">$(escs "$CONTRACT_SHA")</span></p>"

# ─── What was built ────────────────────────────────────────────────────────

emit '<h2>What was built</h2>'
if [ -n "$DIFF_NOTE" ]; then
  emit "<p class=\"note\">$(escs "$DIFF_NOTE")</p>"
elif [ "$FILES_CHANGED" -eq 0 ]; then
  emit '<p class="note">No file changes between the baseline and the final commit.</p>'
else
  emit '<div class="grid">'
  emit "<div class=\"kv\"><span class=\"k\">Files changed</span><span class=\"v\">${FILES_CHANGED}</span></div>"
  emit "<div class=\"kv\"><span class=\"k\">Lines added</span><span class=\"v\">${ADDED}</span></div>"
  emit "<div class=\"kv\"><span class=\"k\">Lines removed</span><span class=\"v\">${REMOVED}</span></div>"
  emit "<div class=\"kv\"><span class=\"k\">Commits</span><span class=\"v\">$(escs "${COMMIT_COUNT:-?}")</span></div>"
  emit '</div>'
  emit '<details><summary>Per-file diffstat</summary><div class="scroll"><table>'
  emit '<tr><th>File</th><th>+</th><th>&minus;</th></tr>'
  while IFS=$'\t' read -r a r p; do
    [ -z "${p:-}" ] && continue
    emit "<tr><td class=\"mono\">$(escs "$p")</td><td>$(escs "$a")</td><td>$(escs "$r")</td></tr>"
  done <<<"$DIFF_ROWS"
  emit '</table></div></details>'
fi

# ─── Lanes ─────────────────────────────────────────────────────────────────

emit '<h2>Lanes</h2>'
[ -n "$PLAN_NOTE" ] && emit "<p class=\"note\">$(escs "$PLAN_NOTE")</p>"
emit '<div class="scroll"><table>'
emit '<tr><th>Lane</th><th>Agent</th><th>Task</th><th>Owns</th><th>Depends on</th><th>Test command</th></tr>'
while IFS=$'\t' read -r lane runner effort task; do
  [ -z "$lane" ] && continue
  owns=""
  deps=""
  testcmd=""
  if [ -n "$PLAN_JSON" ]; then
    owns=$(jq -r --arg l "$lane" '[.lanes[]? | select(.name==$l) | .owns[]?] | join(", ")' <<<"$PLAN_JSON" 2>/dev/null || echo "")
    deps=$(jq -r --arg l "$lane" '[.lanes[]? | select(.name==$l) | .depends_on[]?] | join(", ")' <<<"$PLAN_JSON" 2>/dev/null || echo "")
    testcmd=$(jq -r --arg l "$lane" '[.lanes[]? | select(.name==$l) | .test_command] | map(select(. != null)) | first // ""' <<<"$PLAN_JSON" 2>/dev/null || echo "")
  fi
  emit "<tr><td class=\"mono\">$(escs "$lane")</td><td>$(escs "$runner") $(escs "$effort")</td><td>$(escs "$task")</td><td class=\"mono\">$(escs "$owns")</td><td class=\"mono\">$(escs "$deps")</td><td class=\"mono\">$(escs "$testcmd")</td></tr>"
done < <(jq -r '.workers[]? | [.lane, .runner, .effort, (.task // "")] | @tsv' "$MANIFEST")
emit '</table></div>'

# ─── Decisions and assumptions recorded during the run ─────────────────────

emit '<h2>Decisions and assumptions recorded during the run</h2>'
DEC_FILES=()
while IFS= read -r f; do
  [ -n "$f" ] && DEC_FILES+=("$f")
done < <(find "${RUN_DIR}/lanes" -type f -path '*/decisions/*.json' 2>/dev/null | sort || true)

if [ ${#DEC_FILES[@]} -eq 0 ]; then
  emit '<p class="note">No lane recorded a decision or assumption through decision.sh during this run. That is an absence of records, not evidence that no decisions were made.</p>'
else
  emit "<p class=\"note\">${#DEC_FILES[@]} record(s), as written by the lanes themselves.</p>"
  for f in "${DEC_FILES[@]}"; do
    jq -e . "$f" >/dev/null 2>&1 || {
      emit "<p class=\"note\">Skipped an unreadable decision record: $(escs "$f")</p>"
      continue
    }
    d_kind=$(jq -r '.kind // "decision"' "$f")
    d_title=$(jq -r '.title // ""' "$f")
    d_lane=$(jq -r '.lane // ""' "$f")
    d_task=$(jq -r '.task // ""' "$f")
    d_ts=$(jq -r '.ts // ""' "$f")
    d_rationale=$(jq -r '.rationale // ""' "$f")
    emit '<div class="card">'
    emit "<h3><span class=\"badge b-decision\">$(escs "$d_kind")</span> $(escs "$d_title")</h3>"
    emit "<p class=\"note\">lane <span class=\"mono\">$(escs "$d_lane")</span> &middot; task <span class=\"mono\">$(escs "$d_task")</span> &middot; $(escs "$d_ts")</p>"
    emit '<p><strong>Rationale</strong></p>'
    pre_block "$d_rationale"
    if [ "$(jq -r '.alternatives | length' "$f")" -gt 0 ]; then
      emit '<p><strong>Alternatives considered and rejected</strong></p><ul>'
      while IFS= read -r alt; do
        [ -z "$alt" ] && continue
        emit "<li>$(escs "$alt")</li>"
      done < <(jq -r '.alternatives[]?' "$f")
      emit '</ul>'
    fi
    if [ "$(jq -r '.tradeoffs | length' "$f")" -gt 0 ]; then
      emit '<p><strong>Tradeoffs accepted</strong></p><ul>'
      while IFS= read -r tr; do
        [ -z "$tr" ] && continue
        emit "<li>$(escs "$tr")</li>"
      done < <(jq -r '.tradeoffs[]?' "$f")
      emit '</ul>'
    fi
    emit '</div>'
  done
fi

# ─── Decisions taken BEFORE the run, from the approved plan ────────────────

RATIONALE_SECTION=$(plan_section "Rationale & key decisions")
ABSTRACTIONS_SECTION=$(plan_section "Abstractions decision log")
if [ -n "$RATIONALE_SECTION" ] || [ -n "$ABSTRACTIONS_SECTION" ]; then
  emit '<h2>Decisions taken before the run (from the approved plan)</h2>'
  if [ -n "$RATIONALE_SECTION" ]; then
    emit '<h3>Rationale &amp; key decisions</h3>'
    pre_block "$RATIONALE_SECTION"
  fi
  if [ -n "$ABSTRACTIONS_SECTION" ]; then
    emit '<h3>Abstractions decision log</h3>'
    pre_block "$ABSTRACTIONS_SECTION"
  fi
fi

# ─── Drift from the approved plan ──────────────────────────────────────────

emit '<h2>Drift from the approved plan</h2>'
DRIFT_SEEN=0
if [ -n "$PLAN_CONTRACT_VERSION" ] && [ "$PLAN_CONTRACT_VERSION" != "$CONTRACT_VERSION" ]; then
  DRIFT_SEEN=1
  emit "<p><strong>Contract moved.</strong> The plan declared <span class=\"mono\">$(escs "$PLAN_CONTRACT_VERSION")</span>; the run ended on <span class=\"mono\">$(escs "$CONTRACT_VERSION")</span> — the contract was renegotiated mid-run.</p>"
fi
if [ "$ROUND" -gt 1 ]; then
  DRIFT_SEEN=1
  emit "<p><strong>${ROUND} rounds.</strong> Work did not converge in a single round; each extra round is a gate that failed or a lane that needed waking again.</p>"
fi
BLOCKED_COUNT=0
if [ -s "$EVENTS" ]; then
  BLOCKED_COUNT=$(jq -rs '[.[] | select(.type=="blocked")] | length' "$EVENTS" 2>/dev/null || echo 0)
fi
if [ "$BLOCKED_COUNT" -gt 0 ]; then
  DRIFT_SEEN=1
  emit "<p><strong>${BLOCKED_COUNT} blocked event(s).</strong> Each is a lane that stopped rather than guessing past a blocker.</p>"
  emit '<div class="scroll"><table><tr><th>When</th><th>Lane</th><th>Blocked on</th></tr>'
  while IFS=$'\t' read -r b_ts b_lane b_msg; do
    [ -z "$b_lane" ] && continue
    emit "<tr><td class=\"mono\">$(escs "$b_ts")</td><td class=\"mono\">$(escs "$b_lane")</td><td>$(escs "$b_msg")</td></tr>"
  done < <(jq -rs '.[] | select(.type=="blocked") | [.ts, .lane, .msg] | @tsv' "$EVENTS")
  emit '</table></div>'
fi
[ "$DRIFT_SEEN" = "0" ] && emit '<p class="note">One round, no blocked lanes, contract version unchanged from the approved plan.</p>'

# ─── Final board ───────────────────────────────────────────────────────────

emit '<h2>Final lane status</h2>'
if [ -s "$EVENTS" ]; then
  emit '<div class="scroll"><table><tr><th>Lane</th><th>Task</th><th>Status</th><th>Last message</th></tr>'
  while IFS=$'\t' read -r f_lane f_task f_type f_msg; do
    [ -z "$f_lane" ] && continue
    emit "<tr><td class=\"mono\">$(escs "$f_lane")</td><td>$(escs "$f_task")</td><td><span class=\"badge b-$(escs "$f_type")\">$(escs "$f_type")</span></td><td>$(escs "$f_msg")</td></tr>"
  done < <(jq -rs '
    group_by([.lane, .task]) | map(sort_by(.ts) | last) | sort_by([.lane, .task])
    | .[] | [.lane, .task, .type, .msg] | @tsv' "$EVENTS")
  emit '</table></div>'

  EVENT_COUNT=$(jq -rs 'length' "$EVENTS")
  emit "<details><summary>Full event timeline (${EVENT_COUNT} events)</summary><div class=\"scroll\"><table>"
  emit '<tr><th>When</th><th>Lane</th><th>Task</th><th>Type</th><th>Message</th></tr>'
  while IFS=$'\t' read -r t_ts t_lane t_task t_type t_msg; do
    [ -z "$t_lane" ] && continue
    emit "<tr><td class=\"mono\">$(escs "$t_ts")</td><td class=\"mono\">$(escs "$t_lane")</td><td>$(escs "$t_task")</td><td><span class=\"badge b-$(escs "$t_type")\">$(escs "$t_type")</span></td><td>$(escs "$t_msg")</td></tr>"
  done < <(jq -rs '.[] | [.ts, .lane, .task, .type, .msg] | @tsv' "$EVENTS")
  emit '</table></div></details>'
else
  emit '<p class="note">No events were recorded for this run.</p>'
fi

# ─── Verification ──────────────────────────────────────────────────────────

emit '<h2>Verification</h2>'
if [ -n "$REVIEW" ] && [ -f "$REVIEW" ]; then
  emit "<h3>Peer review</h3>"
  emit "<p class=\"note\">Full report: <span class=\"mono\">$(escs "$REVIEW")</span></p>"
  emit "<details open><summary>/deep-review report</summary>"
  pre_block "$(cat "$REVIEW")"
  emit "</details>"
elif [ -n "$REVIEW" ]; then
  emit "<p class=\"note\">Review report not found at $(escs "$REVIEW").</p>"
else
  emit '<p class="note">No /deep-review report was passed to this report builder.</p>'
fi

if [ -n "$QA" ]; then
  if [ -f "$QA" ]; then
    QA_REL=$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$QA" "$(dirname "$OUT")" 2>/dev/null || printf '%s' "$QA")
    emit "<h3>QA evidence</h3>"
    emit "<p>Evidence report: <a href=\"$(escs "$QA_REL")\">$(escs "$QA")</a></p>"
    emit "<p class=\"note\">QA evidence binds the commit it was executed against. If that is not <span class=\"mono\">$(escs "${FINAL_SHA:0:12}")</span>, the evidence is stale.</p>"
  else
    emit "<h3>QA evidence</h3>"
    emit "<p class=\"note\">QA report not found at $(escs "$QA").</p>"
  fi
fi

emit '<h3>Pull request</h3>'
if [ -n "$PR" ]; then
  emit "<p><a href=\"$(escs "$PR")\">$(escs "$PR")</a></p>"
else
  emit '<p class="note">No pull request URL was passed to this report builder.</p>'
fi

# ─── Footer ────────────────────────────────────────────────────────────────

cat >>"$OUT" <<'HTML_FOOT'
<footer>
<p>Generated by <code>build-run-report.sh</code> from the run directory alone — manifest, event
log, per-lane decision records, the approved plan and git. Nothing on this page was recalled
from a model's memory of the run.</p>
<p>Per-lane decision records and <code>worker-&lt;lane&gt;.files.txt</code> are written by the
lanes about themselves and are not authenticated. The one enforced boundary is the git-derived
ownership check in <code>validate-run-state.sh</code>.</p>
</footer>
</main>
</body>
</html>
HTML_FOOT

printf '%s\n' "$OUT"
