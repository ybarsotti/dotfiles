#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

while IFS= read -r -d '' file; do
  printf 'Checking %s ...\n' "${file#"$repo_root"/}"
  sed -E 's/\{\{[^}]*\}\}//g' "$file" \
    | sed '/./,$!d' \
    | shellcheck -s bash --severity=error -
done < <(find "$repo_root" -name '*.sh.tmpl' -type f -not -path '*/.git/*' -print0)
