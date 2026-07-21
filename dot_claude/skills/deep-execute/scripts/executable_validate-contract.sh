#!/usr/bin/env bash
# validate-contract.sh — deterministic validation of a deep-execute run's API
# contract, read from RUN_DIR/manifest.json's `.contract` block.
#
# Usage:
#   validate-contract.sh RUN_DIR [--json]
#
# Emits 4 records via the same `record item status detail` + `--json` +
# exit-1 contract as validate-run-state.sh / validate-plan.sh:
#   contract-exists, contract-sha256-matches, contract-version-matches,
#   contract-lint
# Exit 0 iff every item passes.
#
# ── contract-version-matches: "matches where readable" ─────────────────────
# Not every contract kind embeds its own version inside the file (a
# TypeScript type file or a shell `command` contract usually doesn't). This
# item only fails when the contract file DOES have a readable version field
# AND it disagrees with the manifest's declared `contract.version` — a
# contract kind/shape with no embedded version to compare against records
# pass, saying so, never fail-by-default for something that was never there
# to check.
#
# ── contract-lint: a real linter failure fails; a genuinely absent linter ──
# passes, honestly
# For kind=openapi, a real OpenAPI linter (redocly, then spectral) is
# preferred when installed — its exit code is the ground truth, and a real
# finding in the contract fails this item. When NEITHER is installed, this
# is a missing optional dev tool, not a contract problem: the item records
# `pass`, with `detail` stating plainly that lint was skipped because no
# linter was found — it does NOT quietly substitute the plan's
# validation_command and call THAT "lint" (that would misrepresent what was
# actually checked). For every other kind, the plan's own
# `validation_command` is not optional tooling — it's the contract's
# declared, mandatory check — so it always runs, and a real failure there
# always fails this item.
set -uo pipefail

RESULTS=()
record() {
  local item="$1" status="$2" detail="$3"
  RESULTS+=("$(jq -n --arg i "$item" --arg s "$status" --arg d "$detail" \
    '{item:$i, status:$s, detail:$d}')")
}

if [ $# -lt 1 ]; then
  echo "Usage: validate-contract.sh RUN_DIR [--json]" >&2
  exit 2
fi
RUN_DIR="$1"
shift
JSON_OUT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON_OUT=1; shift ;;
    *)
      echo "validate-contract.sh: unknown flag '$1'" >&2
      exit 2
      ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  echo "validate-contract.sh: jq required" >&2
  exit 2
}

MANIFEST="${RUN_DIR}/manifest.json"
if [ ! -f "$MANIFEST" ] || ! jq -e . "$MANIFEST" >/dev/null 2>&1; then
  echo "validate-contract.sh: missing or invalid JSON: ${MANIFEST}" >&2
  exit 2
fi

CWD=$(jq -r '.cwd' "$MANIFEST")
CONTRACT_VERSION=$(jq -r '.contract.version' "$MANIFEST")
CONTRACT_PATH=$(jq -r '.contract.path' "$MANIFEST")
CONTRACT_KIND=$(jq -r '.contract.kind' "$MANIFEST")
VALIDATION_COMMAND=$(jq -r '.contract.validation_command' "$MANIFEST")
CONTRACT_SHA=$(jq -r '.contract.sha256' "$MANIFEST")
CONTRACT_ABS="${CWD}/${CONTRACT_PATH}"

if command -v sha256sum >/dev/null 2>&1; then
  SHA_CMD=(sha256sum)
else
  SHA_CMD=(shasum -a 256)
fi

# ─── 1. contract-exists ─────────────────────────────────────────────────────
if [ -f "$CONTRACT_ABS" ]; then
  record "contract-exists" "pass" "found at ${CONTRACT_PATH}"
else
  record "contract-exists" "fail" "missing: ${CONTRACT_PATH} (resolved to ${CONTRACT_ABS})"
fi

# ─── 2. contract-sha256-matches ────────────────────────────────────────────
if [ -f "$CONTRACT_ABS" ]; then
  ACTUAL_SHA=$("${SHA_CMD[@]}" "$CONTRACT_ABS" | awk '{print $1}')
  if [ "$ACTUAL_SHA" = "$CONTRACT_SHA" ]; then
    record "contract-sha256-matches" "pass" "sha256 matches manifest (${CONTRACT_SHA})"
  else
    record "contract-sha256-matches" "fail" "sha256 mismatch: manifest=${CONTRACT_SHA} actual=${ACTUAL_SHA}"
  fi
else
  record "contract-sha256-matches" "fail" "cannot compute sha256 — contract file missing: ${CONTRACT_PATH}"
fi

# ─── 3. contract-version-matches (where readable — see header) ────────────
if [ -f "$CONTRACT_ABS" ]; then
  case "$CONTRACT_KIND" in
    openapi)
      if command -v yq >/dev/null 2>&1; then
        EMBEDDED=$(yq -r '.info.version // ""' "$CONTRACT_ABS" 2>/dev/null || true)
      else
        EMBEDDED=$(jq -r '.info.version // empty' "$CONTRACT_ABS" 2>/dev/null || true)
      fi
      ;;
    *)
      EMBEDDED=$(jq -r '.version // empty' "$CONTRACT_ABS" 2>/dev/null || true)
      ;;
  esac
  if [ -z "$EMBEDDED" ] || [ "$EMBEDDED" = "null" ]; then
    record "contract-version-matches" "pass" "no readable version field for kind=${CONTRACT_KIND}; nothing to compare against manifest contract.version=${CONTRACT_VERSION}"
  elif [ "$EMBEDDED" = "$CONTRACT_VERSION" ]; then
    record "contract-version-matches" "pass" "embedded version ${EMBEDDED} matches manifest contract.version"
  else
    record "contract-version-matches" "fail" "embedded version ${EMBEDDED} does not match manifest contract.version ${CONTRACT_VERSION}"
  fi
else
  record "contract-version-matches" "fail" "cannot read version — contract file missing: ${CONTRACT_PATH}"
fi

# ─── 4. contract-lint ───────────────────────────────────────────────────────
if [ -f "$CONTRACT_ABS" ]; then
  case "$CONTRACT_KIND" in
    openapi)
      if command -v redocly >/dev/null 2>&1; then
        if LINT_OUT=$(cd "$CWD" && redocly lint "$CONTRACT_PATH" 2>&1); then
          record "contract-lint" "pass" "redocly lint passed"
        else
          record "contract-lint" "fail" "redocly lint failed: ${LINT_OUT}"
        fi
      elif command -v spectral >/dev/null 2>&1; then
        if LINT_OUT=$(cd "$CWD" && spectral lint "$CONTRACT_PATH" 2>&1); then
          record "contract-lint" "pass" "spectral lint passed"
        else
          record "contract-lint" "fail" "spectral lint failed: ${LINT_OUT}"
        fi
      else
        record "contract-lint" "pass" "no OpenAPI linter (redocly/spectral) found on PATH — lint skipped, not silently replaced by validation_command; contract already checked by sha256 + version above"
      fi
      ;;
    typescript | json-schema | command)
      if LINT_OUT=$(cd "$CWD" && sh -c "$VALIDATION_COMMAND" 2>&1); then
        record "contract-lint" "pass" "validation_command succeeded: ${VALIDATION_COMMAND}"
      else
        record "contract-lint" "fail" "validation_command failed: ${VALIDATION_COMMAND}: ${LINT_OUT}"
      fi
      ;;
    *)
      record "contract-lint" "fail" "unknown contract kind: ${CONTRACT_KIND}"
      ;;
  esac
else
  record "contract-lint" "fail" "cannot lint — contract file missing: ${CONTRACT_PATH}"
fi

# ─── Output ─────────────────────────────────────────────────────────────
ALL_JSON=$(printf '%s\n' "${RESULTS[@]}" | jq -s '.')
FAILS=$(echo "$ALL_JSON" | jq '[.[] | select(.status == "fail")] | length')

if [ "$JSON_OUT" -eq 1 ]; then
  echo "$ALL_JSON"
else
  printf "## validate-contract: %s\n\n" "$RUN_DIR"
  echo "$ALL_JSON" | jq -r '.[] | "- [" + (if .status == "pass" then "x" else " " end) + "] " + .item + " — " + .detail'
  echo
  if [ "$FAILS" -eq 0 ]; then
    echo "verdict: ALL PASS"
  else
    echo "verdict: $FAILS FAIL"
  fi
fi

[ "$FAILS" -eq 0 ] && exit 0 || exit 1
