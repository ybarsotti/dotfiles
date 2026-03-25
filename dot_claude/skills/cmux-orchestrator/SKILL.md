---
name: cmux-orchestrator
description: Parallelize work across multiple Claude Code sessions using cmux terminal multiplexer. Use this skill whenever the user asks to run tasks in parallel, split work across agents, fan out subtasks, orchestrate multiple workers, or when a task has 2+ independent subtasks that benefit from concurrent execution. Triggers on "parallelize", "fan out", "split work", "multi-agent", "orchestrate", "run in parallel", "cmux workers", "concurrent tasks", "spawn workers", "run these simultaneously", "multi-session", or any request to divide work across multiple Claude instances. Even if the user just says "can you run these at the same time" or "do these in parallel", use this skill.
---

# cmux Orchestrator

You are a parallel task orchestrator. Instead of spawning internal subagents, you create real Claude Code sessions in cmux terminal panes — each working independently on a subtask with full tool access. You coordinate their work, track progress, and synthesize results.

This approach gives visible, persistent worker sessions that the user can inspect, interact with, and keep alive after completion.

## Prerequisites

Before anything else, verify the environment:

```bash
cmux identify --json
which claude
```

If either fails, tell the user and stop.

Save the orchestrator's identity:

```bash
ORCH_INFO=$(cmux identify --json)
ORCH_SURFACE=$(echo "$ORCH_INFO" | jq -r '.caller.surface_ref')
ORCH_WORKSPACE=$(echo "$ORCH_INFO" | jq -r '.caller.workspace_ref')
```

## Phase 1 — Plan (MANDATORY)

**Never create sessions before the plan is approved by the user.**

1. Analyze the user's request and decompose it into independent subtasks
2. Identify dependencies — serialize those, parallelize only independent ones
3. For each subtask determine:
   - **Worker name**: short, descriptive, kebab-case (e.g. `auth-refactor`, `add-tests`)
   - **Files and directories** it will read or modify
   - **Context**: documentation paths, architecture notes
   - **Success criteria**: concrete definition of done
   - **Dependencies**: which other workers must finish first (avoid when possible)

4. Present the plan as a table:

```
| # | Worker Name    | Task Summary             | Key Files            | Depends On |
|---|----------------|--------------------------|----------------------|------------|
| 1 | auth-refactor  | Refactor auth middleware  | src/auth/*.ts        | none       |
| 2 | add-tests      | Add unit tests for users  | tests/users/**       | none       |
| 3 | api-docs       | Generate OpenAPI spec     | docs/, src/routes/*  | none       |
```

5. Use `AskUserQuestion` with selection options to get approval — never ask the user to type "yes" or "no" freehand:
   - Header: "Plan"
   - Options: "Approve (Recommended)" / "Adjust" / "Cancel"
   - If the user selects "Adjust", ask what to change with another `AskUserQuestion`

6. Record the working directory — all workers must share the same `cwd`

**Always use `AskUserQuestion` with predefined options for any decision point** — plan approval, cleanup confirmation, blocked worker resolution, etc.

## Phase 2 — Setup Run Directory

Create a unique run directory and all coordination files:

```bash
RUN_ID="cmux-$(date +%Y%m%d-%H%M%S)"
RUN_DIR="/tmp/cmux-orchestrator/${RUN_ID}"
mkdir -p "${RUN_DIR}"
```

### 2a. Write the shared system prompt

Write `${RUN_DIR}/system-prompt.txt` — delivered to workers via `--append-system-prompt-file`:

```
You are a worker agent in a cmux parallel orchestration.

## Protocol

1. Your first action: read the task file path given in your initial message.
2. Execute the task completely and thoroughly.
3. When finished, write a markdown summary of everything you did to your result file (path is in the task file).
4. Then write exactly "done" to your done marker file (path is in the task file).
5. If you hit a blocking issue you cannot resolve, write "blocked: <reason>" to the done marker instead.
6. Stay available for follow-up — do NOT exit or close the session.

## Tool Integration

### Serena (semantic code tools)
Prefer Serena's semantic tools over text-based grep/sed when available:
- Use find_symbol and get_symbols_overview for code navigation
- Use replace_symbol_body for precise, symbol-level edits
- Use find_referencing_symbols to understand call chains before refactoring

### GitNexus (code intelligence graph)
Before modifying any function, class, or method:
- Run gitnexus_impact to check blast radius — if HIGH or CRITICAL, write "blocked: high-impact change on <symbol>, needs orchestrator review" to your done marker
- Run gitnexus_detect_changes before writing your done marker to verify changes match expected scope
- Use gitnexus_query to find related code by concept instead of grepping

### General
- Read CLAUDE.md in the project root for project-specific conventions
- Follow existing code patterns and style
- Prefer immutable patterns — create new objects, never mutate existing ones
- Handle errors explicitly at every level
```

### 2b. Write per-worker task files

For each worker, write `${RUN_DIR}/worker-<name>.prompt.md`:

```markdown
# Task: <Worker Name>

## Orchestration Info
- Run ID: <RUN_ID>
- Run directory: <RUN_DIR>
- Orchestrator surface: <ORCH_SURFACE>
- Result file: <RUN_DIR>/worker-<name>.result.md
- Done marker: <RUN_DIR>/worker-<name>.done

## Task
<Detailed task description — be specific about what to do, not vague>

## Files to Work With
<Explicit list of files and directories, with brief notes on what's relevant in each>

## Context
<Architecture notes, related documentation paths, design decisions the worker needs to know>

## Success Criteria
<Concrete, verifiable definition of done>

## When Finished
1. Write a markdown summary of all changes you made to: <RUN_DIR>/worker-<name>.result.md
2. Include a list of every file you created or modified
3. Write "done" (just that word) to: <RUN_DIR>/worker-<name>.done
4. Stay available — do not exit
```

### 2c. Write manifest

Write `${RUN_DIR}/manifest.json` to track orchestration state:

```json
{
  "run_id": "<RUN_ID>",
  "created_at": "<ISO timestamp>",
  "cwd": "<working directory>",
  "orchestrator_surface": "<ORCH_SURFACE>",
  "worker_pane_ref": null,
  "workers": [
    {
      "name": "<name>",
      "surface_ref": null,
      "status": "pending",
      "prompt_file": "<RUN_DIR>/worker-<name>.prompt.md",
      "result_file": "<RUN_DIR>/worker-<name>.result.md",
      "done_marker": "<RUN_DIR>/worker-<name>.done"
    }
  ]
}
```

## Phase 3 — Create Sessions (use the helper script)

**ALWAYS use the `launch-workers.sh` script** to create sessions. Do NOT manually run `cmux send`, `cmux new-pane`, or `cmux new-surface` — the script handles all of that correctly.

The script creates this layout:

```
┌─────────────────────────────────────┐
│                                     │
│         ORCHESTRATOR (big)          │
│                                     │
├─────────────────────────────────────┤
│ [w: auth] [w: tests] [w: docs]     │  ← tabs
│         worker pane (smaller)       │
└─────────────────────────────────────┘
```

Workers share one pane below the orchestrator as tabs. The user clicks tabs to switch between workers.

### Running the script

The script is at `~/.claude/skills/cmux-orchestrator/scripts/launch-workers.sh`.

```bash
~/.claude/skills/cmux-orchestrator/scripts/launch-workers.sh <RUN_DIR> <CWD> <worker1> <worker2> [worker3] ...
```

**Example:**

```bash
~/.claude/skills/cmux-orchestrator/scripts/launch-workers.sh \
  /tmp/cmux-orchestrator/cmux-20260324-150000 \
  /Users/me/project \
  auth-refactor add-tests api-docs
```

The script:
1. Creates ONE worker pane (split down from orchestrator)
2. Adds a tab (`new-surface`) per additional worker in that pane
3. Launches `claude --model sonnet --name '<name>' --dangerously-skip-permissions --append-system-prompt-file <run_dir>/system-prompt.txt` in each tab
4. Waits 12 seconds for Claude to initialize
5. Renames tabs to `w: <name>` (after Claude starts, so it doesn't overwrite)
6. Sends the task prompt to each worker
7. Outputs JSON with `pane_ref` and worker `surface_ref` values

**Output JSON (use to update manifest.json):**

```json
{
  "pane_ref": "pane:5",
  "workers": [
    {"name": "auth-refactor", "surface_ref": "surface:10"},
    {"name": "add-tests", "surface_ref": "surface:11"},
    {"name": "api-docs", "surface_ref": "surface:12"}
  ]
}
```

### After the script completes

1. Parse the JSON output and update `manifest.json` with surface refs and set all statuses to `"running"`
2. Set sidebar status: `cmux set-status "orchestrator" "N workers running" --icon sparkle --color "#ff9500"`
3. Set initial progress: `cmux set-progress 0.0 --label "0/N workers done"`
4. Log the event: `cmux log "Orchestration started: N workers"`

## Phase 4 — Monitor

Switch back to the orchestrator workspace and poll worker completion by checking done marker files.

```bash
# Check all done markers in one pass
DONE_COUNT=0
TOTAL=<number of workers>
for worker in <worker-names>; do
  if [ -f "${RUN_DIR}/worker-${worker}.done" ]; then
    STATUS=$(cat "${RUN_DIR}/worker-${worker}.done")
    DONE_COUNT=$((DONE_COUNT + 1))
    echo "${worker}: ${STATUS}"
  else
    echo "${worker}: running"
  fi
done
echo "${DONE_COUNT}/${TOTAL} complete"
```

### Monitoring rules

- **Poll interval**: every 30-60 seconds
- **Status updates**: after each poll, tell the user which workers are done and which are still running — keep it to one line
- **Progress bar**: `cmux set-progress $(echo "scale=2; ${DONE_COUNT}/${TOTAL}" | bc) --label "${DONE_COUNT}/${TOTAL} workers done"`
- **Blocked workers**: if a done marker contains `blocked: <reason>`, notify the user immediately with `AskUserQuestion` offering options to resolve
- **Peeking**: use `cmux capture-pane --surface <ref> --lines 5` to check what a worker is doing if the user asks
- **Crash detection**: if `cmux capture-pane --surface <ref>` fails, the worker pane likely closed — mark as crashed in manifest, notify user
- **Completion notification**: when all workers are done, run `cmux notify --title "Orchestration Complete" --body "All ${TOTAL} workers finished"`

### Recovery

If the orchestrator loses context (e.g., after context compaction), re-read `manifest.json` to recover all surface refs and file paths.

## Phase 5 — Synthesize

Once ALL done markers exist and contain "done" (or "blocked"):

1. Read every `worker-<name>.result.md`
2. Compile a unified summary:

```markdown
## Orchestration Results — <RUN_ID>

### Summary: <done_count> completed, <blocked_count> blocked out of <total>

#### Worker: <name>
- **Status**: done | blocked
- **Changes**: <brief summary from result file>
- **Files modified**: <list>

(repeat for each worker)

### Integration Notes
<Any conflicts between workers, overlapping file changes, or coordination issues>

### Recommended Next Steps
- Run `git diff` to review all changes holistically
- Run tests to verify nothing broke
- Review any blocked workers and decide how to proceed
```

3. Update sidebar: `cmux set-status "orchestrator" "complete" --icon sparkle --color "#00ff00"`
4. Set progress to 100%: `cmux set-progress 1.0 --label "Done"`

**Only present the final summary when ALL workers have reported.** Small per-poll status updates are fine, but the comprehensive synthesis waits until everyone is done.

## Cleanup

**Never clean up automatically.** Workers stay alive until the user explicitly says to close them.

When the user is ready (use `AskUserQuestion` to confirm), provide cleanup:

```bash
# Close all worker surfaces (tabs) in the worker pane
for surface in <surface-refs-from-manifest>; do
  cmux close-surface --surface "${surface}"
done
# The worker pane auto-closes when its last surface is closed

# Remove run directory
rm -rf "${RUN_DIR}"

# Clear sidebar
cmux set-status "orchestrator" "idle" --icon sparkle
cmux set-progress 0.0 --label ""
```

## Error Handling

| Scenario | Action |
|----------|--------|
| Not inside cmux | Abort with clear message — suggest opening cmux |
| `claude` CLI not found | Abort — suggest `npm install -g @anthropic-ai/claude-code` |
| Pane creation fails | Retry once, then abort that worker and notify user |
| Worker writes "blocked" | Immediately notify user with `AskUserQuestion` offering resolution options |
| Worker pane disappears | Detect via failed `capture-pane`, mark crashed in manifest, notify user |
| Orchestrator loses context | Re-read `manifest.json` from `${RUN_DIR}` to recover all state |
| All workers fail | Summarize all failures, suggest running tasks sequentially as fallback |

## Constraints

- **Maximum 6 concurrent workers** — more causes UI clutter and diminishing returns
- **Workers use `--model sonnet`** by default for cost efficiency. The user can override.
- **Orchestrator uses whatever model the user chose** — it handles planning
- **Workers run `--dangerously-skip-permissions`** — only in trusted project directories
- **Never parallelize dependent tasks** — serialize them instead
- **Workers must not exit** until the user says so — they stay in interactive mode
