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
# deployed name (foo.sh) — same convention as deep-plan/cmux-orchestrator's
# suites, so this test keeps working after `chezmoi apply` strips the prefix.
DISPATCH="${ROOT}/dot_claude/skills/deep-review/scripts/executable_dispatch.sh"
[ -f "$DISPATCH" ] || DISPATCH="${ROOT}/dot_claude/skills/deep-review/scripts/dispatch.sh"
COLLECT_CONTEXT="${ROOT}/dot_claude/skills/deep-review/scripts/executable_collect-context.sh"
[ -f "$COLLECT_CONTEXT" ] || COLLECT_CONTEXT="${ROOT}/dot_claude/skills/deep-review/scripts/collect-context.sh"
REVIEWER="${ROOT}/dot_claude/skills/deep-review/scripts/executable_reviewer.sh"
[ -f "$REVIEWER" ] || REVIEWER="${ROOT}/dot_claude/skills/deep-review/scripts/reviewer.sh"
AGGREGATE="${ROOT}/dot_claude/skills/deep-review/scripts/executable_aggregate.sh"
[ -f "$AGGREGATE" ] || AGGREGATE="${ROOT}/dot_claude/skills/deep-review/scripts/aggregate.sh"

# ─── Task 12: SKILL.md points at dispatch.sh's own invocation and reuse of ─
# reviewer.sh by /deep-execute, and is under the pre-slimming baseline. ────

SKILL_MD_TEXT="$(cat "$SKILL_MD")"

assert_eq "$([ "$(wc -l <"$SKILL_MD" | tr -d ' ')" -lt 139 ] && echo yes || echo no)" yes \
  "SKILL.md: line count is under the pre-slimming baseline of 139"
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
# never fabricate findings, headless-only reviewers (no cmux panes), and
# exactly one aggregator call. Matches the pattern set by
# deep-plan/tests/executable_test-deep-plan.sh ("Task 6") and
# cmux-orchestrator/tests/executable_test-cmux-orchestrator.sh (task 8) —
# extend THIS block, not the line-count check, if this file is slimmed again.

assert_contains "$SKILL_MD_TEXT" "Do not try to repair invalid args silently" \
  "SKILL.md: must-survive — do not silently repair invalid args"
assert_contains "$SKILL_MD_TEXT" "Don't background it" \
  "SKILL.md: must-survive — run the dispatcher in the foreground, not backgrounded"
assert_contains "$SKILL_MD_TEXT" "Never invent findings" \
  "SKILL.md: must-survive — never invent findings when a reviewer fails"
assert_contains "$SKILL_MD_TEXT" "Headless only" \
  "SKILL.md: must-survive — headless only"
assert_contains "$SKILL_MD_TEXT" "Do NOT spawn reviewers in cmux panes" \
  "SKILL.md: must-survive — do not spawn reviewers in cmux panes"
assert_contains "$SKILL_MD_TEXT" "One aggregator call" \
  "SKILL.md: must-survive — one aggregator call"

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
for script in "$DISPATCH" "$COLLECT_CONTEXT" "$REVIEWER" "$AGGREGATE"; do
  MODE=$(stat -f '%Lp' "$script" 2>/dev/null || stat -c '%a' "$script")
  assert_eq "$MODE" "755" "$(basename "$script"): source-tree executable bit is 755"
done

assert_summary
