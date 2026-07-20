#!/usr/bin/env bash
# superpowers-invoke.sh — the ONLY writer of RUN_DIR/superpowers-receipts.log
# and the ONLY thing permitted to tick a `## Superpowers invoked` box.
#
# Before this existed, `## Superpowers invoked` was free prose an agent could
# edit directly, so a `[x]` proved nothing — an agent could certify a skill it
# never ran. Routing every tick through here makes the claim (the box) and
# the evidence (the receipt) the same action:
# `validate-plan.sh`'s `superpowers-ticks-have-receipts` check rejects any
# `[x]` that has no matching, chain-valid, ancestor-verified receipt line.
#
# This is tamper-EVIDENT, not tamper-proof. Each receipt is anchored to the
# project repo's HEAD commit and chained by hash to the previous receipt, so
# forging one requires either fabricating a self-consistent sha256 chain by
# hand (possible — the algorithm is documented right here) or rewriting local
# git history to mint a commit to point at (also possible, for anyone with
# push/rewrite access to their own clone). The 0444 chmod below is a cheap
# speed bump against casual editing, not a security boundary. What this
# mechanism actually buys is raised cost and a durable trail, not
# impossibility.
#
# The caller invokes this AFTER actually invoking the skill (via the Skill
# tool) — this script only records the fact, it never invokes a skill itself.
#
# Usage:
#   superpowers-invoke.sh RUN_DIR SKILL_NAME
#
# RUN_DIR must contain plan.md. SKILL_NAME must already appear as a
# `- [ ]`/`- [x]` line under plan.md's `## Superpowers invoked` section (which
# also covers its nested `### Handoff` subsection) — that section is the
# known set; a name outside it exits 2 without writing anything.
#
# Appends one line to RUN_DIR/superpowers-receipts.log:
#   <iso-8601-utc>\t<skill-name>\t<repo-head-sha>\t<chain-hash>
# where:
#   - <repo-head-sha> is `git rev-parse HEAD` of the project repo, resolved
#     from RUN_DIR's location first, then this process's cwd; the literal
#     `no-git` if neither resolves to a git repo.
#   - <chain-hash> = sha256(previous-line's chain-hash + the TAB-joined
#     <ts>\t<skill>\t<repo-head-sha> of THIS line). The first line in the log
#     chains from the empty string.
# Writes with O_APPEND, chmods the log 0444 afterward (reopened 0644 only by
# this script, only long enough to append the next line), then flips the
# matching `- [ ] <skill>` line in plan.md to `- [x] <skill>`.
#
# Example:
#   superpowers-invoke.sh "$RUN_DIR" brainstorming

set -eufo pipefail

RUN_DIR="${1:?usage: superpowers-invoke.sh RUN_DIR SKILL_NAME}"
SKILL_NAME="${2:?usage: superpowers-invoke.sh RUN_DIR SKILL_NAME}"

PLAN="${RUN_DIR}/plan.md"
RECEIPTS="${RUN_DIR}/superpowers-receipts.log"

[ -f "$PLAN" ] || { echo "superpowers-invoke.sh: missing $PLAN" >&2; exit 2; }

# Known set = whatever plan.md itself declares under `## Superpowers
# invoked` (both the required planning list and the nested `### Handoff`
# list) — tying validity to the plan's own text avoids a second list that can
# drift out of sync with templates/plan.md. Fence-aware: an illustrative
# fenced example elsewhere in the plan must never be mistaken for this
# section's declared set.
FOUND=0
while IFS= read -r s; do
  [ "$s" = "$SKILL_NAME" ] && { FOUND=1; break; }
done < <(awk '
  /^```/ { infence = !infence; next }
  infence { next }
  /^## Superpowers invoked/ { inside=1; next }
  inside && /^## / { inside=0 }
  inside
' "$PLAN" | sed -n 's/^- \[[ x]\] \([a-z0-9-]*\).*/\1/p')

if [ "$FOUND" -ne 1 ]; then
  echo "superpowers-invoke.sh: unknown skill '${SKILL_NAME}' (not declared under $PLAN's '## Superpowers invoked')" >&2
  exit 2
fi

if command -v sha256sum >/dev/null 2>&1; then
  SHA_CMD=(sha256sum)
else
  SHA_CMD=(shasum -a 256)
fi

# Resolve the project repo's HEAD: prefer RUN_DIR's own location (the plan
# usually lives inside the project it plans for), fall back to this
# process's cwd, else record the literal `no-git`.
REPO_SHA="no-git"
if RS=$(git -C "$RUN_DIR" rev-parse HEAD 2>/dev/null); then
  REPO_SHA="$RS"
elif RS=$(git rev-parse HEAD 2>/dev/null); then
  REPO_SHA="$RS"
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

PREV_HASH=""
if [ -f "$RECEIPTS" ]; then
  chmod 0644 "$RECEIPTS"
  PREV_HASH=$(tail -n 1 "$RECEIPTS" | awk -F'\t' '{print $4}')
fi

PAYLOAD=$(printf '%s\t%s\t%s' "$TS" "$SKILL_NAME" "$REPO_SHA")
HASH=$(printf '%s%s' "$PREV_HASH" "$PAYLOAD" | "${SHA_CMD[@]}" | awk '{print $1}')

printf '%s\t%s\t%s\t%s\n' "$TS" "$SKILL_NAME" "$REPO_SHA" "$HASH" >>"$RECEIPTS"
chmod 0444 "$RECEIPTS"

TMP=$(mktemp)
awk -v skill="$SKILL_NAME" -v ts="$TS" '
  /^```/ { infence = !infence; print; next }
  infence { print; next }
  /^## Superpowers invoked/ { in_section = 1; print; next }
  /^## / && in_section { in_section = 0 }
  in_section && $0 ~ ("^- \\[ \\] " skill "( |$)") {
    sub(/\[ \]/, "[x]")
    if ($0 ~ /— <when>/) sub(/— <when>/, "— " ts)
    print; next
  }
  { print }
' "$PLAN" >"$TMP"
mv "$TMP" "$PLAN"

echo "superpowers-invoke: recorded receipt (repo-sha=${REPO_SHA}) + ticked ${SKILL_NAME} at ${TS}" >&2
