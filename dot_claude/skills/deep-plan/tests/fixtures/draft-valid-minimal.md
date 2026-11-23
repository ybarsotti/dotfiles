# Sample Feature Implementation Plan

> **For agentic workers:** Build this plan with the `implement` skill, or with the executor that `~/.claude/skills/_shared/plan-routing.md` picks. After the build, run `~/.claude/skills/_shared/after-approval.md` to the end, through the final deep review and the PR. Track each step with `~/.claude/skills/_shared/workflow.sh` in the step file below. Do not use `superpowers:finishing-a-development-branch`.

**Goal:** Ship the sample feature end to end.

**Architecture:** A single service change behind an existing adapter boundary.

**Tech Stack:** Bash, jq.

## Implementation tasks

### Task 1: Do the thing

**Files:**

- Create: `src/thing.sh`

**Interfaces:**

- `thing.sh ARG` — does the thing.

- [ ] **Step 1: Write the failing test**
- [ ] **Step 2: Run it and watch it fail**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run it and watch it pass**

An illustrative fence, present so a fence-aware parser has something to skip:

```bash
echo "example only, not a real task"
```

## Checklist (machine-validated; do NOT hand-edit — call tick-checklist.sh)

- [ ] mermaid-present
- [ ] tasks-≥1
- [ ] no-tbd-placeholders
- [ ] superpowers-all-invoked
