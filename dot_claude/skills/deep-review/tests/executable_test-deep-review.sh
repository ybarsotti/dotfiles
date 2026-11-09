#!/usr/bin/env bash
# Tests for the Task 12 slimming of deep-review/SKILL.md: it should call
# dispatch.sh/reviewer.sh instead of restating their internals in prose, and
# stay under the pre-slimming line-count baseline without losing any rule
# an agent actually needs to follow correctly.
set -eufo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
# shellcheck source=/dev/null
. "${ROOT}/dot_claude/skills/_shared/executable_assert.sh"

SKILL_MD="${ROOT}/dot_claude/skills/deep-review/SKILL.md"

# Scripts resolve both the source-tree name (executable_foo.sh) and the
# deployed name (foo.sh) — same convention as the deep-plan
# suite, so this test keeps working after `chezmoi apply` strips the prefix.
DISPATCH="${ROOT}/dot_claude/skills/deep-review/scripts/executable_dispatch.sh"
[ -f "$DISPATCH" ] || DISPATCH="${ROOT}/dot_claude/skills/deep-review/scripts/dispatch.sh"
COLLECT_CONTEXT="${ROOT}/dot_claude/skills/deep-review/scripts/executable_collect-context.sh"
[ -f "$COLLECT_CONTEXT" ] || COLLECT_CONTEXT="${ROOT}/dot_claude/skills/deep-review/scripts/collect-context.sh"
REVIEWER="${ROOT}/dot_claude/skills/deep-review/scripts/executable_reviewer.sh"
[ -f "$REVIEWER" ] || REVIEWER="${ROOT}/dot_claude/skills/deep-review/scripts/reviewer.sh"
AGGREGATE="${ROOT}/dot_claude/skills/deep-review/scripts/executable_aggregate.sh"
[ -f "$AGGREGATE" ] || AGGREGATE="${ROOT}/dot_claude/skills/deep-review/scripts/aggregate.sh"
RECORD="${ROOT}/dot_claude/skills/deep-review/scripts/executable_record.sh"
[ -f "$RECORD" ] || RECORD="${ROOT}/dot_claude/skills/deep-review/scripts/record.sh"
REPORT="${ROOT}/dot_claude/skills/deep-review/scripts/executable_report.sh"
[ -f "$REPORT" ] || REPORT="${ROOT}/dot_claude/skills/deep-review/scripts/report.sh"
SARIF="${ROOT}/dot_claude/skills/deep-review/scripts/executable_sarif.sh"
VERIFY_EVIDENCE="${ROOT}/dot_claude/skills/deep-review/scripts/executable_verify-evidence.sh"
CHECK_STALE="${ROOT}/dot_claude/skills/deep-review/scripts/executable_check-stale.sh"
TEST_SIGNALS="${ROOT}/dot_claude/skills/deep-review/scripts/executable_test-signals.sh"
[ -f "$TEST_SIGNALS" ] || TEST_SIGNALS="${ROOT}/dot_claude/skills/deep-review/scripts/test-signals.sh"
[ -f "$SARIF" ] || SARIF="${ROOT}/dot_claude/skills/deep-review/scripts/sarif.sh"

# ─── Task 12: SKILL.md points at dispatch.sh's own invocation and reuse of ─
# reviewer.sh by /deep-execute, and is under the pre-slimming baseline. ────

SKILL_MD_TEXT="$(cat "$SKILL_MD")"

# Baseline history: 139 -> 165 when reviewers moved to recording findings by command
# (evidence mandatory, closed category set, severity replacing the per-reviewer verdict), then
# 165 -> 200 for Phase 4.5, which makes fixing and re-reviewing the default instead of a
# question the agent asks. Both are contracts the agent cannot derive from the scripts.
# Raise this again only for a rule of that weight, never to fit restated script internals.
assert_eq "$([ "$(wc -l <"$SKILL_MD" | tr -d ' ')" -lt 200 ] && echo yes || echo no)" yes \
  "SKILL.md: line count is under the baseline of 200"
assert_contains "$SKILL_MD_TEXT" "scripts/dispatch.sh" \
  "SKILL.md: Phase 2 still names dispatch.sh as the invocation target"
assert_contains "$SKILL_MD_TEXT" 'Skill(skill="simplify")' \
  "SKILL.md: Phase 5 still invokes the simplify skill"
assert_contains "$SKILL_MD_TEXT" "single-persona per-round reviewer for \`/deep-execute\`" \
  "SKILL.md: reviewer.sh's reuse by /deep-execute is documented"

# ─── Fix: must-survive rules pinned so the line-count metric can't be ──────
# satisfied by deleting load-bearing prose instead of restating it tighter.
# The four checks above only prove SKILL.md got shorter and still mentions
# dispatch.sh/simplify/deep-execute — every other rule in the file could be
# deleted and they'd stay green. Each assertion below pins one rule a prior
# reviewer identified as load-bearing for this skill: don't silently repair
# bad args, run the dispatcher in the foreground (so progress is visible),
# never fabricate findings, headless-only reviewers (no Orca terminals), and
# exactly one aggregator call. Matches the pattern set by
# deep-plan/tests/executable_test-deep-plan.sh ("Task 6") —
# extend THIS block, not the line-count check, if this file is slimmed again.

assert_contains "$SKILL_MD_TEXT" "Do not try to repair invalid args silently" \
  "SKILL.md: must-survive — do not silently repair invalid args"
assert_contains "$SKILL_MD_TEXT" "Don't background it" \
  "SKILL.md: must-survive — run the dispatcher in the foreground, not backgrounded"
assert_contains "$SKILL_MD_TEXT" "Never invent findings" \
  "SKILL.md: must-survive — never invent findings when a reviewer fails"
assert_contains "$SKILL_MD_TEXT" "Headless only" \
  "SKILL.md: must-survive — headless only"
assert_contains "$SKILL_MD_TEXT" "Do NOT spawn reviewers in Orca terminals" \
  "SKILL.md: must-survive — do not spawn reviewers in Orca terminals"
assert_contains "$SKILL_MD_TEXT" "No aggregator call in record mode" \
  "SKILL.md: must-survive — no aggregator call when reviewers record findings"
assert_contains "$SKILL_MD_TEXT" "still use a single \`claude -p\` aggregator" \
  "SKILL.md: must-survive — non-recording variants keep exactly one aggregator call"

# The record contract. Each of these is a rule the scripts enforce but the agent must know
# up front, because a reviewer that does not know it wastes a whole run producing text.
assert_contains "$SKILL_MD_TEXT" "rejects a finding with no \`--evidence\`" \
  "SKILL.md: must-survive — a finding with no evidence is rejected"
assert_contains "$SKILL_MD_TEXT" "There is no per-reviewer verdict" \
  "SKILL.md: must-survive — severity decides the verdict, reviewers do not vote"

# ─── The restated dispatcher mechanics are genuinely gone, not just ────────
# shortened — content, not occurrence: the full progress-transcript example
# and the numbered "The dispatcher: 1...7" internals list no longer appear,
# since dispatch.sh already implements and can demonstrate both live.
NO_TRANSCRIPT="yes"
case "$SKILL_MD_TEXT" in
  *"[deep-review] run-id=run-"*) NO_TRANSCRIPT="no" ;;
esac
assert_eq "$NO_TRANSCRIPT" "yes" \
  "SKILL.md: the illustrative stderr transcript was removed, not just trimmed"

NO_STEP_LIST="yes"
case "$SKILL_MD_TEXT" in
  *"Creates a run directory at \`/tmp/deep-review/run-"*) NO_STEP_LIST="no" ;;
esac
assert_eq "$NO_STEP_LIST" "yes" \
  "SKILL.md: the restated dispatcher run-directory mechanics were removed"

# ─── Known issue fixed alongside the slimming: the scripts dispatch.sh ─────
# calls directly (no \`bash\` wrapper — see executable_dispatch.sh's own
# \`"\${SCRIPT_DIR}/collect-context.sh" ...\` invocations) need their
# source-tree executable bit set, or dispatch.sh fails before chezmoi apply
# ever gets a chance to fix the mode. dispatch.sh itself is the direct
# invocation target named in Phase 2 above.
for script in "$DISPATCH" "$COLLECT_CONTEXT" "$REVIEWER" "$AGGREGATE" "$RECORD" "$REPORT" "$SARIF" \
  "$VERIFY_EVIDENCE" "$CHECK_STALE" "$TEST_SIGNALS"; do
  MODE=$(stat -c '%a' "$script" 2>/dev/null || stat -f '%Lp' "$script")
  assert_eq "$MODE" "755" "$(basename "$script"): source-tree executable bit is 755"
done


# ─── record.sh + report.sh: QUESTION, --remark and --clean ─────────────────
# A QUESTION reaches the report but never blocks the verdict; a remark is capped so it stays
# pasteable; a clean section is listed so the report shows what ran.
RR_DIR=$(mktemp -d)
export DEEP_REVIEW_FINDINGS="${RR_DIR}/findings.jsonl"
"$RECORD" --persona simplicity --category simplicity --severity QUESTION --file app/m.py --line 3 \
  --title "guard on a non-null field?" --evidence "app/models.py:10" \
  --remark "isn't this enforced at DB level? read obj.x directly" 2>/dev/null
"$RECORD" --persona senior-backend --clean "2. Database and queries" 2>/dev/null
RR_REPORT=$("$REPORT" "$RR_DIR")
assert_contains "$RR_REPORT" "**Verdict: APPROVE**" "report: a QUESTION alone does not block the verdict"
# shellcheck disable=SC2016 # literal backticks in the expected markdown, not a command substitution
assert_contains "$RR_REPORT" '- `app/m.py:3` isn'"'"'t this enforced at DB level?' "report: remarks to post list the file, line and remark"
assert_contains "$RR_REPORT" "- senior-backend: 2. Database and queries" "report: clean sections are listed per persona"
"$RECORD" --persona correctness --category correctness --severity LOW --file app/m.py --line 9 \
  --title "low" --evidence "app/m.py:1" 2>/dev/null
assert_contains "$("$REPORT" "$RR_DIR")" "**Verdict: REQUEST_CHANGES**" "report: a LOW beside a QUESTION still requests changes"
assert_exit 1 "$RECORD" --persona x --category simplicity --severity LOW --title t --evidence e \
  --remark "$(printf '%0161d' 0)"
unset DEEP_REVIEW_FINDINGS
rm -rf "$RR_DIR"

# ─── recurring.sh: a finding seen in two earlier runs of the same repo ─────
RECURRING="${ROOT}/dot_claude/skills/deep-review/scripts/executable_recurring.sh"
RC_ROOT=$(mktemp -d)
rc_run() { # rc_run NAME REMOTE TITLE
  mkdir -p "${RC_ROOT}/$1"
  printf '## Repo\n- remote: %s\n' "$2" >"${RC_ROOT}/$1/context.md"
  jq -nc --arg t "$3" '{title:$t, severity:"HIGH"}' >"${RC_ROOT}/$1/findings.jsonl"
}
rc_run run-a git@x:me/app "Service layer raises HttpError for validation"
rc_run run-b git@x:me/app "Repository raises HttpError on validation failure"
rc_run run-c git@x:me/other "Service layer raises HttpError for validation"
rc_run run-now git@x:me/app "Service raises HttpError on validation"
RC_OUT=$("$RECURRING" "${RC_ROOT}/run-now" "$RC_ROOT")
assert_contains "$RC_OUT" "| 2 | HIGH | Service raises HttpError on validation |" \
  "recurring: counts earlier runs of the same repository only"
rc_run run-now git@x:me/app "Checkout button lacks a focus ring"
assert_eq "$("$RECURRING" "${RC_ROOT}/run-now" "$RC_ROOT")" "" "recurring: a new problem prints nothing"
rm -rf "$RC_ROOT"

# ─── record.sh: a persona records at most 3 LOW findings ───────────────────
LOW_FILE="$(mktemp -d)/findings.jsonl"
for n in 1 2 3; do
  "$RECORD" --findings "$LOW_FILE" --persona p --category tests --severity LOW --title "t$n" \
    --evidence e 2>/dev/null
done
assert_exit 1 "$RECORD" --findings "$LOW_FILE" --persona p --category tests --severity LOW \
  --title t4 --evidence e
assert_exit 0 "$RECORD" --findings "$LOW_FILE" --persona q --category tests --severity LOW \
  --title other --evidence e
rm -rf "$(dirname "$LOW_FILE")"

# ─── dispatch.sh: only_when_changed skips a persona; --lens adds a reviewer ─
LENS_REPO=$(mktemp -d)
git -C "$LENS_REPO" init -q -b main
mkdir -p "${LENS_REPO}/.agents/skills/team-review" "${LENS_REPO}/src"
echo "# lens" >"${LENS_REPO}/.agents/skills/team-review/SKILL.md"
echo a >"${LENS_REPO}/src/x.py"
mkdir -p "${LENS_REPO}/web"
echo a >"${LENS_REPO}/web/cart.test.ts"
git -C "$LENS_REPO" add -A
git -C "$LENS_REPO" -c user.email=t@t -c user.name=t commit -qm init
echo b >>"${LENS_REPO}/src/x.py"
LENS_OUT=$(cd "$LENS_REPO" && "$DISPATCH" default --dry-run --scope HEAD \
  --lens "${LENS_REPO}/.agents/skills/team-review/SKILL.md" 2>/dev/null)
assert_contains "$LENS_OUT" "senior-frontend                no changed file matches" \
  "dispatch: a frontend persona is skipped on a backend-only diff"
assert_contains "$LENS_OUT" "lens-team-review               → claude" \
  "dispatch: --lens adds the repository lens as a Claude reviewer"
assert_contains "$LENS_OUT" ".agents/skills/team-review/SKILL.md" \
  "dispatch: --dry-run lists the repository lenses"
assert_contains "$LENS_OUT" "test-quality                   no changed file matches" \
  "dispatch: test-quality is skipped when no test file changes"
echo b >>"${LENS_REPO}/web/cart.test.ts"
LENS_OUT=$(cd "$LENS_REPO" && "$DISPATCH" default --dry-run --scope HEAD 2>/dev/null)
assert_contains "$LENS_OUT" "test-quality                   → claude" \
  "dispatch: test-quality runs on Claude when a test file changes"
rm -rf "$LENS_REPO"

# ─── test-quality: registered on Claude, owns the mock-boundary rule ───────
PERSONAS_DIR="${ROOT}/dot_claude/skills/deep-review/personas"
DEFAULT_YML="${ROOT}/dot_claude/skills/deep-review/variants/default.yml"
assert_eq "$(yq -r '.personas[] | select(.id == "test-quality") | .runner' "$DEFAULT_YML")" claude \
  "default.yml: test-quality is registered with runner claude"
MOCK_HEADING="Mock only the outermost call to an external service"
assert_eq "$(grep -c "$MOCK_HEADING" "${PERSONAS_DIR}/correctness.md" || true)" 0 \
  "correctness.md: the mock-boundary block moved out"
assert_contains "$(cat "${PERSONAS_DIR}/test-quality.md" 2>/dev/null)" "$MOCK_HEADING" \
  "test-quality.md: owns the mock-boundary block"

# ─── senior-backend: query-cost checklist and backend path regex ───────────
SB_MD=$(cat "${PERSONAS_DIR}/senior-backend.md")
for needle in "**Work per row**" "**Rows read, not rows returned**" "**Where it runs**" \
  "Join and rewrite pass" "deleted_at IS NULL" "distinct=True" "EXPLAIN (ANALYZE, BUFFERS)" \
  "assertNumQueries" "selectinload" "lazy=\"raise\"" "findMany" "generated SQL shape"; do
  assert_contains "$SB_MD" "$needle" "senior-backend.md: names ${needle}"
done
assert_eq "$(grep -c '^- \*\*N+1\*\*' "${PERSONAS_DIR}/senior-backend.md")" 1 \
  "senior-backend.md: one N+1 rule, not a second copy"
QC_MD=$(cat "${ROOT}/dot_claude/skills/_shared/query-check.md")
assert_contains "$QC_MD" "Production sizing" "query-check.md: sizing comes from project docs"
assert_contains "$QC_MD" "shared hit + read" "query-check.md: report compares buffers"
SB_RE=$(yq -r '.personas[] | select(.id == "senior-backend") | .only_when_changed' "$DEFAULT_YML")
for p in apps/api/src/orders.service.ts prisma/schema.prisma src/db/schema.ts drizzle.config.ts \
  packages/core/src/database/client.ts src/repositories/order-repository.ts \
  src/repository/user.repo.js src/models/invoice.ts drizzle/0003_add_orders_index.sql \
  internal/store/queries/orders.sql app/billing/models.py src/users/users.repository.ts \
  src/orders/order.entity.ts src/migration/1700-add.ts; do
  assert_eq "$(grep -cE -- "$SB_RE" <<<"$p" || true)" 1 "senior-backend regex: matches ${p}"
done
for p in src/components/OrderTable.tsx src/features/orders/OrderList.tsx 'app/routes/orders.$id.tsx' \
  src/features/orders/queries/useOrders.ts src/features/checkout/schema.ts \
  src/hooks/useDatabaseStatus.ts; do
  assert_eq "$(grep -cE -- "$SB_RE" <<<"$p" || true)" 0 "senior-backend regex: skips ${p}"
done

# ─── test-signals.sh: silent without recipes, headed output with them ──────
SIG_REPO=$(mktemp -d)
assert_eq "$("$TEST_SIGNALS" "$SIG_REPO" 2>&1; echo "exit=$?")" "exit=0" \
  "test-signals: no justfile prints nothing and exits 0"
printf 'lint:\n\techo lint-ran\n' >"${SIG_REPO}/justfile"
assert_eq "$("$TEST_SIGNALS" "$SIG_REPO" 2>&1; echo "exit=$?")" "exit=0" \
  "test-signals: a justfile without the recipes prints nothing and exits 0"
printf 'mutate:\n\t@echo survivor-at-app.py:3\ntest-overlap:\n\t@echo overlap-found; exit 1\n' \
  >"${SIG_REPO}/justfile"
SIG_OUT=$("$TEST_SIGNALS" "$SIG_REPO"; echo "exit=$?")
assert_contains "$SIG_OUT" "### just mutate" "test-signals: mutate output has a heading"
assert_contains "$SIG_OUT" "survivor-at-app.py:3" "test-signals: mutate output is included"
assert_contains "$SIG_OUT" "overlap-found" "test-signals: a failing recipe still shows its output"
assert_contains "$SIG_OUT" "exit=0" "test-signals: a failing recipe does not fail the script"
rm -rf "$SIG_REPO"

assert_summary
