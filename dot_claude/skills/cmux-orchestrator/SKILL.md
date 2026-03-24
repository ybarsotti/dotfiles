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
# Must succeed — confirms we're inside cmux
cmux identify --json

# Must be available
which claude
```

If either fails, tell the user and stop. Suggest `brew install --cask cmux` or installing Claude CLI as needed.

Save the orchestrator's own identity for later reference:

```bash
ORCH_INFO=$(cmux identify --json)
ORCH_SURFACE=$(echo "$ORCH_INFO" | jq -r '.caller.surface_ref')
ORCH_WORKSPACE=$(echo "$ORCH_INFO" | jq -r '.caller.workspace_ref')
```

## Phase 1 — Plan (MANDATORY)

**Never create sessions before the plan is approved by the user.**

1. Analyze the user's request and decompose it into independent subtasks
2. Identify tasks that have dependencies — serialize those, parallelize only independent ones
3. For each subtask determine:
   - **Worker name**: short, descriptive, kebab-case (used as `--name` flag, e.g. `auth-refactor`, `add-tests`, `api-docs`)
   - **Files and directories** it will read or modify
   - **Context**: documentation paths, architecture notes, relevant background
   - **Success criteria**: concrete definition of done
   - **Dependencies**: which other workers (if any) must finish first — avoid these when possible

4. Present the plan as a table:

```
| # | Worker Name    | Task Summary             | Key Files            | Depends On |
|---|----------------|--------------------------|----------------------|------------|
| 1 | auth-refactor  | Refactor auth middleware  | src/auth/*.ts        | none       |
| 2 | add-tests      | Add unit tests for users  | tests/users/**       | none       |
| 3 | api-docs       | Generate OpenAPI spec     | docs/, src/routes/*  | none       |
```

5. Ask the user to confirm or adjust before proceeding
6. Record the working directory — all workers must share the same `cwd`

## Phase 2 — Setup Run Directory

Create a unique run directory and all coordination files:

```bash
RUN_ID="cmux-$(date +%Y%m%d-%H%M%S)"
RUN_DIR="/tmp/cmux-orchestrator/${RUN_ID}"
mkdir -p "${RUN_DIR}"
```

### 2a. Write the shared system prompt

Write `${RUN_DIR}/system-prompt.txt` — this is appended to every worker's system prompt via `--append-system-prompt-file`:

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
- Use insert_before_symbol / insert_after_symbol for adding code at the right location

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

## Phase 3 — Create Sessions

### Layout strategy

| Workers | Layout |
|---------|--------|
| 2       | Split right from orchestrator pane |
| 3       | Split right, then split right pane down |
| 4-6     | New workspace with grid splits |

For 4+ workers, create a dedicated workspace so the orchestrator stays uncluttered:

```bash
WORKER_WS=$(cmux --json new-workspace | jq -r '.workspace_ref')
cmux rename-workspace --workspace "${WORKER_WS}" "workers: ${RUN_ID}"
```

### Launch each worker

For each worker in the plan:

```bash
# 1. Create a new pane (alternate right/down for grid layout)
PANE_JSON=$(cmux --json new-pane --direction right)
SURFACE_REF=$(echo "$PANE_JSON" | jq -r '.surface_ref')

# 2. Name the tab for sidebar visibility
cmux rename-tab --surface "${SURFACE_REF}" "w: <name>"

# 3. Launch Claude in the pane
cmux send --surface "${SURFACE_REF}" -- "cd <cwd> && claude --model sonnet --name '<name>' --dangerously-skip-permissions --append-system-prompt-file ${RUN_DIR}/system-prompt.txt\n"

# 4. Wait for Claude to initialize
sleep 5

# 5. Send the task prompt
cmux send --surface "${SURFACE_REF}" -- "Read and execute the task described at ${RUN_DIR}/worker-<name>.prompt.md — start immediately.\n"
```

After launching each worker:
- Update `manifest.json` with the worker's `surface_ref` and set status to `"running"`
- Set sidebar status: `cmux set-status "orchestrator" "<N> workers running" --icon sparkle`
- Set initial progress: `cmux set-progress 0.0 --label "0/${TOTAL} workers done"`

**Important**: launch ALL workers before starting to monitor. Do not wait for one to finish before launching the next.

## Phase 4 — Monitor

Poll worker completion by checking done marker files. Between polls, give the user brief status updates.

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
- **Blocked workers**: if a done marker contains `blocked: <reason>`, notify the user immediately and ask how to proceed
- **Peeking**: use `cmux capture-pane --surface <ref> --lines 5` to check what a worker is currently doing if the user asks
- **Crash detection**: if `cmux capture-pane --surface <ref>` fails, the worker pane likely closed — mark as crashed in manifest, notify user
- **Completion notification**: when all workers are done, run `cmux notify --title "Orchestration Complete" --body "All ${TOTAL} workers finished"`

### Recovery

If the orchestrator loses context (e.g., after context compaction), re-read `manifest.json`:

```bash
cat ${RUN_DIR}/manifest.json
```

This has all surface refs and file paths needed to resume monitoring.

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

When the user is ready, provide cleanup commands:

```bash
# Close all worker panes
for surface in <surface-refs-from-manifest>; do
  cmux close-surface --surface "${surface}"
done

# Close worker workspace if one was created
cmux close-workspace --workspace "${WORKER_WS}"

# Remove run directory
rm -rf "${RUN_DIR}"
```

## Error Handling

| Scenario | Action |
|----------|--------|
| Not inside cmux | Abort with clear message — suggest opening cmux |
| `claude` CLI not found | Abort — suggest `npm install -g @anthropic-ai/claude-code` |
| Pane creation fails | Retry once with opposite direction, then abort that worker and notify user |
| Worker writes "blocked" | Immediately notify user with the reason, ask for guidance |
| Worker pane disappears | Detect via failed `capture-pane`, mark crashed in manifest, notify user |
| Orchestrator loses context | Re-read `manifest.json` from `${RUN_DIR}` to recover all state |
| All workers fail | Summarize all failures, suggest running tasks sequentially as fallback |

## Constraints

- **Maximum 6 concurrent workers** — more causes UI clutter and diminishing returns
- **Workers use `--model sonnet`** by default for cost efficiency. The user can override per-worker or globally.
- **Orchestrator uses whatever model the user chose** — it handles planning, which benefits from deeper reasoning
- **Workers run `--dangerously-skip-permissions`** — only appropriate in trusted project directories
- **Never parallelize dependent tasks** — if worker B needs worker A's output, serialize them (run A first, then B)
- **Workers must not exit** until the user says so — they stay in interactive mode for follow-up questions

## Example

**User**: "Parallelize this: refactor the auth module, add missing tests for UserService, and update the README"

**Orchestrator**:
1. Presents plan with 3 workers: `auth-refactor`, `user-tests`, `readme-update`
2. User approves
3. Creates `/tmp/cmux-orchestrator/cmux-20260324-150000/`
4. Writes system prompt, 3 task files, manifest
5. Creates 3 cmux panes, launches Claude Sonnet in each
6. Monitors every 30s: "auth-refactor: running, user-tests: done, readme-update: running"
7. All 3 finish → reads results → presents unified summary
8. Workers stay alive for follow-up until user says to clean up
