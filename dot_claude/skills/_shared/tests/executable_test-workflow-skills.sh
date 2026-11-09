#!/usr/bin/env bash
# Tests the workflow stage skills and the artifact examples in workflow-artifacts.md.
# The examples run through the real verifier of the project template.
# TEMPLATE_DIR points at a local clone of that template.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
SKILLS="${ROOT}/dot_claude/skills"
REF="${SKILLS}/_shared/workflow-artifacts.md"
TEMPLATE_DIR="${TEMPLATE_DIR:-/Users/barsotti/Developer/Pers/ai-monorepo-template}"
WORKFLOW_SRC="${TEMPLATE_DIR}/core/.workflow"
VERIFY="${WORKFLOW_SRC}/scripts/verify.mjs"

# shellcheck source=/dev/null
. "${SKILLS}/_shared/executable_assert.sh"

if [ ! -f "$VERIFY" ]; then
  echo "FAIL: the verifier is not at ${VERIFY}. Set TEMPLATE_DIR."
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Skill files -----------------------------------------------------------

STAGES="workflow-mode workflow-post-plan workflow-post-implementation workflow-finish"
for skill in $STAGES; do
  file="${SKILLS}/${skill}/SKILL.md"
  text=$(cat "$file" 2>/dev/null || true)
  assert_eq "$(head -n 1 "$file" 2>/dev/null)" "---" "${skill}: opens with frontmatter"
  assert_contains "$text" "name: ${skill}" "${skill}: frontmatter has the name"
  assert_contains "$text" "description: " "${skill}: frontmatter has a description"
  assert_contains "$text" ".workflow/config.json" "${skill}: names the config file"
  assert_contains "$text" "This repository has no workflow" "${skill}: stops without .workflow/config.json"
done

text() { cat "${SKILLS}/$1/SKILL.md" 2>/dev/null || true; }
assert_contains "$(text workflow-mode)" 'Next: Skill(skill="workflow-post-plan")' "mode: standard goes to post-plan"
assert_contains "$(text workflow-mode)" 'Skill(skill="workflow-finish")' "mode: fast goes to finish"
assert_contains "$(text workflow-mode)" "AskUserQuestion" "mode: asks the user"
assert_contains "$(text workflow-post-plan)" 'Next: Skill(skill="workflow-post-implementation")' "post-plan: next is post-implementation"
assert_contains "$(text workflow-post-implementation)" 'Next: Skill(skill="workflow-finish")' "post-implementation: next is finish"
# shellcheck disable=SC2016 # The backticks are literal Markdown.
assert_contains "$(text workflow-finish)" 'Next: run `/pr`' "finish: points to /pr"
assert_eq "$(text workflow-finish | grep -c 'Next: Skill(')" 0 "finish: has no next skill"

for pair in post-plan:workflow-post-plan post-implementation:workflow-post-implementation finish:workflow-finish; do
  assert_contains "$(text "${pair#*:}")" "--through ${pair%%:*} --enforcement blocking" "${pair#*:}: runs the blocking verifier"
done
for skill in workflow-post-plan workflow-post-implementation workflow-finish; do
  assert_contains "$(text "$skill")" "correctness, simplicity, repo-rules" "${skill}: names the three reviewer roles"
done

# --- Integration lines -----------------------------------------------------

assert_contains "$(text simple-plan)" 'Skill(skill="workflow-post-plan")' "simple-plan: invokes post-plan"
assert_contains "$(text deep-plan)" 'Skill(skill="workflow-post-plan")' "deep-plan: invokes post-plan"
assert_contains "$(cat "${SKILLS}/_shared/after-approval.md")" 'Skill(skill="workflow-post-implementation")' \
  "after-approval: invokes post-implementation"

# --- Examples parse --------------------------------------------------------

# Each example is the fenced block after an `<!-- example: <name> -->` line.
mkdir -p "$TMP/examples"
awk -v dir="$TMP/examples" '
  /^<!-- example: / { name = $3; next }
  name && /^```/ { if (inside) { inside = 0; name = "" } else inside = 1; next }
  inside { print > (dir "/" name) }
' "$REF" 2>/dev/null
EXAMPLES="fast-workflow.md standard-workflow.md standard-post-plan.md standard-post-implementation.md standard-finish.md standard-decisions.md"
# Pass the paths in the environment. verify.mjs reads process.argv[1] when it loads.
for name in $EXAMPLES; do
  result=$(VERIFY="$VERIFY" EXAMPLE="$TMP/examples/$name" node --input-type=module -e '
    import { readFileSync } from "node:fs";
    import { pathToFileURL } from "node:url";
    const { parseFrontmatter } = await import(pathToFileURL(process.env.VERIFY));
    const { data } = parseFrontmatter(readFileSync(process.env.EXAMPLE, "utf8"));
    console.log(Object.keys(data).length > 0 ? "parsed" : "no frontmatter");
  ' 2>&1)
  assert_eq "$result" "parsed" "example ${name}: parseFrontmatter reads it"
done

# --- Examples pass the verifier, end to end --------------------------------

GIT=(git -c user.email=t@t -c user.name=t -c commit.gpgsign=false)
REPO="$TMP/repo"
mkdir -p "$REPO/.workflow/scripts" "$REPO/src" "$REPO/docs/rules/business" \
  "$REPO/docs/rules/technical" "$REPO/docs/rules/implementation"
cp "$WORKFLOW_SRC/config.json" "$REPO/.workflow/"
cp "$VERIFY" "$REPO/.workflow/scripts/"
cat >"$REPO/docs/rules/technical/TR-001.md" <<'EOF'
---
{"id": "TR-001", "kind": "technical", "status": "active", "paths": ["src/**"], "assertion": "x", "tests": []}
---
EOF
echo base >"$REPO/src/app.js"
(
  cd "$REPO" || exit 1
  "${GIT[@]}" init -q -b main
  "${GIT[@]}" add -A
  "${GIT[@]}" commit -q -m base
  "${GIT[@]}" checkout -q -b feat/x
  echo change >src/app.js
  "${GIT[@]}" commit -q -am change
)

# The shared commands block of the reference sets BASE, TASK_DIR, DIFF_HASH and PLAN_HASH.
awk '/^<!-- commands -->/ { on = 1; next } on && /^```/ { if (inside) exit; inside = 1; next } inside' \
  "$REF" >"$TMP/commands.sh" 2>/dev/null

# verify_example STAGE EXAMPLE... — writes the examples with real hashes, then runs the verifier.
verify_example() {
  local stage="$1"
  shift
  (
    cd "$REPO" || exit 2
    # shellcheck source=/dev/null
    . "$TMP/commands.sh" 2>/dev/null
    mkdir -p "$TASK_DIR"
    for name in "$@"; do
      sed -e "s|sha256:<diff_hash>|${DIFF_HASH:-}|" -e "s|sha256:<plan_hash>|${PLAN_HASH:-}|" \
        "$TMP/examples/$name" >"$TASK_DIR/${name#*-}"
    done
    node .workflow/scripts/verify.mjs --base-ref "$BASE" --through "$stage" --enforcement blocking
  )
}

out=$(verify_example finish fast-workflow.md 2>&1)
assert_eq "$?" 0 "fast example passes the verifier through finish (${out})"

echo "drift" >>"$REPO/src/app.js"
(cd "$REPO" && "${GIT[@]}" commit -q -am drift)
out=$(cd "$REPO" && node .workflow/scripts/verify.mjs --base-ref main --through finish 2>&1)
assert_contains "$out" "STALE_DIFF_HASH" "fast example: a new commit makes diff_hash stale"

rm -rf "$REPO/.workflow/tasks"
mkdir -p "$REPO/.workflow/tasks/feat/x"
printf '# Plan\n\nChange src/app.js.\n' >"$REPO/.workflow/tasks/feat/x/plan.md"
out=$(verify_example finish standard-workflow.md standard-post-plan.md standard-post-implementation.md \
  standard-finish.md standard-decisions.md 2>&1)
assert_eq "$?" 0 "standard examples pass the verifier through finish (${out})"

assert_summary
