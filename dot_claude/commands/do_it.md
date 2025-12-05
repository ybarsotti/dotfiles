# Do It - TDD Implementation + Refactoring Pipeline

You are an expert developer who implements solutions using Test-Driven Development and then refactors for simplicity and quality. This command chains the full implementation workflow.

**Usage**: `/do_it [task-file]` (defaults to `tmp/TASK.md`)

## Prerequisites

Before running this command, ensure:
- `tmp/DESIGN.md` exists (created by `/design-solution`)
- `tmp/TASK.md` exists (created by `/design-solution`)

If these files don't exist, inform the user to run `/design-solution` first.

---

## Pipeline Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         /do_it                              │
├─────────────────────────────────────────────────────────────┤
│  1. Read TASK.md + DESIGN.md                                │
│  2. TDD Implementation (Red → Green → Refactor cycle)       │
│  3. Full Refactoring Pass                                   │
│  4. Update TASK.md with progress                            │
│  5. Generate implementation summary                         │
└─────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Setup & Verification

1. **Check prerequisites**:
   - Verify `tmp/DESIGN.md` exists
   - Verify `tmp/TASK.md` exists (or use provided task file)
   - If missing, STOP and tell user to run `/design-solution` first

2. **Read and understand**:
   - Read `tmp/TASK.md` for actionable tasks
   - Read `tmp/DESIGN.md` for solution architecture
   - Identify the implementation order from the task phases

3. **Update task status**:
   - Change TASK.md status from "🟡 Ready for Implementation" to "🔵 In Progress"

---

## Phase 2: TDD Implementation

For each task in TASK.md, follow the strict TDD cycle:

### 🔴 RED: Write Failing Tests First

**CRITICAL**: Tests MUST be written BEFORE any implementation code.

For each task:
1. Write unit tests describing expected behavior
2. Cover scenarios:
   - Happy path (normal operation)
   - Edge cases (boundary conditions, empty/null values)
   - Error cases (invalid input, exceptions)
3. Run tests → They MUST fail (no implementation yet)
4. Include performance tests where specified in TASK.md:
   - Query count assertions (prevent N+1)
   - Response time benchmarks
   - Large dataset handling

### 🟢 GREEN: Implement Minimum Code

1. Write the simplest code that makes tests pass
2. Follow the design from DESIGN.md
3. Use existing code identified in the design
4. Run tests → All must pass before proceeding
5. **DO NOT proceed to refactor if tests fail**

### 🔵 REFACTOR: Clean Up (Mini-refactor)

1. Clean up implementation without changing behavior
2. Remove obvious duplication
3. Improve naming and readability
4. Run tests → Must still pass

### Progress Tracking

After completing each task:
- Update TASK.md: Change `- [ ]` to `- [x]` for completed items
- Add brief implementation notes if design deviated

---

## Phase 3: Full Refactoring Pass

After ALL tasks are implemented and tests pass, perform a comprehensive refactoring:

### Code Quality Analysis

Analyze the implemented code for:

1. **Code Smells**:
   - Duplicated code across new files
   - Long methods/functions (>30 lines)
   - Large classes/modules
   - Long parameter lists
   - Feature envy (methods using other class's data)

2. **Complexity Issues**:
   - Deep nesting (>3 levels)
   - Complex conditionals
   - High cyclomatic complexity

3. **Performance Issues**:
   - N+1 queries (queries in loops)
   - Missing bulk operations
   - Missing caching opportunities
   - Inefficient algorithms

4. **DRY Violations**:
   - Repeated logic that could be extracted
   - Similar code patterns that could be unified

### Refactoring Actions

Apply these refactoring patterns as needed:

- **Extract Method**: Break long functions into smaller, focused ones
- **Extract Class/Module**: Split responsibilities
- **Simplify Conditionals**: Use guard clauses, early returns
- **Remove Duplication**: Create shared utilities
- **Improve Naming**: Make code self-documenting
- **Optimize Queries**: Batch operations, add caching

### Verify After Refactoring

After each refactoring change:
1. Run all tests → Must pass
2. Verify no behavior changes
3. Check performance tests still pass

---

## Phase 4: Finalize

### Update Documentation

1. **Update TASK.md**:
   - Mark all completed tasks with `[x]`
   - Change status to "🟢 Implementation Complete"
   - Add any deviations or notes

2. **Create/Update tmp/IMPLEMENTATION.md**:
   ```markdown
   # Implementation Notes

   ## Overview
   [Brief description of what was implemented]

   ## Files Changed
   - `path/to/file1.ext` - [What was added/changed]
   - `path/to/file2.ext` - [What was added/changed]

   ## Test Coverage
   - Total tests written: [number]
   - All tests passing: ✅ Yes
   - Coverage areas: [list]

   ## Performance Verification
   - N+1 queries: ✅ Prevented
   - Bulk operations: ✅ Used where applicable
   - Response times: ✅ Within targets

   ## Refactoring Applied
   - [Refactoring 1]: [Brief description]
   - [Refactoring 2]: [Brief description]

   ## Deviations from Design
   - [Any changes from original DESIGN.md and why]

   ## Ready for Review
   Run `/review-solution-code` for comprehensive code review.
   ```

### Final Summary

Output a summary:
```
✅ /do_it Complete

📝 Tasks Completed: X/Y
🧪 Tests: [number] written, all passing
🔄 Refactoring: [number] improvements applied
📁 Files Modified: [list]

📋 Next Steps:
1. Run /review-solution-code for code review
2. Run /ship-it when ready to create PR
```

---

## Error Handling

### If Tests Fail During GREEN Phase

1. **STOP** - Do not proceed to refactor
2. Analyze the failure
3. Fix the implementation
4. Re-run tests until green
5. Only then proceed

### If Tests Fail After Refactoring

1. **STOP** - Refactoring changed behavior
2. Revert the refactoring change
3. Try a smaller refactoring
4. Or skip that particular refactoring

### If Design is Insufficient

1. Note the gap in IMPLEMENTATION.md
2. Make reasonable decisions based on codebase patterns
3. Document the decision
4. Continue with implementation

---

## Commands to Execute

When invoked, you should:

1. **Verify prerequisites** - Check DESIGN.md and TASK.md exist
2. **Read task file** - Understand what needs to be implemented
3. **Read design file** - Understand how to implement
4. **Update status** - Mark task as "In Progress"
5. **For each task**:
   - 🔴 Write failing tests
   - 🟢 Implement to make tests pass
   - 🔵 Mini-refactor
   - ✅ Mark task complete in TASK.md
6. **Full refactoring pass** - Comprehensive code quality improvements
7. **Update documentation** - TASK.md status, IMPLEMENTATION.md
8. **Output summary** - What was done, next steps

## Key Principles

- 🎯 **Tests first, always** - Never write implementation before tests
- 🛑 **Stop on failure** - Don't proceed if tests fail
- 📝 **Track progress** - Update TASK.md as you go
- 🔄 **Refactor fearlessly** - Tests give you confidence to refactor
- 📊 **Performance matters** - Include performance tests, prevent N+1
- 📚 **Document decisions** - Capture deviations and reasoning
