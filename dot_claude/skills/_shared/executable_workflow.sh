#!/usr/bin/env bash
# workflow.sh — the step file of a workflow run.
#
# The orchestrator and every spawned agent keep one step file. Each step is one row. The
# Stop hook `workflow-gate.sh` reads the file and blocks the end of a turn while a step is
# still open. Only a session that ran `init` is tracked: `init` prints the tracking line that
# the hook looks for in the transcript.
#
# Usage:
#   workflow.sh init   <file> <flow> [--project DIR] [--plan PATH]
#   workflow.sh add    <file> <id> <title> [--after <id>]
#   workflow.sh done   <file> <id> <evidence>      evidence: an existing path, a URL or a command
#   workflow.sh skip   <file> <id> <reason>
#   workflow.sh wait   <file> <id> <what>          an Orca worker or a background job
#   workflow.sh block  <file> <id> <question>      a question to the user
#   workflow.sh todo   <file> <id>                 open the step again
#   workflow.sh close  <file> <reason>             skip every open step (the user stopped the run)
#   workflow.sh status <file>                      what is done, what is next, what is left
#   workflow.sh check  <file>                      exit 0 when no step is open, else exit 1
#
# Row format:  - [x] <id> | <title> | <detail>
#   [ ] todo   [x] done   [-] skipped   [~] waiting   [!] blocked
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOWS="${WORKFLOW_FLOWS_DIR:-$HERE/workflows}"
# A step in this list cannot be skipped once a build step is done. The final deep review
# always runs over code that was built.
NOSKIP="review"

die() { printf 'workflow.sh: %s\n' "$*" >&2; exit 2; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
abspath() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }

# Print "<mark> <id> <title> <detail>" for each row, tab-separated.
rows() {
  awk -F' \\| ' '/^- \[.\] / {
    mark = substr($1, 4, 1); id = substr($1, 7)
    printf "%s\t%s\t%s\t%s\n", mark, id, $2, $3
  }' "$1"
}

has_row() { rows "$1" | awk -F'\t' -v id="$2" '$2 == id { found = 1 } END { exit !found }'; }

next_open() { rows "$1" | awk -F'\t' '$1 == " " { print $2 " — " $3; exit }'; }

left_count() { rows "$1" | awk -F'\t' '$1 == " " || $1 == "~" || $1 == "!" { n++ } END { print n + 0 }'; }

any_build_done() { rows "$1" | awk -F'\t' '$1 == "x" && $2 ~ /^build/ { f = 1 } END { exit !f }'; }

log_line() {
  local file="$1" text="$2" next
  next="$(next_open "$file")"
  printf -- '- %s %s. Next: %s. Left: %s.\n' "$(now)" "$text" "${next:-none}" "$(left_count "$file")" >>"$file"
}

# Rewrite the row of <id> with a new mark and detail.
set_row() {
  local file="$1" id="$2" mark="$3" detail="$4" tmp
  has_row "$file" "$id" || die "no step '$id' in $file"
  tmp="$(mktemp)"
  MARK="$mark" ID="$id" DETAIL="$detail" awk -F' \\| ' '
    /^- \[.\] / && substr($1, 7) == ENVIRON["ID"] {
      printf "- [%s] %s | %s | %s\n", ENVIRON["MARK"], ENVIRON["ID"], $2, ENVIRON["DETAIL"]; next
    }
    { print }' "$file" >"$tmp"
  mv "$tmp" "$file"
}

check_noskip() {
  local file="$1" id="$2"
  case " $NOSKIP " in
    *" $id "*) if any_build_done "$file"; then die "'$id' cannot be skipped after code was built. Run it."; fi ;;
  esac
}

cmd_init() {
  local file="$1" flow="$2" project="$PWD" plan="" steps
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --project) project="$2"; shift 2 ;;
      --plan) plan="$2"; shift 2 ;;
      *) die "unknown flag $1" ;;
    esac
  done
  file="$(abspath "$file")"
  steps="$FLOWS/$flow.steps"
  [ -f "$steps" ] || die "unknown flow '$flow' (no $steps)"
  if [ ! -f "$file" ]; then
    mkdir -p "$(dirname "$file")"
    {
      printf '# Workflow: %s\n\n' "$flow"
      printf 'Project: %s\n' "$project"
      [ -n "$plan" ] && printf 'Plan: %s\n' "$plan"
      printf 'Started: %s\n\n## Steps\n\n' "$(now)"
      local f
      for f in "$steps" $(awk '/^@include / { print $2 }' "$steps"); do
        case "$f" in /*) ;; *) f="$FLOWS/$f" ;; esac
        awk -F'|' '!/^#/ && !/^@/ && NF >= 2 { printf "- [ ] %s | %s | \n", $1, $2 }' "$f"
      done
      printf '\n## Log\n\n'
    } >"$file"
    if has_row "$file" setup; then set_row "$file" setup x "$file"; fi
    log_line "$file" "init $flow"
  fi
  printf '[workflow-gate] tracking %s\n' "$file"
  cmd_status "$file"
}

cmd_add() {
  local file="$1" id="$2" title="$3" after="" tmp
  shift 3
  [ "${1:-}" = "--after" ] && after="$2"
  has_row "$file" "$id" && die "step '$id' already exists"
  tmp="$(mktemp)"
  if [ -n "$after" ]; then
    has_row "$file" "$after" || die "no step '$after' in $file"
    # Insert after the last row whose id is <after> or starts with "<after>.".
    ROW="- [ ] $id | $title | " AFTER="$after" awk '
      { line[NR] = $0 }
      /^- \[.\] / { split(substr($0, 7), p, " \\| "); if (p[1] == ENVIRON["AFTER"] || index(p[1], ENVIRON["AFTER"] ".") == 1) last = NR }
      END { for (i = 1; i <= NR; i++) { print line[i]; if (i == last) print ENVIRON["ROW"] } }' "$file" >"$tmp"
  else
    ROW="- [ ] $id | $title | " awk '
      { line[NR] = $0 } /^- \[.\] / { last = NR }
      END { for (i = 1; i <= NR; i++) { print line[i]; if (i == last) print ENVIRON["ROW"] } }' "$file" >"$tmp"
  fi
  mv "$tmp" "$file"
  log_line "$file" "added $id"
}

cmd_done() {
  local file="$1" id="$2" evidence="${3:-}"
  [ -n "$evidence" ] || die "done needs evidence: a path, a URL or a command and its result"
  # The first word is a path when it holds two or more segments (/a/b, ~/a). A slash command
  # such as "/deep-review: 0 HIGH" is not a path.
  local first="${evidence%% *}"
  case "$first" in
    /*/*|~/*) [ -e "${first/#\~/$HOME}" ] || die "evidence path does not exist: $first" ;;
  esac
  set_row "$file" "$id" x "$evidence"
  log_line "$file" "done $id: $evidence"
}

cmd_mark() {
  local file="$1" id="$2" mark="$3" verb="$4" text="${5:-}"
  [ -n "$text" ] || die "$verb needs a reason"
  [ "$mark" = "-" ] && check_noskip "$file" "$id"
  set_row "$file" "$id" "$mark" "$verb: $text"
  log_line "$file" "$verb $id: $text"
}

cmd_close() {
  local file="$1" reason="${2:-}" id
  [ -n "$reason" ] || die "close needs a reason"
  for id in $(rows "$file" | awk -F'\t' '$1 == " " || $1 == "~" || $1 == "!" { print $2 }'); do
    check_noskip "$file" "$id"
    set_row "$file" "$id" - "skipped: $reason"
  done
  log_line "$file" "closed: $reason"
}

cmd_status() {
  local file="$1"
  rows "$file" | awk -F'\t' '
    $1 == "x" { done = done "  done     " $2 "\n" }
    $1 == "-" { done = done "  skipped  " $2 " (" $4 ")\n" }
    $1 == "~" { open = open "  waiting  " $2 " — " $3 " (" $4 ")\n" }
    $1 == "!" { open = open "  blocked  " $2 " — " $3 " (" $4 ")\n" }
    $1 == " " { open = open "  todo     " $2 " — " $3 "\n"; if (!next_) next_ = $2 " — " $3 }
    END {
      printf "Done:\n%s", (done ? done : "  none\n")
      printf "Left:\n%s", (open ? open : "  none\n")
      printf "Next: %s\n", (next_ ? next_ : "none")
    }'
}

cmd_check() {
  local file="$1"
  [ -f "$file" ] || die "no step file $file"
  # A waiting or blocked step is a legitimate stop: a worker runs, or the user must answer.
  if rows "$file" | awk -F'\t' '$1 == "~" || $1 == "!" { f = 1 } END { exit !f }'; then exit 0; fi
  if rows "$file" | awk -F'\t' '$1 == " " { f = 1 } END { exit !f }'; then
    printf 'Next: %s\n' "$(next_open "$file")"
    exit 1
  fi
  exit 0
}

[ $# -ge 2 ] || { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
cmd="$1"; file="$2"; shift 2
[ "$cmd" = init ] || [ -f "$file" ] || die "no step file $file. Run init first."
case "$cmd" in
  init)   [ $# -ge 1 ] || die "init <file> <flow>"; cmd_init "$file" "$@" ;;
  add)    [ $# -ge 2 ] || die "add <file> <id> <title>"; cmd_add "$file" "$@" ;;
  done)   [ $# -ge 1 ] || die "done <file> <id> <evidence>"; cmd_done "$file" "$@" ;;
  skip)   [ $# -ge 1 ] || die "skip <file> <id> <reason>"; cmd_mark "$file" "$1" - skipped "${2:-}" ;;
  wait)   [ $# -ge 1 ] || die "wait <file> <id> <what>"; cmd_mark "$file" "$1" "~" waiting "${2:-}" ;;
  block)  [ $# -ge 1 ] || die "block <file> <id> <question>"; cmd_mark "$file" "$1" "!" blocked "${2:-}" ;;
  todo)   [ $# -ge 1 ] || die "todo <file> <id>"; set_row "$file" "$1" " " ""; log_line "$file" "reopened $1" ;;
  close)  cmd_close "$file" "${1:-}" ;;
  status) cmd_status "$file" ;;
  check)  cmd_check "$file" ;;
  *) die "unknown command $cmd" ;;
esac
