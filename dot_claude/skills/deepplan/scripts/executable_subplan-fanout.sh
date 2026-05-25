#!/usr/bin/env bash
# subplan-fanout.sh — split root plan's "Affected files" into ≤N chapters
# grouped by top-level directory. Generates `subplans/<chapter>.md` and
# writes the Subplans section back into plan.md.
#
# Usage:
#   subplan-fanout.sh <run-dir> [--max-chapters N]
#
# Default cap: 5; overflow → "misc" chapter.
# Portable to bash 3.2 (macOS default).

set -uo pipefail

RUN_DIR="$1"; shift
MAX_CHAPTERS=5

while [ $# -gt 0 ]; do
  case "$1" in
    --max-chapters) MAX_CHAPTERS="$2"; shift 2 ;;
    *) echo "subplan-fanout.sh: unknown flag '$1'" >&2; exit 2 ;;
  esac
done

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN="${RUN_DIR}/plan.md"
SUBPLAN_TEMPLATE="${SKILL_DIR}/templates/subplan.md"

[ -f "$PLAN" ] || { echo "subplan-fanout.sh: missing $PLAN" >&2; exit 2; }
[ -f "$SUBPLAN_TEMPLATE" ] || { echo "subplan-fanout.sh: missing $SUBPLAN_TEMPLATE" >&2; exit 2; }

mkdir -p "${RUN_DIR}/subplans"

# Working scratch dir for per-group file lists.
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

# Extract affected file paths.
PATHS=$(awk '/^## Affected files/{flag=1; next} /^## /{flag=0} flag' "$PLAN" \
        | grep -oE '`[^`]+`' | tr -d '`' | sort -u)

if [ -z "$PATHS" ]; then
  echo "subplan-fanout.sh: no affected file paths found in plan" >&2
  exit 1
fi

# Bucket paths into per-group files.
slug() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g'; }

while IFS= read -r p; do
  [ -z "$p" ] && continue
  first=$(echo "$p" | awk -F/ '{print (NF==1) ? "root" : $1}')
  echo "$p" >> "${SCRATCH}/$(slug "$first")"
done <<< "$PATHS"

# Build groups list ordered by file count (largest first), with the original
# (non-slugified) name stored too.
GROUP_FILES=$(ls -1 "$SCRATCH" 2>/dev/null)

ORDERED=$(
  for slug_name in $GROUP_FILES; do
    count=$(wc -l < "${SCRATCH}/${slug_name}" | tr -d ' ')
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

generate_subplan() {
  local chapter="$1"
  local paths_file="$2"
  local s; s=$(slug "$chapter")
  local out="${RUN_DIR}/subplans/${s}.md"

  sed "s|{{CHAPTER}}|${chapter}|g" "$SUBPLAN_TEMPLATE" > "${out}.tmp"

  awk -v paths_file="$paths_file" '
    /\{\{FILES\}\}/ {
      while ((getline line < paths_file) > 0) if (line != "") print "- `" line "`"
      close(paths_file)
      next
    }
    { print }
  ' "${out}.tmp" > "$out"
  rm -f "${out}.tmp"
  echo "subplans/${s}.md"
}

# Apply cap. If groups ≤ MAX_CHAPTERS, all become chapters. Otherwise: first
# (MAX-1), rest folded into "misc".
TOTAL_GROUPS=$(echo "$GROUP_FILES" | grep -c .)
LINKS=()
i=0

if [ "$TOTAL_GROUPS" -le "$MAX_CHAPTERS" ]; then
  while IFS= read -r slug_name; do
    [ -z "$slug_name" ] && continue
    name=$(display_name "$slug_name")
    link=$(generate_subplan "$name" "${SCRATCH}/${slug_name}")
    LINKS+=("- [$name]($link)")
  done <<< "$ORDERED"
else
  MISC_FILE="${SCRATCH}/__misc__"
  : > "$MISC_FILE"
  while IFS= read -r slug_name; do
    [ -z "$slug_name" ] && continue
    if [ "$i" -lt "$((MAX_CHAPTERS - 1))" ]; then
      name=$(display_name "$slug_name")
      link=$(generate_subplan "$name" "${SCRATCH}/${slug_name}")
      LINKS+=("- [$name]($link)")
    else
      cat "${SCRATCH}/${slug_name}" >> "$MISC_FILE"
    fi
    i=$((i + 1))
  done <<< "$ORDERED"
  if [ -s "$MISC_FILE" ]; then
    link=$(generate_subplan "misc" "$MISC_FILE")
    LINKS+=("- [misc]($link)")
  fi
fi

# Replace `## Subplans` body in plan.md with the new links.
# macOS awk rejects newlines in -v values; pass via temp file.
LINKS_FILE="${SCRATCH}/__links__"
printf '%s\n' "${LINKS[@]}" > "$LINKS_FILE"
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
' "$PLAN" > "$TMP"
if [ -s "$TMP" ]; then
  mv "$TMP" "$PLAN"
else
  rm -f "$TMP"
  echo "subplan-fanout: awk failed; plan.md unchanged" >&2
  exit 1
fi

echo "subplan-fanout: generated ${#LINKS[@]} chapter(s) in ${RUN_DIR}/subplans/" >&2
printf '%s\n' "${LINKS[@]}"
