# Handle Review Comments

Launch the **stack-comment-handler** agent to address PR review feedback with intelligent downstream propagation.

## Usage

```bash
# Run with detected PR from current branch
/handle-comments

# Specify PR number explicitly
/handle-comments pr: 1234

# With config file
/handle-comments pr: 1234 config: tmp/stack_20251112_143000.toml
```

## What This Agent Does

1. **Extracts review comments** from GitHub PR
2. **Guides you** through applying the requested changes
3. **Runs quality checks** (format, pyright, tests)
4. **Analyzes downstream impact** by scanning for import dependencies
5. **Propagates changes** through the stack sequentially
6. **Verifies all affected PRs** pass CI after updates

## When to Use

- PR has review comments that need addressing
- Changes might affect downstream PRs in the stack
- Need to ensure consistency across the entire PR chain
- Want automated propagation of fixes through dependencies

## Note

This agent works in both **stack mode** (with config file) and **single-PR mode** (without config).

For the full pipeline with quality review, use `/stack-pipeline`.

---

Additional instructions: $ARGUMENTS
