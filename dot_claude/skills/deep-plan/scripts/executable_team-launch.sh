#!/usr/bin/env bash
# team-launch.sh — verify agent-teams prerequisites and print the spawn prompt.
#
# Usage: team-launch.sh <run-dir>
#
# Exits non-zero if prereqs are missing. Prints the natural-language prompt the
# orchestrator must issue to spawn the team (per
# https://code.claude.com/docs/en/agent-teams — teams are created via prompting,
# not via a CLI flag).

set -uo pipefail

RUN_DIR="$1"
PLAN="${RUN_DIR}/plan.md"

[ -f "$PLAN" ] || { echo "team-launch.sh: missing $PLAN" >&2; exit 1; }

# 1. Env var set?
if [ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" != "1" ]; then
  # Fall back to reading settings.json (where this repo also sets it).
  if [ -f "$HOME/.claude/settings.json" ] && jq -e '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS == "1"' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
    : # OK — settings.json enables it
  else
    echo "team-launch.sh: agent-teams not enabled. Add to ~/.claude/settings.json: { \"env\": { \"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS\": \"1\" } }" >&2
    exit 2
  fi
fi

# 2. Version check (≥ 2.1.32).
if command -v claude >/dev/null 2>&1; then
  VER=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")
  awk -v v="$VER" 'BEGIN {
    split(v, a, ".");
    if (a[1] < 2 || (a[1] == 2 && a[2] < 1) || (a[1] == 2 && a[2] == 1 && a[3] < 32)) exit 1;
    exit 0
  }' || {
    echo "team-launch.sh: claude $VER < 2.1.32 (agent-teams requires 2.1.32+)" >&2
    exit 3
  }
fi

# 3. Extract affected-files list from plan to use as ownership boundaries.
AFFECTED=$(awk '/^## Affected files/{flag=1; next} /^## /{flag=0} flag' "$PLAN" | head -30)

cat <<EOF
=== AGENT TEAM SPAWN PROMPT — issue this to the lead session verbatim ===

Create an agent team to execute the plan at ${PLAN}. Use Sonnet for each teammate. Spawn 3 teammates to start; add a 4th codex-model teammate if the plan calls out a parallelizable scaffolding/fixture slice.

Split work along the file-ownership boundaries below; one teammate owns each boundary so two teammates never edit the same file:

${AFFECTED:-<read affected files from the plan>}

Require plan approval before any teammate writes code (per the agent-teams docs: "Require plan approval for teammates"). Each teammate follows strict red-green-refactor TDD per the superpowers:test-driven-development skill, and respects the project's CLAUDE.md conventions.

After all teammates report idle and tests are green locally, ask the team to clean up.

=== END SPAWN PROMPT ===
EOF
