#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_dir=$(mktemp -d -t stop-hooks-test.XXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$tmp_dir/bin/osascript"
chmod +x "$tmp_dir/bin/osascript"

failures=0

if ruby -rjson -e 'puts JSON.generate({"message" => "x" * 1048576})' \
    | gtimeout 2 env PATH="$tmp_dir/bin:$PATH" \
        bash "$repo_root/dot_local/bin/executable_notify-claude"; then
  echo "notify-large-payload: PASS"
else
  status=$?
  echo "notify-large-payload: FAIL (exit $status)" >&2
  failures=$((failures + 1))
fi

rendered_hooks=$(chezmoi execute-template <"$repo_root/dot_codex/private_hooks.json.tmpl")

if jq -e '[.hooks.Stop[].hooks[] | select(.command | contains("plannotator"))] | length == 0' \
    >/dev/null <<<"$rendered_hooks"; then
  echo "stop-plannotator-absent: PASS"
else
  echo "stop-plannotator-absent: FAIL" >&2
  failures=$((failures + 1))
fi

if jq -e 'all(.hooks.Stop[].hooks[]; .async == true or ((.timeout // 600) <= 10))' \
    >/dev/null <<<"$rendered_hooks"; then
  echo "stop-handlers-bounded: PASS"
else
  echo "stop-handlers-bounded: FAIL" >&2
  failures=$((failures + 1))
fi

exit "$failures"
