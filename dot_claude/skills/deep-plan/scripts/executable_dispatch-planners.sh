#!/usr/bin/env bash
# dispatch-planners.sh — fan out Opus + Codex planner drafts in parallel.
#
# Usage: dispatch-planners.sh <run-dir> <task-description> [--no-codex]
#
# Writes:
#   <run-dir>/draft-opus.md
#   <run-dir>/draft-codex.md  (skipped if --no-codex)
#   <run-dir>/logs/planner-{opus,codex}.log

set -uo pipefail

RUN_DIR="$1"
TASK_DESC="$2"
NO_CODEX="${3:-}"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="${SKILL_DIR}/templates/plan.md"
# Deployed tree (chezmoi strips the `executable_` prefix) is the default
# target; fall back to the source-tree name so this script also runs
# directly out of the chezmoi source (tests invoke it that way).
RUNNER="${SKILL_DIR}/scripts/runner.sh"
[ -f "$RUNNER" ] || RUNNER="${SKILL_DIR}/scripts/executable_runner.sh"
VALIDATE_DRAFT="${SKILL_DIR}/scripts/validate-draft.sh"
[ -f "$VALIDATE_DRAFT" ] || VALIDATE_DRAFT="${SKILL_DIR}/scripts/executable_validate-draft.sh"
mkdir -p "${RUN_DIR}/logs"

# A planner must invoke the Skill tool, read the writing-plans skill, and
# then write a full multi-task plan — 900s was not enough headroom and a
# planner that ran out mid-stream still exited 0, so its truncated draft
# went straight to review looking legitimate. Override with
# DEEP_PLAN_PLANNER_TIMEOUT.
PLANNER_TIMEOUT="${DEEP_PLAN_PLANNER_TIMEOUT:-1800}"

# The planners must LOAD superpowers:writing-plans themselves — we never paste its body
# into the prompt. Claude planners invoke the Skill tool; codex reads the skill file, so
# resolve its path here (newest install wins) and hand over the path only.
WP_SKILL_PATH=$(find "${HOME}/.claude/plugins" "${HOME}/.claude/skills" \
  -path '*writing-plans/SKILL.md' -not -path '*temp_git_*' 2>/dev/null | sort | tail -1)

# shellcheck disable=SC2016  # backticks below are Markdown, not command substitution
build_prompt() {
  local persona_file="$1" runner="$2"
  cat "$persona_file"
  printf '\n\n---\n\n## Required skill (load it, do not improvise)\n\n'
  if [ "$runner" = "claude" ]; then
    printf 'Before writing anything, invoke: Skill(skill="superpowers:writing-plans").\n'
    printf 'Follow it verbatim for the plan header, File Structure and `### Task N:` blocks.\n'
  else
    if [ -n "$WP_SKILL_PATH" ]; then
      printf 'Before writing anything, read the writing-plans skill at:\n  %s\n' "$WP_SKILL_PATH"
    else
      printf 'Before writing anything, load your `writing-plans` skill.\n'
    fi
    printf 'Follow it verbatim for the plan header, File Structure and `### Task N:` blocks.\n'
  fi
  printf '\n\n---\n\n## Task\n%s\n\n---\n\n## Target skeleton\n\n' "$TASK_DESC"
  cat "$TEMPLATE"
  printf '\n\n---\n\nWrite the full plan now. Output Markdown only. No commentary.\n'
}

# Opus planner
OPUS_PROMPT=$(mktemp)
build_prompt "${SKILL_DIR}/personas/planner-opus.md" claude > "$OPUS_PROMPT"
"$RUNNER" claude opus "$OPUS_PROMPT" "$PLANNER_TIMEOUT" \
  > "${RUN_DIR}/draft-opus.md" \
  2> "${RUN_DIR}/logs/planner-opus.log" &
OPUS_PID=$!

# Codex planner (optional)
CODEX_PID=""
if [ "$NO_CODEX" != "--no-codex" ]; then
  CODEX_PROMPT=$(mktemp)
  build_prompt "${SKILL_DIR}/personas/planner-codex.md" codex > "$CODEX_PROMPT"
  "$RUNNER" codex "" "$CODEX_PROMPT" "$PLANNER_TIMEOUT" \
    > "${RUN_DIR}/draft-codex.md" \
    2> "${RUN_DIR}/logs/planner-codex.log" &
  CODEX_PID=$!
fi

wait "$OPUS_PID"
OPUS_EXIT=$?
CODEX_EXIT=0
if [ -n "$CODEX_PID" ]; then
  wait "$CODEX_PID"
  CODEX_EXIT=$?
fi

echo "planners: opus=${OPUS_EXIT} codex=${CODEX_EXIT}" >&2

# A planner process exiting 0 only means the runner didn't crash or time
# out — it says nothing about whether the draft it wrote is a real, complete
# plan. This used to gate purely on process exit codes, so one valid
# planner silently masked the other ENABLED planner producing an empty or
# truncated draft (exactly the failure that motivated this script). Now
# every ENABLED planner's draft must independently pass validate-draft.sh;
# a disabled codex (--no-codex) is never required.
OPUS_VALID=0
CODEX_VALID=0

if [ "$OPUS_EXIT" -eq 0 ] && "$VALIDATE_DRAFT" "${RUN_DIR}/draft-opus.md" --json \
    > "${RUN_DIR}/draft-opus.validation.json"; then
  OPUS_VALID=1
else
  echo "dispatch-planners.sh: opus draft invalid or process failed" >&2
fi

if [ -n "$CODEX_PID" ] && [ "$CODEX_EXIT" -eq 0 ] &&
   "$VALIDATE_DRAFT" "${RUN_DIR}/draft-codex.md" --json \
    > "${RUN_DIR}/draft-codex.validation.json"; then
  CODEX_VALID=1
elif [ -n "$CODEX_PID" ]; then
  echo "dispatch-planners.sh: codex draft invalid or process failed" >&2
fi

if [ "$OPUS_VALID" -ne 1 ]; then
  echo "dispatch-planners.sh: opus planner failed" >&2
  exit 1
fi
if [ "$NO_CODEX" != "--no-codex" ] && [ "$CODEX_VALID" -ne 1 ]; then
  echo "dispatch-planners.sh: codex planner failed" >&2
  exit 1
fi

exit 0
