---
name: zorch
description: |
  Use when the user wants to run multiple coding tasks in parallel
  using Zellij, mentions "zorch", "spawn agent", "new worktree agent",
  or wants to split work across multiple Claude instances.
---

# zorch — Zellij Agent Orchestrator

zorch manages parallel AI coding agents in Zellij using git worktrees.
Each agent gets its own worktree, branch, and Zellij pane running Claude Code.

## CLI Commands

### Create a new agent
```bash
zorch new /path/to/project --prompt "Implement JWT authentication" --slug "add-jwt-auth"
```
This creates:
- Git worktree at `.claude/worktrees/<slug>` with branch `zorch/<slug>`
- New Zellij pane running Claude Code with the prompt

### Merge an agent's work
```bash
zorch merge <slug>
```
Merges the agent's branch into main, then cleans up worktree and branch.

### Close/discard an agent
```bash
zorch close <slug>
```
Removes the worktree and branch without merging.

### List active agents
```bash
zorch list          # Human-readable
zorch list --json   # JSON for scripting
```

### Check status
```bash
zorch status
```

## Best Practices

1. **Use descriptive prompts** — the slug is auto-generated from the prompt
2. **One task per agent** — keep agents focused on a single feature/fix
3. **Merge frequently** — merge agents once their task is complete to avoid drift
4. **Review before merge** — check the agent's work before merging into main
5. **Close failed agents** — use `close` to discard agents that went wrong

## Conventions

- Branches: `zorch/<slug>` (e.g., `zorch/add-jwt-auth`)
- Worktrees: `.claude/worktrees/<slug>`
- Pane names: `zorch: <slug>`
- State: `~/.local/share/zorch/state.json`

## Zellij Plugin

The zorch dashboard is accessible via `Alt+z` in Zellij.
From the dashboard: `n` to create, `m` to merge, `x` to close, `Enter` to focus.
