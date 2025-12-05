# Claude Code Commands Guide

## Quick Reference

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `/design-solution` | Design before coding | Starting a new feature |
| `/do_it` | TDD + refactor pipeline | After design is approved |
| `/review-solution-code` | Code review vs design | Before shipping |
| `/ship-it` | Quality checks + PR | Ready to merge |
| `/simplify` | Quick cleanup | Small improvements |
| `/refactor` | Deep code analysis | Architecture concerns |
| `/test` | Run tests | Verify changes |
| `/coverage` | Improve test coverage | Low coverage areas |
| `/fix` | Debug errors | Terminal errors |
| `/deps` | Dependency management | Security/updates |
| `/stack-pipeline` | Split large PRs | PR > 500 lines |

---

## Core Workflow

```
/design-solution  →  /do_it  →  /review-solution-code  →  /ship-it
```

### `/design-solution`
**Purpose**: Analyze problem, ask questions, create design document.

**Output**: `tmp/DESIGN.md`, `tmp/TASK.md`

**Use when**: Starting any non-trivial feature.

```
/design-solution
# Answers clarifying questions
# Creates design + task list
```

### `/do_it`
**Purpose**: Implement using TDD, then refactor.

**Input**: `tmp/DESIGN.md`, `tmp/TASK.md`
**Output**: Code + tests + `tmp/IMPLEMENTATION.md`

**Use when**: Design is approved, ready to code.

```
/do_it
# Writes tests first (RED)
# Implements code (GREEN)
# Refactors (REFACTOR)
```

### `/review-solution-code`
**Purpose**: Comprehensive code review against design.

**Input**: Implemented code + `tmp/DESIGN.md`
**Output**: `tmp/REVIEW.md`

**Use when**: Implementation complete, before shipping.

```
/review-solution-code
# Checks security, performance, N+1, best practices
```

### `/ship-it`
**Purpose**: Run all quality checks, create PR.

**Use when**: Code reviewed, ready to merge.

```
/ship-it
# Formats, lints, tests, security scan
# Creates PR with meaningful description
```

---

## Code Quality Commands

### `/simplify`
**Purpose**: Quick cleanup - guard clauses, reduce nesting, remove dead code.

**Use when**: Small improvements, post-implementation touchup.

```
/simplify
# Light refactoring pass
```

### `/refactor`
**Purpose**: Deep analysis - code smells, DRY, complexity, architecture.

**Use when**: Technical debt, architecture concerns, major cleanup.

```
/refactor
# Comprehensive refactoring suggestions
```

### `/test`
**Purpose**: Run project test suite.

**Use when**: Verify changes work.

```
/test
# Runs tests, reports results
```

### `/coverage`
**Purpose**: Add tests to improve coverage.

**Use when**: Coverage gaps identified.

```
/coverage
# Analyzes coverage, writes missing tests
```

---

## Utility Commands

### `/fix`
**Purpose**: Debug terminal errors using web search + docs.

**Use when**: Error message you don't understand.

```
/fix
# Reads error, searches docs, suggests fix
```

### `/deps`
**Purpose**: Audit and update dependencies.

**Use when**: Security alerts, outdated packages.

```
/deps
# Checks vulnerabilities, suggests updates
```

### `/docs`
**Purpose**: Generate/update documentation.

**Use when**: README outdated, API docs needed.

```
/docs
# Creates/updates project documentation
```

### `/security-review-custom`
**Purpose**: Security-focused code review.

**Use when**: Security-sensitive changes.

```
/security-review-custom
# High-confidence vulnerability detection only
```

---

## PR Review Commands

### `/review-pr [number]`
**Purpose**: Review a GitHub PR or local branch.

**Use when**: Reviewing someone's PR.

```
/review-pr 123
# or
/review-pr  # reviews current branch
```

### `/code-review`
**Purpose**: General codebase analysis.

**Use when**: Scanning for issues across codebase.

```
/code-review
# Updates TASK.md with prioritized issues
```

---

## PR Stack Pipeline

For splitting large PRs into reviewable stacks.

### `/stack-pipeline`
**Purpose**: Full automated PR splitting with checkpoints.

**Use when**: PR > 500 lines, multiple concerns mixed.

```
/stack-pipeline
# Analyzes → Plans → Creates → Validates → Fixes → Reports
# Human approval at each stage
```

### Recovery Commands (Advanced)
Use these only if `/stack-pipeline` fails mid-way:

| Command | Stage | Purpose |
|---------|-------|---------|
| `/analyze-branch` | 1 | Re-run analysis |
| `/plan-stack` | 2 | Re-generate plan |
| `/create-stack` | 3 | Re-create branches |
| `/validate-stack` | 4 | Re-validate CI |
| `/fix-stack` | 5 | Fix CI failures |
| `/report-slack` | 6 | Generate announcement |
| `/handle-comments` | - | Process review feedback |
| `/review-quality` | 3c | Assess stack quality |

---

## Project Setup Commands

### `/build-planning`
**Purpose**: Create project-level planning docs.

**Use when**: New project kickoff, onboarding.

**Output**: `PLANNING.md`, `TASK.md`

```
/build-planning
# Documents architecture, tech stack, conventions
```

### `/review-solution-design`
**Purpose**: Review design document for completeness.

**Use when**: After `/design-solution`, before `/do_it`.

```
/review-solution-design
# Validates design, adds review section
```

---

## Decision Tree

```
Need to implement something?
├── New feature/complex change
│   └── /design-solution → /do_it → /review-solution-code → /ship-it
├── Bug fix (simple)
│   └── /do_it → /ship-it
├── Quick cleanup
│   └── /simplify → /ship-it
└── Major refactoring
    └── /design-solution → /refactor → /ship-it

Need to review code?
├── Your own implementation
│   └── /review-solution-code
├── Someone's PR
│   └── /review-pr [number]
└── General codebase scan
    └── /code-review

Large PR to split?
└── /stack-pipeline

Error to debug?
└── /fix

Dependencies to update?
└── /deps
```

---

## File Outputs

| Command | Creates |
|---------|---------|
| `/design-solution` | `tmp/DESIGN.md`, `tmp/TASK.md` |
| `/do_it` | `tmp/IMPLEMENTATION.md` |
| `/review-solution-code` | `tmp/REVIEW.md` |
| `/review-pr` | `tmp/PR_REVIEW.md` |
| `/build-planning` | `PLANNING.md`, `TASK.md` |
| `/stack-pipeline` | `tmp/stack_*.toml` |
