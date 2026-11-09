#!/usr/bin/env bash
# contract-bump.sh — records an approved contract change in manifest.json.
#
# Usage:
#   contract-bump.sh RUN_DIR NEW_VERSION
#
# The drift procedure: the user approves the change, the orchestrator edits
# the contract and commits it, then runs this script. It sets
# contract.version, contract.sha256 and `checkpoint_commit` (HEAD). The
# contract and shared-file checks of validate-run-state.sh compare against
# that checkpoint from now on; `baseline_commit` stays the start of the run.
#
# It refuses an uncommitted contract: the checkpoint must hold the bytes the
# hash describes.
set -eufo pipefail

[ $# -eq 2 ] || {
  echo "Usage: contract-bump.sh RUN_DIR NEW_VERSION" >&2
  exit 2
}
RUN_DIR="$1"
VERSION="$2"
MANIFEST="${RUN_DIR}/manifest.json"
[ -f "$MANIFEST" ] || {
  echo "contract-bump.sh: missing ${MANIFEST}" >&2
  exit 2
}

CWD=$(jq -r '.cwd' "$MANIFEST")
CONTRACT=$(jq -r '.contract.path' "$MANIFEST")
[ -f "${CWD}/${CONTRACT}" ] || {
  echo "contract-bump.sh: no contract at ${CWD}/${CONTRACT}" >&2
  exit 1
}
[ -z "$(git -C "$CWD" status --porcelain -- "$CONTRACT")" ] || {
  echo "contract-bump.sh: commit ${CONTRACT} first — the checkpoint must hold the new contract" >&2
  exit 1
}

if command -v sha256sum >/dev/null 2>&1; then SHA_CMD=(sha256sum); else SHA_CMD=(shasum -a 256); fi
SHA=$("${SHA_CMD[@]}" "${CWD}/${CONTRACT}" | awk '{print $1}')
HEAD=$(git -C "$CWD" rev-parse HEAD)

TMP=$(mktemp "${RUN_DIR}/.manifest.XXXXXX")
jq --arg v "$VERSION" --arg sha "$SHA" --arg head "$HEAD" \
  '.contract.version = $v | .contract.sha256 = $sha | .checkpoint_commit = $head' "$MANIFEST" >"$TMP"
mv "$TMP" "$MANIFEST"
echo "contract-bump.sh: contract ${CONTRACT} is ${VERSION} (sha256 ${SHA:0:12}) at checkpoint ${HEAD:0:12}"
