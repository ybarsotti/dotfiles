# Simplify - Quick Code Cleanup

Light refactoring pass focused on making code simpler and more readable. Use this after `/do_it` or for quick cleanup of small changes.

**For comprehensive refactoring** (code smells, architecture, DRY), use `/refactor` instead.

## What This Does

1. **Remove dead code** - Unused variables, unreachable code, commented-out blocks
2. **Simplify conditionals** - Convert to guard clauses, early returns
3. **Reduce nesting** - Flatten deeply nested code (max 3 levels)
4. **Extract obvious duplicates** - Only when pattern repeats 3+ times
5. **Improve naming** - Rename unclear variables/functions

## What This Does NOT Do

- Architecture changes
- Performance optimization
- Full DRY analysis
- Code smell detection
- Complexity metrics

## Process

1. **Identify target** - Ask user for file/function or use recent changes
2. **Quick scan** - Find obvious simplification opportunities
3. **Apply changes** - One at a time, verify tests pass
4. **Report** - List what was simplified

## Simplification Patterns

### Guard Clauses
```python
# Before
def process(data):
    if data is not None:
        if data.valid:
            return do_work(data)
    return None

# After
def process(data):
    if data is None:
        return None
    if not data.valid:
        return None
    return do_work(data)
```

### Early Returns
```javascript
// Before
function calculate(x) {
    let result;
    if (x > 0) {
        result = x * 2;
    } else {
        result = 0;
    }
    return result;
}

// After
function calculate(x) {
    if (x <= 0) return 0;
    return x * 2;
}
```

### Flatten Nesting
```python
# Before
for item in items:
    if item.active:
        if item.valid:
            process(item)

# After
for item in items:
    if not item.active:
        continue
    if not item.valid:
        continue
    process(item)
```

## Commands to Execute

1. **Ask for scope** - File, function, or "recent changes"
2. **Read the code** - Understand current structure
3. **Identify 3-5 simplifications** - Don't over-do it
4. **Apply each change** - Run tests after each
5. **Output summary** - What was simplified

## Output Format

```
✅ /simplify Complete

Simplified: path/to/file.ext

Changes:
- Line 45: Converted nested if to guard clause
- Line 67: Removed unused variable `temp`
- Line 89: Flattened 4-level nesting to 2 levels

Tests: ✅ Passing
```

## When to Use

| Scenario | Use `/simplify` | Use `/refactor` |
|----------|-----------------|-----------------|
| Quick cleanup after implementation | ✅ | |
| Small PR touchup | ✅ | |
| Code smell investigation | | ✅ |
| Architecture concerns | | ✅ |
| DRY violations across files | | ✅ |
| Performance issues | | ✅ |
