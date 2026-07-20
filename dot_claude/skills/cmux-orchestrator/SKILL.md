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
```

If it fails, tell the user and stop. `claude`/`codex` availability is checked per-runner by `launch-workers.sh` at launch time — don't hard-require `claude` here for a codex-only run.

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

## Phase 2 — Prepare the Run

Create a unique run directory, then let `prepare-run.sh` write all the fixed scaffolding — the shared system prompt, each worker's prompt/result files, and `manifest.json`. It launches nothing and is idempotent (safe to re-run, e.g. after adding a worker — it won't overwrite prompt/result files that already exist).

```bash
RUN_ID="cmux-$(date +%Y%m%d-%H%M%S)"
RUN_DIR="/tmp/cmux-orchestrator/${RUN_ID}"
mkdir -p "${RUN_DIR}"

~/.claude/skills/cmux-orchestrator/scripts/prepare-run.sh \
  "${RUN_DIR}" "$(pwd)" "${ORCH_SURFACE}" \
  auth-refactor add-tests api-docs
```

The script is at `~/.claude/skills/cmux-orchestrator/scripts/prepare-run.sh`. Worker specs use the same `name` / `name:runner:model` / `name:runner:model@effort` grammar as `launch-workers.sh` (Phase 3) — pass the identical specs to both.

It writes:
- `${RUN_DIR}/system-prompt.txt` — from `templates/system-prompt.txt`, or a custom file via `--system-prompt FILE`
- `${RUN_DIR}/worker-<name>.prompt.md` and `.result.md` per worker
- `${RUN_DIR}/manifest.json` — `worker_pane_ref` plus one entry per worker (`name`, `surface_ref`, `status`, `prompt_file`, `result_file`, `done_marker`)

**Before launching**, open every `worker-<name>.prompt.md` and replace the `<placeholder>` Task / Files to Work With / Context / Success Criteria sections with the real, subtask-specific content decided in Phase 1 — `prepare-run.sh` only writes the fixed scaffolding, never the judgement.

## Phase 3 — Create Sessions (use the helper script)

**ALWAYS use the `launch-workers.sh` script** to create sessions. Do NOT manually run `cmux send`, `cmux new-pane`, or `cmux new-surface` — the script handles all of that correctly.

The script creates this layout:

```
┌───────────────────────┬─────────────────────┐
│                       │ [w:auth][w:test][w:d]│ ← tabs
│   ORCHESTRATOR (big)  │                     │
│                       │   worker pane       │
│                       │   (smaller)         │
└───────────────────────┴─────────────────────┘
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
1. Creates ONE worker pane (split right from orchestrator)
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

Switch back to the orchestrator workspace. Call `monitor-workers.sh "${RUN_DIR}"` — it blocks until one worker's state changes, prints exactly one trigger as JSON, and exits. Keep calling it in a loop until every worker has reached a terminal state.

```bash
~/.claude/skills/cmux-orchestrator/scripts/monitor-workers.sh "${RUN_DIR}"
```

Trigger `type` is one of `done`, `blocked`, `crashed` (pane vanished), or `failed` (fatal signature in the pane log, or the script's own bounded wait ran out without any of the above). Use the Monitor tool to run this loop in the background instead of blocking on it turn by turn.

### On each trigger

- **`done`**: update `manifest.json` status, tell the user in one line, keep polling
- **`blocked`**: immediately notify the user with `AskUserQuestion` offering resolution options
- **`crashed`**: mark crashed in `manifest.json`, notify the user
- **`failed`**: notify the user with the reason from the trigger JSON

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

## Reusing Idle Workers

After a worker completes its task, its pane stays alive and idle. **Reuse idle panes** for new tasks instead of creating new ones. Use the `send-task.sh` script — it automatically appends `\n` so the prompt auto-submits:

```bash
# Send a text prompt to an idle worker (auto-submits with Enter)
~/.claude/skills/cmux-orchestrator/scripts/send-task.sh <surface_ref> "Your task prompt here"

# Send a prompt file to an idle worker
~/.claude/skills/cmux-orchestrator/scripts/send-task.sh <surface_ref> --file /tmp/cmux-orchestrator/run-123/worker-fix.prompt.md
```

**NEVER use raw `cmux send` directly** — the script handles the `\n` (Enter key) automatically. Without it, text is pasted but not submitted and the user must press Enter manually.

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
