#!/usr/bin/env bash
# subplan-fanout.sh — split root plan's "Affected files" into per-lane
# chapters when the plan declares a parallel `## Execution shape`, or into
# ≤N top-level-directory chapters (the original behavior) for plans without
# one. Generates `subplans/<chapter>.md` and writes the Subplans section
# back into plan.md.
#
# Usage:
#   subplan-fanout.sh <run-dir> [--max-chapters N]
#
# --max-chapters only applies to the directory-grouped fallback; lane mode
# always emits exactly one subplan per declared lane.
# Default cap: 5; overflow → "misc" chapter.
# Portable to bash 3.2 (macOS default).

set -uo pipefail

RUN_DIR="$1"
shift
MAX_CHAPTERS=5

while [ $# -gt 0 ]; do
  case "$1" in
  --max-chapters)
    MAX_CHAPTERS="$2"
    shift 2
    ;;
  *)
    echo "subplan-fanout.sh: unknown flag '$1'" >&2
    exit 2
    ;;
  esac
done

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN="${RUN_DIR}/plan.md"
SUBPLAN_TEMPLATE="${SKILL_DIR}/templates/subplan.md"
PARSER="${SKILL_DIR}/scripts/plan-to-json.sh"

[ -f "$PLAN" ] || {
  echo "subplan-fanout.sh: missing $PLAN" >&2
  exit 2
}
[ -f "$SUBPLAN_TEMPLATE" ] || {
  echo "subplan-fanout.sh: missing $SUBPLAN_TEMPLATE" >&2
  exit 2
}

mkdir -p "${RUN_DIR}/subplans"

# Working scratch dir for per-group file lists.
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

# Extract affected file paths — only the first backtick span per bullet line
# (the path); a bullet's trailing description may itself mention other
# `backticked` terms that are not paths.
PATHS=$(awk '/^## Affected files/{flag=1; next} /^## /{flag=0} flag' "$PLAN" |
  awk -F'`' '/^- / && NF >= 3 { print $2 }' |
  sort -u)

if [ -z "$PATHS" ]; then
  echo "subplan-fanout.sh: no affected file paths found in plan" >&2
  exit 1
fi

slug() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g'; }

# ─── Decide lane mode vs. legacy directory grouping ────────────────────────
# A plan with no `## Execution shape` (or one whose Mode isn't `parallel`)
# degrades to the original top-level-directory grouping — older, serial-only
# plans must keep fanning out exactly as before.

LANE_MODE=0
PLAN_JSON="{}"
if [ -f "$PARSER" ] && command -v jq >/dev/null 2>&1; then
  if PLAN_JSON=$("$PARSER" "$PLAN" 2>/dev/null); then
    MODE_VAL=$(jq -r '.mode // "serial"' <<<"$PLAN_JSON" 2>/dev/null || echo serial)
    LANE_COUNT=$(jq '.lanes | length' <<<"$PLAN_JSON" 2>/dev/null || echo 0)
    if [ "$MODE_VAL" = "parallel" ] && [ "$LANE_COUNT" -gt 0 ]; then
      LANE_MODE=1
    fi
  fi
fi

# owns_match PATH PATTERN — exact-path or `/**`-prefix ownership match.
owns_match() {
  local path="$1" pattern="$2" prefix
  case "$pattern" in
  */**)
    prefix=${pattern%/**}
    case "$path" in "$prefix" | "$prefix"/*) return 0 ;; esac
    ;;
  *) [ "$path" = "$pattern" ] && return 0 ;;
  esac
  return 1
}

generate_subplan() {
  local chapter="$1" paths_file="$2" tasks_file="${4:-}"
  local contract_version="${5:-n/a}" contract_path="${6:-n/a}"
  local lane="${3:-$chapter}"
  local s
  s=$(slug "$chapter")
  local out="${RUN_DIR}/subplans/${s}.md"

  sed -e "s|{{CHAPTER}}|${chapter}|g" \
    -e "s|{{LANE}}|${lane}|g" \
    -e "s|{{MODE}}|serial|g" \
    -e "s|{{CONTRACT_VERSION}}|${contract_version}|g" \
    -e "s|{{CONTRACT_PATH}}|${contract_path}|g" \
    "$SUBPLAN_TEMPLATE" >"${out}.tmp"

  awk -v paths_file="$paths_file" '
    /\{\{FILES\}\}/ {
      while ((getline line < paths_file) > 0) if (line != "") print "- `" line "`"
      close(paths_file)
      next
    }
    { print }
  ' "${out}.tmp" >"${out}.tmp2"
  mv "${out}.tmp2" "${out}.tmp"

  if [ -n "$tasks_file" ] && [ -f "$tasks_file" ]; then
    awk -v tasks_file="$tasks_file" '
      /\{\{TASKS\}\}/ {
        while ((getline line < tasks_file) > 0) print line
        close(tasks_file)
        next
      }
      { print }
    ' "${out}.tmp" >"$out"
  else
    sed "s|{{TASKS}}|<!-- no lane-tagged tasks found in the root plan for this chapter; author them by hand, following \`superpowers:writing-plans\`. -->|g" \
      "${out}.tmp" >"$out"
  fi
  rm -f "${out}.tmp"
  echo "subplans/${s}.md"
}

LINKS=()

if [ "$LANE_MODE" -eq 1 ]; then
  # ─── Lane-owned grouping ──────────────────────────────────────────────────
  CONTRACT_VERSION_VAL=$(jq -r '.contract.version // "n/a"' <<<"$PLAN_JSON")
  CONTRACT_PATH_VAL=$(jq -r '.contract.path // "n/a"' <<<"$PLAN_JSON")
  LANE_NAMES=$(jq -r '.lanes[].name' <<<"$PLAN_JSON")
  LANE_PATTERNS=$(jq -r '.lanes[] | .name as $n | .owns[] | "\($n)\t\(.)"' <<<"$PLAN_JSON")

  # Bucket affected paths by owning lane; unowned paths fall into "misc".
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    owner=""
    while IFS=$'\t' read -r lname pat; do
      [ -z "$pat" ] && continue
      if owns_match "$p" "$pat"; then
        owner="$lname"
        break
      fi
    done <<<"$LANE_PATTERNS"
    [ -z "$owner" ] && owner="misc"
    echo "$p" >>"${SCRATCH}/paths-${owner}"
  done <<<"$PATHS"

  # Bucket raw `### Task N:` blocks by their `**Lane:**` tag; untagged blocks
  # fall into "misc". Skips ``` fences so illustrative example lines inside a
  # task's own steps are never mistaken for that task's real metadata.
  awk -v scratch="$SCRATCH" '
    function flush(   f) {
      if (buf == "") return
      f = (lane != "" ? (scratch "/tasks-" lane) : (scratch "/tasks-misc"))
      print buf > f
      print "" > f
    }
    /^```/ { infence = !infence; buf = (buf == "" ? $0 : buf "\n" $0); next }
    /^### Task [0-9]+:/ { flush(); buf = $0; lane = ""; next }
    /^## / && buf != "" { flush(); buf = ""; next }
    buf != "" {
      if (!infence && lane == "" && $0 ~ /^\*\*Lane:\*\*/) {
        n = split($0, a, "`"); if (n >= 2) lane = a[2]
      }
      buf = buf "\n" $0
    }
    END { flush() }
  ' "$PLAN"

  while IFS= read -r lname; do
    [ -z "$lname" ] && continue
    paths_file="${SCRATCH}/paths-${lname}"
    tasks_file="${SCRATCH}/tasks-${lname}"
    [ -f "$paths_file" ] || : >"$paths_file"
    link=$(generate_subplan "$lname" "$paths_file" "$lname" "$tasks_file" \
      "$CONTRACT_VERSION_VAL" "$CONTRACT_PATH_VAL")
    LINKS+=("- [$lname]($link)")
  done <<<"$LANE_NAMES"

  if [ -f "${SCRATCH}/paths-misc" ] || [ -f "${SCRATCH}/tasks-misc" ]; then
    [ -f "${SCRATCH}/paths-misc" ] || : >"${SCRATCH}/paths-misc"
    link=$(generate_subplan "misc" "${SCRATCH}/paths-misc" "misc" "${SCRATCH}/tasks-misc" \
      "$CONTRACT_VERSION_VAL" "$CONTRACT_PATH_VAL")
    LINKS+=("- [misc]($link)")
  fi
else
  # ─── Legacy top-level-directory grouping (plans with no lane data) ────────
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    first=$(echo "$p" | awk -F/ '{print (NF==1) ? "root" : $1}')
    echo "$p" >>"${SCRATCH}/$(slug "$first")"
  done <<<"$PATHS"

  # Build groups list ordered by file count (largest first), with the original
  # (non-slugified) name stored too.
  GROUP_FILES=$(ls -1 "$SCRATCH" 2>/dev/null)

  ORDERED=$(
    for slug_name in $GROUP_FILES; do
      count=$(wc -l <"${SCRATCH}/${slug_name}" | tr -d ' ')
      printf "%d\t%s\n" "$count" "$slug_name"
    done | sort -rn | cut -f2
  )

  # Compute display name (un-slugged) — use first directory token from any path.
  display_name() {
    local slug_name="$1"
    local first_path
    first_path=$(head -1 "${SCRATCH}/${slug_name}")
    echo "$first_path" | awk -F/ '{print (NF==1) ? "root" : $1}'
  }

  # Apply cap. If groups ≤ MAX_CHAPTERS, all become chapters. Otherwise: first
  # (MAX-1), rest folded into "misc".
  TOTAL_GROUPS=$(echo "$GROUP_FILES" | grep -c .)
  i=0

  if [ "$TOTAL_GROUPS" -le "$MAX_CHAPTERS" ]; then
    while IFS= read -r slug_name; do
      [ -z "$slug_name" ] && continue
      name=$(display_name "$slug_name")
      link=$(generate_subplan "$name" "${SCRATCH}/${slug_name}")
      LINKS+=("- [$name]($link)")
    done <<<"$ORDERED"
  else
    MISC_FILE="${SCRATCH}/__misc__"
    : >"$MISC_FILE"
    while IFS= read -r slug_name; do
      [ -z "$slug_name" ] && continue
      if [ "$i" -lt "$((MAX_CHAPTERS - 1))" ]; then
        name=$(display_name "$slug_name")
        link=$(generate_subplan "$name" "${SCRATCH}/${slug_name}")
        LINKS+=("- [$name]($link)")
      else
        cat "${SCRATCH}/${slug_name}" >>"$MISC_FILE"
      fi
      i=$((i + 1))
    done <<<"$ORDERED"
    if [ -s "$MISC_FILE" ]; then
      link=$(generate_subplan "misc" "$MISC_FILE")
      LINKS+=("- [misc]($link)")
    fi
  fi
fi

# Replace `## Subplans` body in plan.md with the new links.
# macOS awk rejects newlines in -v values; pass via temp file.
LINKS_FILE="${SCRATCH}/__links__"
printf '%s\n' "${LINKS[@]}" >"$LINKS_FILE"
TMP=$(mktemp)
awk -v body_file="$LINKS_FILE" '
  /^## Subplans/ {
    print; print ""
    while ((getline line < body_file) > 0) print line
    close(body_file)
    in_section = 1; next
  }
  /^## / && in_section { in_section = 0; print; next }
  in_section { next }
  { print }
' "$PLAN" >"$TMP"
if [ -s "$TMP" ]; then
  mv "$TMP" "$PLAN"
else
  rm -f "$TMP"
  echo "subplan-fanout: awk failed; plan.md unchanged" >&2
  exit 1
fi

echo "subplan-fanout: generated ${#LINKS[@]} chapter(s) in ${RUN_DIR}/subplans/" >&2
printf '%s\n' "${LINKS[@]}"
