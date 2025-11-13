# Review Stack Quality

Launch the **stack-quality-reviewer** agent to assess the quality of a created PR stack.

## Usage

```bash
# Run with defaults (finds most recent stack config)
/review-quality

# Specify config file
/review-quality config: tmp/stack_20251112_143000.toml
```

## What This Agent Does

1. **Analyzes size balance** across all PRs
   - Identifies PRs that are too small (< 40 lines)
   - Identifies PRs that are too large (> 500 lines)
   - Highlights ideal-sized PRs (40-300 lines)

2. **Checks logical grouping**
   - Verifies test files are with implementation
   - Identifies orphaned test files

3. **Validates PR descriptions**
   - Ensures meaningful descriptions
   - Checks for placeholder text
   - Verifies stack context is clear

4. **Verifies dependency correctness**
   - Checks that imports only come from adjacent upstream PRs
   - Identifies dependency violations

5. **Generates comprehensive report** with:
   - Per-PR quality assessment
   - Overall stack quality score
   - Actionable recommendations
   - Issues that need addressing

## When to Use

- After creating a PR stack (via `/create-stack` or `/stack-pipeline`)
- Before sending stack for review
- To validate stack structure and reviewability
- To identify potential improvements before merge

## Note

This runs **Stage 3c only**. For full pipeline with quality review included, use `/stack-pipeline`.

The quality review is automatically integrated into the full pipeline after branch creation.

---

Additional instructions: $ARGUMENTS
