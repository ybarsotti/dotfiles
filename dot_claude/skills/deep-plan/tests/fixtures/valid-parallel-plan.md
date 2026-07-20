# Widget Catalog Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fixture plan exercising a 4-lane parallel execution shape and API contract for `plan-to-json.sh` and the lane validators.

**Architecture:** Four disjoint lanes — orchestrator, planning, execution, review — each own a distinct path prefix and build against one shared, versioned contract.

**Tech Stack:** Bash, jq.

## Global Constraints

- This is a test fixture; paths under `src/` are illustrative and not meant to exist on disk.

## Execution shape

- Mode: `parallel`
- Orchestrator lane: `orchestrator`
- Shared, committed pre-fanout and read-only afterwards: `justfile`, `src/shared/contract.schema.json`
- Ownership syntax: exact repo-relative path, or a directory prefix ending in `/**`; multiple entries separated by `<br>`

| lane | scope | owns (path globs) | must-not-touch | agent | test_command | mock_command | depends_on |
|---|---|---|---|---|---|---|---|
| orchestrator | Shared contract, justfile and README wiring | `justfile`<br>`README.md`<br>`src/shared/contract.schema.json` | `src/planning/**`<br>`src/execution/**`<br>`src/review/**` | `orchestrator` | `tests/orchestrator.sh` | `none` | `none` |
| planning | Catalog parsing rules | `src/planning/**` | `src/execution/**`<br>`src/review/**` | `opus high` | `tests/planning.sh` | `none` | `orchestrator` |
| execution | Sync runner | `src/execution/**` | `src/planning/**`<br>`src/review/**` | `codex gpt-5.6-terra high` | `tests/execution.sh` | `none` | `orchestrator` |
| review | Final checklist and acceptance tests | `src/review/**` | `src/planning/**`<br>`src/execution/**` | `sonnet high` | `tests/review.sh` | `none` | `none` |

## API contract

- Contract version: `1.0.0`
- Materialized contract: `src/shared/contract.schema.json`
- Contract kind: `json-schema`
- Contract validation command: `jq -e '.type' src/shared/contract.schema.json`
- Endpoints: none — this is a shell-only sync tool with no HTTP surface.

## Affected files

- `justfile` — orchestrator wiring
- `README.md` — orchestrator docs
- `src/shared/contract.schema.json` — the materialized contract
- `src/planning/parser.sh` — catalog parsing rules
- `src/execution/runner.sh` — sync runner
- `src/review/checklist.sh` — final acceptance checklist

## Implementation tasks

### Task 1: Wire the shared contract and orchestrator harness

**Lane:** `orchestrator`

**Files:**

- Create: `src/shared/contract.schema.json`
- Modify: `justfile`
- Modify: `README.md`

**Interfaces:**

- `src/shared/contract.schema.json` — JSON Schema, `type` required.

- [ ] **Step 1: Write the failing contract test** — assert `jq -e '.type'` on the schema.
- [ ] **Step 2: Run it and verify the red state** — file missing.
- [ ] **Step 3: Create the schema** — minimal valid JSON Schema document.
- [ ] **Step 4: Run it and verify green**.

### Task 2: Implement the planning-lane parser

**Lane:** `planning`

**Files:**

- Create: `src/planning/parser.sh`

**Interfaces:**

- `parser.sh CATALOG.csv` prints normalized rows to stdout.

- [ ] **Step 1: Write the failing parser test**.
- [ ] **Step 2: Run it and verify the red state**.
- [ ] **Step 3: Implement `parser.sh`**.
- [ ] **Step 4: Run it and verify green**.

### Task 3: Implement the execution-lane runner

**Lane:** `execution`

**Files:**

- Create: `src/execution/runner.sh`

**Interfaces:**

- `runner.sh CATALOG.csv` syncs normalized rows to the target store.

- [ ] **Step 1: Write the failing runner test**.
- [ ] **Step 2: Run it and verify the red state**.
- [ ] **Step 3: Implement `runner.sh`**.
- [ ] **Step 4: Run it and verify green**.

### Task 4: Implement the review-lane checklist

**Lane:** `review`

**Files:**

- Create: `src/review/checklist.sh`

**Interfaces:**

- `checklist.sh` exits 0 iff every acceptance check passes.

- [ ] **Step 1: Write the failing checklist test**.
- [ ] **Step 2: Run it and verify the red state**.
- [ ] **Step 3: Implement `checklist.sh`**.
- [ ] **Step 4: Run it and verify green**.

## Superpowers invoked

- [ ] grill-with-docs
- [ ] brainstorming
- [ ] writing-plans
