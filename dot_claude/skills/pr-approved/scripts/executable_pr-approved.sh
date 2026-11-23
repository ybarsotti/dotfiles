#!/usr/bin/env bash
# pr-approved.sh — the read-only checks of /pr-approved. It changes nothing.
#
# Usage:
#   pr-approved.sh state   [<pr>]     JSON: PR, threads still open, checks, merge readiness
#   pr-approved.sh pending <root>     JSON: why the worktree at <root> must stay (empty = safe)
set -euo pipefail

die() { printf 'pr-approved.sh: %s\n' "$*" >&2; exit 2; }

cmd_state() {
  local pr="${1:-}" repo owner name number threads
  repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
  owner=${repo%/*}; name=${repo#*/}
  # An empty $pr means "the PR of the current branch".
  local view args=()
  [ -n "$pr" ] && args=("$pr")
  view=$(gh pr view "${args[@]+"${args[@]}"}" --json number,url,state,isDraft,headRefName,baseRefName,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup)
  number=$(jq -r .number <<<"$view")
  # Review threads with their resolved state. A flat comment list cannot be resolved.
  # shellcheck disable=SC2016 # GraphQL variables, not shell expansions
  threads=$(gh api graphql -F owner="$owner" -F name="$name" -F n="$number" -f query='
    query($owner:String!,$name:String!,$n:Int!){repository(owner:$owner,name:$name){
      pullRequest(number:$n){reviewThreads(first:100){nodes{id isResolved isOutdated path line
        comments(first:1){nodes{author{login} body url}}}}}}}' \
    --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)
           | {id, path, line, outdated: .isOutdated, author: .comments.nodes[0].author.login,
              url: .comments.nodes[0].url, body: (.comments.nodes[0].body | .[0:200])}]')
  jq -n --argjson v "$view" --argjson t "$threads" '
    ($v.statusCheckRollup // []) as $c
    | ($c | map(.conclusion // .state // "")) as $s
    | {
        number: $v.number, url: $v.url, state: $v.state, draft: $v.isDraft,
        head: $v.headRefName, base: $v.baseRefName,
        mergeable: $v.mergeable, merge_state: $v.mergeStateStatus, review: $v.reviewDecision,
        open_threads: $t,
        checks: {
          total: ($c | length),
          failing: [$c[] | select((.conclusion // .state // "") | test("FAILURE|ERROR|CANCELLED|TIMED_OUT|ACTION_REQUIRED|STARTUP_FAILURE")) | (.name // .context)],
          pending: [$c[] | select((.conclusion // "") == "" and ((.state // .status // "") | test("PENDING|QUEUED|IN_PROGRESS|EXPECTED|WAITING"))) | (.name // .context)]
        }
      }
    | .ready = (.state == "OPEN" and (.draft | not) and (.open_threads | length) == 0
                and (.checks.failing | length) == 0 and (.checks.pending | length) == 0
                and .mergeable == "MERGEABLE" and .review != "CHANGES_REQUESTED")'
}

cmd_pending() {
  local root="${1:-}" reasons=() file run open
  [ -d "$root" ] || die "no folder $root"
  root=$(cd "$root" && pwd -P)
  [ -z "$(git -C "$root" status --porcelain)" ] || reasons+=("uncommitted changes in $root")
  if git -C "$root" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    [ "$(git -C "$root" rev-list --count '@{upstream}..HEAD')" = 0 ] || reasons+=("commits not pushed")
  fi
  # Step files of the runs that worked in this folder.
  for file in "$HOME"/.claude/*-runs/*/chain.md; do
    [ -f "$file" ] || continue
    case "$file" in "$HOME"/.claude/pr-approved-runs/*) continue ;; esac
    grep -qxF "Project: $root" "$file" || continue
    run=$(dirname "$file")
    # An open step other than the PR and its watch is work that is not done.
    open=$(awk -F' \\| ' '/^- \[[ ~!]\] / { id = substr($1, 7); if (id != "pr") print id }' "$file" | paste -sd, -)
    [ -z "$open" ] || reasons+=("open steps in $file: $open")
    # A breakdown task that has no plan yet is a task still to do in this folder.
    if [ -f "$run/breakdown.md" ]; then
      reasons+=("breakdown with more tasks: $run/breakdown.md (check which tasks have no plan)")
    fi
  done
  jq -nc --arg r "$root" '$ARGS.positional | {root: $r, keep: (length > 0), reasons: .}' \
    --args "${reasons[@]+"${reasons[@]}"}"
}

[ $# -ge 1 ] || { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
case "$1" in
  state) shift; cmd_state "$@" ;;
  pending) shift; cmd_pending "$@" ;;
  *) die "unknown command $1" ;;
esac
