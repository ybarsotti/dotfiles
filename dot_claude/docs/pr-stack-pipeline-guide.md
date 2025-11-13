# PR Stack Pipeline - Complete Guide

**Last Updated**: 2025-01-13

## Overview

The PR Stack Pipeline is an automated system for splitting large pull requests into smaller, reviewable, dependency-ordered stacks. Instead of one massive 2000-line PR, you get 4-6 focused PRs of 200-400 lines each, making code review faster and safer.

### Key Benefits

- **Faster Reviews**: Smaller PRs are reviewed 10x faster
- **Dependency-Aware**: Automatically orders PRs by import relationships
- **Quality Validated**: All PRs pass CI checks before pushing
- **Intelligent Fixing**: Auto-fixes missing imports and type errors
- **Review Propagation**: Changes from review comments flow through the stack
- **Quality Assessment**: Post-creation review ensures optimal size and structure

## Quick Start

### Full Pipeline (Recommended for First-Time Users)

```bash
# On your large feature branch
/stack-pipeline
```

This runs the complete pipeline with human checkpoints at each stage. You'll approve the analysis, review the plan, and verify quality before PRs are created.

### Individual Commands (For Advanced Users)

```bash
# Stage 1: Analyze branch dependencies
/analyze-branch

# Stage 2: Create split plan
/plan-stack config: tmp/stack_<branch>_<timestamp>.toml

# Stage 3: Create branches and PRs with validation
/create-stack config: tmp/stack_<branch>_<timestamp>.toml

# Stage 3c: Review stack quality
/review-quality config: tmp/stack_<branch>_<timestamp>.toml

# Stage 4: Monitor remote CI
/validate-stack config: tmp/stack_<branch>_<timestamp>.toml

# Stage 5: Fix any CI failures
/fix-stack config: tmp/stack_<branch>_<timestamp>.toml

# Stage 6: Generate Slack announcement
/report-slack config: tmp/stack_<branch>_<timestamp>.toml

# After PRs are created and reviewed
/handle-comments pr: 1234
```

## Command Reference

### `/stack-pipeline` - Full Orchestrated Pipeline

**Purpose**: Run the complete PR splitting process with human checkpoints

**When to Use**:
- First time splitting a branch
- Want guided experience with approval at each stage
- Need full control and visibility

**Process**:
1. Analyzes branch with dependency detection
2. Creates split plan based on layers
3. Creates branches sequentially with CI validation
4. Reviews stack quality post-creation
5. Creates PRs and monitors remote CI
6. Fixes any failures automatically
7. Generates Slack announcement

**Human Checkpoints**:
- After analysis: "Does this look correct?"
- After planning: "Review the plan. Approve to continue?"
- After creation: "All branches validated. Continue?"
- After quality review: "Quality acceptable? Any concerns?"
- After CI monitoring: "Remote CI matches local?"
- After fixing: "Review fixes and approve push?"

**Example**:
```bash
# On branch: feature/user-authentication
git checkout feature/user-authentication
/stack-pipeline

# Follow prompts:
# ✅ Analysis: 47 files changed, 4 layers detected
# Type 'yes' to continue...
# ✅ Plan: 4 PRs created (Foundation → Repositories → Services → API)
# Type 'yes' to continue...
# ... etc
```

---

### `/analyze-branch` - Stage 1: Branch Analysis

**Purpose**: Analyze what changed and identify dependencies

**When to Use**:
- Want to understand your branch structure first
- Need to see file groupings before planning
- Debugging dependency detection

**Output**: Creates `tmp/stack_<branch>_<timestamp>.toml` with:
- List of all changed files
- Detected layers (Foundation, Repositories, Services, API)
- Import relationships between files
- Concerns/recommendations

**Example**:
```bash
/analyze-branch

# Output:
# 📊 Analysis Complete!
# - 47 files changed
# - 4 layers detected: Foundation (12 files), Repositories (15 files), Services (18 files), API (2 files)
# - Config saved: tmp/stack_feature-auth_20251113_140522.toml
```

**Next Steps**: Review the analysis, then run `/plan-stack` with the generated config file.

---

### `/plan-stack` - Stage 2: Create Split Plan

**Purpose**: Generate the branch breakdown strategy

**When to Use**:
- After analysis completes
- Want to modify the plan manually before creation
- Re-planning after dynamic changes

**Requires**: Config file from `/analyze-branch`

**Output**: Updates TOML with:
- Branch names and base branches
- Files assigned to each branch
- Commit messages
- Dependencies between PRs

**Example**:
```bash
/plan-stack config: tmp/stack_feature-auth_20251113_140522.toml

# Output:
# 📋 Plan Created!
# Branch 1/4: feature/01-auth-foundation (12 files)
# Branch 2/4: feature/02-auth-repositories (15 files) → depends on 01
# Branch 3/4: feature/03-auth-services (18 files) → depends on 02
# Branch 4/4: feature/04-auth-api (2 files) → depends on 03

# You can manually edit the TOML before continuing
# Type 'yes' to proceed or 'edit' to pause
```

**Tip**: If you type 'edit', you can manually adjust the plan (move files between branches, rename branches, etc.) before continuing.

---

### `/create-stack` - Stage 3: Create Branches with Validation

**Purpose**: Create the branches and PRs with local CI validation

**When to Use**:
- After planning is approved
- Re-running creation after manual fixes

**Requires**: Config file with plan

**Process**:
1. Creates branches **one at a time** (not batch)
2. For each branch:
   - Cherry-picks commits
   - Runs format, pyright, and tests
   - If pass → checks size → pushes to remote
   - If fail → attempts intelligent auto-fix
   - If still fail → stops for human intervention
3. Creates PRs with descriptions
4. Updates PR descriptions with actual PR numbers

**Key Features**:
- **Sequential**: Each branch validated before next starts
- **Intelligent Fixing**: Searches source branch and existing branches for fixes
- **Size Monitoring**: Checks if fixes make branches too small
- **Zero Broken Branches**: Never pushes failing code

**Example**:
```bash
/create-stack config: tmp/stack_feature-auth_20251113_140522.toml

# Output:
# 🏗️  Creating branch 1/4: feature/01-auth-foundation
# ✅ Format passed
# ✅ Pyright passed
# ✅ Tests passed (12/12)
# ✅ Size: 234 lines (ideal)
# ✅ Pushed to remote
#
# 🏗️  Creating branch 2/4: feature/02-auth-repositories
# ✅ Format passed
# ❌ Pyright failed: Missing import 'UserRow'
# 🔧 Attempting auto-fix...
# ✅ Found in source branch, applying fix
# ✅ Pyright passed
# ✅ Tests passed (15/15)
# ✅ Size: 287 lines (ideal)
# ✅ Pushed to remote
#
# ... continues for all branches
```

**Note**: If Stage 3b (Dynamic Replanning) triggers, you'll be prompted to review a revised plan if branches became too small.

---

### `/review-quality` - Stage 3c: Stack Quality Review

**Purpose**: Assess the quality of the created stack

**When to Use**:
- After `/create-stack` completes
- Before sending stack for review
- Validating stack structure

**Requires**: Config file with created branches

**What It Checks**:
1. **Size Balance**:
   - Too small: < 40 lines
   - Ideal: 40-300 lines
   - Large: 300-500 lines
   - Too large: > 500 lines

2. **Logical Grouping**:
   - Tests with implementation
   - No orphaned test files

3. **PR Descriptions**:
   - Meaningful descriptions
   - No placeholder text
   - Clear stack context

4. **Dependency Correctness**:
   - Imports only from adjacent upstream PRs
   - No dependency violations

**Example**:
```bash
/review-quality config: tmp/stack_feature-auth_20251113_140522.toml

# Output:
# 📊 Quality Assessment Complete!
#
# Overall Rating: ✅ GOOD
#
# Per-PR Assessment:
# PR #1234: ✅ IDEAL (234 lines) - Well-sized, tests included
# PR #1235: 🟡 LARGE (387 lines) - Consider splitting services
# PR #1236: ✅ IDEAL (156 lines) - Perfect size
# PR #1237: ✅ IDEAL (89 lines) - API endpoints focused
#
# 💡 Recommendations:
# - Consider splitting PR #1235 (services) into business logic + orchestration
# - All dependencies are correct
# - Descriptions are clear and complete
```

**Actions**:
- `yes`: Quality acceptable, continue
- `fix`: Address issues manually
- `skip`: Proceed despite concerns
- `abort`: Stop pipeline

---

### `/validate-stack` - Stage 4: Monitor Remote CI

**Purpose**: Verify remote CI matches local validation

**When to Use**:
- After PRs are created
- Checking if remote CI passes
- Identifying remote-only failures

**Requires**: Config file with PR numbers

**Example**:
```bash
/validate-stack config: tmp/stack_feature-auth_20251113_140522.toml

# Output:
# 📊 CI Status Check
# PR #1234: ✅ All checks passed
# PR #1235: ✅ All checks passed
# PR #1236: ✅ All checks passed
# PR #1237: ✅ All checks passed
#
# ✅ All PRs passing! Remote CI matches local validation.
```

---

### `/fix-stack` - Stage 5: Fix CI Failures

**Purpose**: Fix CI failures using intelligent downstream scanning

**When to Use**:
- Remote CI shows failures
- Need to relocate files between PRs
- Propagate fixes through the stack

**Requires**: Config file with CI failure info

**Process**:
1. Parse CI error logs
2. **Search downstream PRs** for relevant fixes
3. If found → cherry-pick fix to failing PR
4. If not found → generate fix manually
5. Propagate fix to all downstream PRs
6. Verify locally and push updates

**Example**:
```bash
/fix-stack config: tmp/stack_feature-auth_20251113_140522.toml

# Output:
# 🔧 Analyzing failures...
#
# PR #1235: Import error - 'calculate_permissions' not found
# 🔍 Scanning downstream PRs...
# ✅ Found in PR #1236 (services)
# 🔄 Cherry-picking fix to PR #1235
# 🔄 Propagating to PR #1236, #1237
# ✅ All PRs fixed and validated
#
# Ready to push? Type 'yes'
```

---

### `/handle-comments` - Address Review Feedback

**Purpose**: Address PR review comments with downstream propagation

**When to Use**:
- PR has review comments from reviewer
- Changes might affect other PRs in the stack
- Need to ensure consistency across the chain

**Requires**: PR number (or auto-detects from current branch)

**Process**:
1. Extracts review comments from GitHub
2. Guides you through applying changes
3. Runs quality checks (format, pyright, tests)
4. Commits changes with meaningful message
5. Analyzes downstream impact by scanning imports
6. Propagates changes to affected branches
7. Verifies all affected PRs pass CI

**Example**:
```bash
# On the PR branch that has review comments
git checkout feature/02-auth-repositories

/handle-comments

# OR specify PR explicitly
/handle-comments pr: 1235

# Output:
# 📝 Handling review comments for PR #1235
#
# 🔍 Found 3 review comments:
# - auth_repo.py:45 - "Add type hints to calculate_permissions"
# - auth_repo.py:67 - "Extract validation logic to separate method"
# - test_auth_repo.py:120 - "Add test for edge case with empty permissions"
#
# 👤 Make the requested changes in your editor
# Type 'done' when ready: done
#
# 🧪 Running quality checks...
# ✅ Format passed
# ✅ Pyright passed
# ✅ Tests passed
#
# 💾 Committing changes...
# ✅ Committed: abc1234
#
# 🔍 Analyzing downstream impact...
# ⚠️  PR #1236 imports from auth_repo
# ⚠️  PR #1237 imports from auth_repo
#
# 🔄 Propagating changes...
# ✅ Merged into feature/03-auth-services
# ✅ Merged into feature/04-auth-api
# ✅ All downstream PRs updated and passing
#
# 📝 Added summary comment to PR #1235
```

**Key Features**:
- **Import-based detection**: Scans for actual code dependencies, not just file names
- **Sequential propagation**: Merges changes through the stack in order
- **Quality validation**: Re-runs checks on each updated branch
- **Automatic PR comment**: Notifies reviewers about propagation

**Works in Two Modes**:
- **Stack Mode**: With config file, propagates to all downstream PRs
- **Single-PR Mode**: Without config, just fixes the one PR

---

### `/report-slack` - Stage 6: Generate Announcement

**Purpose**: Create Slack message announcing the stack

**When to Use**:
- After all PRs are created and passing
- Ready to announce for review

**Requires**: Config file with PR URLs

**Example**:
```bash
/report-slack config: tmp/stack_feature-auth_20251113_140522.toml

# Output:
# 📢 New PR Stack: User Authentication
#
# I've split the user authentication feature into 4 reviewable PRs:
#
# 1. PR #1234: Foundation - auth models and utilities
# 2. PR #1235: Repositories - database access layer
# 3. PR #1236: Services - business logic and orchestration
# 4. PR #1237: API - REST endpoints
#
# Review order: #1234 → #1235 → #1236 → #1237
#
# Each PR targets the previous one. Please review in order and merge sequentially.
#
# 👤 Copy the above message to Slack!
```

---

## Common Workflows

### Workflow 1: First-Time Stack Creation (Recommended)

```bash
# 1. Ensure you're on your feature branch
git checkout feature/user-authentication

# 2. Run full pipeline
/stack-pipeline

# 3. Follow prompts and approve at each checkpoint:
#    - Analysis
#    - Plan
#    - Creation
#    - Quality Review
#    - CI Monitoring
#    - (Fix if needed)
#    - Slack Report

# 4. Copy Slack message and announce
```

**Timeline**: 10-20 minutes with checkpoints

---

### Workflow 2: Quick Creation (Advanced Users)

```bash
# 1. Analyze
/analyze-branch

# 2. Plan
/plan-stack config: tmp/stack_*.toml

# 3. Create
/create-stack config: tmp/stack_*.toml

# 4. Review Quality
/review-quality config: tmp/stack_*.toml

# 5. Report
/report-slack config: tmp/stack_*.toml
```

**Timeline**: 5-10 minutes, no checkpoints

---

### Workflow 3: Manual Planning with Customization

```bash
# 1. Analyze
/analyze-branch
# Config saved: tmp/stack_feature-auth_20251113_140522.toml

# 2. Plan but pause for editing
/plan-stack config: tmp/stack_feature-auth_20251113_140522.toml
# Type 'edit' at the checkpoint

# 3. Manually edit TOML file
# - Move files between branches
# - Rename branches
# - Adjust descriptions

# 4. Create with custom plan
/create-stack config: tmp/stack_feature-auth_20251113_140522.toml

# 5. Quality check
/review-quality config: tmp/stack_feature-auth_20251113_140522.toml

# 6. Generate report
/report-slack config: tmp/stack_feature-auth_20251113_140522.toml
```

---

### Workflow 4: Handling Review Comments

```bash
# After PRs are reviewed and have feedback:

# 1. Checkout the PR branch with comments
git checkout feature/02-auth-repositories

# 2. Address comments with auto-propagation
/handle-comments

# OR specify PR number
/handle-comments pr: 1235

# 3. Follow guided process:
#    - Review extracted comments
#    - Make changes
#    - Verify quality checks
#    - Commit
#    - Watch auto-propagation

# 4. All downstream PRs are automatically updated!
```

---

### Workflow 5: Fixing CI Failures Post-Creation

```bash
# If remote CI shows failures:

# 1. Identify failures
/validate-stack config: tmp/stack_*.toml

# 2. Auto-fix with downstream scanning
/fix-stack config: tmp/stack_*.toml

# 3. Verify fixes and push
# Agent will propagate fixes through the stack
```

---

## Best Practices

### Before Starting

1. **Ensure clean state**: Commit or stash uncommitted changes
2. **Update from main**: `git fetch origin main`
3. **Run tests locally**: Make sure your branch is working
4. **Check branch naming**: Include ticket number (e.g., `feature/AUTH-123-login`)

### During Pipeline

1. **Review analysis carefully**: Verify all changed files are detected
2. **Don't skip quality checks**: They catch issues early
3. **Read PR descriptions**: Make sure they're clear and accurate
4. **Test locally first**: Don't rely only on CI

### After Creation

1. **Review each PR**: Open them in GitHub and scan for issues
2. **Check PR descriptions**: Verify ticket references and stack context
3. **Announce in Slack**: Use generated message to notify team
4. **Monitor CI closely**: First few minutes are critical

### Handling Review Comments

1. **Use `/handle-comments`**: Don't manually propagate changes
2. **Review propagation plan**: Verify which PRs will be affected
3. **Test after propagation**: Run full test suite on affected branches
4. **Communicate changes**: Update PR comments about what changed

---

## Troubleshooting

### Issue: "Analysis failed: No changed files detected"

**Cause**: You're on a branch with no commits compared to base

**Solution**:
```bash
# Verify you have commits
git log main..HEAD

# If empty, make sure you're on the right branch
git branch --show-current

# Check if you've committed your changes
git status
```

---

### Issue: "Planning failed: File count mismatch"

**Cause**: Plan doesn't account for all files in analysis

**Solution**:
```bash
# Re-run analysis
/analyze-branch

# Then re-run planning with fresh config
/plan-stack config: tmp/stack_<newest-timestamp>.toml
```

---

### Issue: "Branch creation stopped: CI validation failed"

**Cause**: A branch failed format/pyright/tests and auto-fix couldn't resolve it

**Solution**:
```bash
# Check the specific error
cat tmp/ci_<branch-name>_*.log

# Fix manually on that branch
git checkout <failing-branch>
# Make fixes
git commit -m "fix: resolve CI failure"

# Resume creation (agent will continue from next branch)
/create-stack config: tmp/stack_*.toml
```

---

### Issue: "PR descriptions have placeholder text"

**Cause**: Agent didn't update descriptions with actual PR numbers

**Solution**:
```bash
# Manually trigger PR description update via GitHub CLI
gh pr edit <PR-NUMBER> --body "$(cat updated_description.md)"

# Or re-run creation (will update existing PRs)
/create-stack config: tmp/stack_*.toml
```

---

### Issue: "Downstream propagation failed: merge conflict"

**Cause**: Changes from `/handle-comments` conflict with downstream code

**Solution**:
```bash
# Manually resolve conflicts
git checkout <downstream-branch>
git merge <upstream-branch>
# Resolve conflicts in editor
git add <resolved-files>
git commit -m "chore: merge review feedback from upstream"
git push origin <downstream-branch>

# Continue with next branch
```

---

### Issue: "Quality review shows PRs too small"

**Cause**: Auto-fixes removed enough code to make branches < 40 lines

**Solution**:
```bash
# Stage 3b should have triggered automatically
# If it didn't, manually consolidate:

# Option 1: Use /fix-stack to merge small PRs
/fix-stack config: tmp/stack_*.toml

# Option 2: Manually replan
/plan-stack config: tmp/stack_*.toml
# Edit TOML to merge small branches
/create-stack config: tmp/stack_*.toml
```

---

### Issue: "Can't find config file"

**Cause**: Lost track of which TOML file to use

**Solution**:
```bash
# List recent stack configs
ls -lt tmp/stack_*.toml | head -5

# Use the most recent one that matches your branch
/create-stack config: tmp/stack_feature-auth_20251113_140522.toml
```

---

## FAQ

### Q: How long does the full pipeline take?

**A**: Typically 10-20 minutes for a 4-PR stack:
- Analysis: 1-2 min
- Planning: 1 min
- Creation: 5-10 min (sequential validation)
- Quality Review: 1-2 min
- CI Monitoring: 2-3 min
- Reporting: 30 sec

### Q: Can I run stages out of order?

**A**: No, stages must run sequentially. Each stage depends on output from previous stages.

### Q: What if I need to add more commits after creation?

**A**:
```bash
# Make changes on the appropriate branch
git checkout feature/02-auth-repositories
# Make changes
git add <files>
git commit -m "feat: additional changes"
git push origin feature/02-auth-repositories

# If changes affect downstream PRs, use /handle-comments
/handle-comments pr: <PR-NUMBER>
```

### Q: Can I manually edit the TOML config?

**A**: Yes! At the planning stage, type 'edit' at the checkpoint. You can:
- Move files between branches
- Rename branches
- Adjust commit messages
- Change base branches

### Q: What if I want to skip quality review?

**A**: At the quality review checkpoint, type 'skip'. But it's not recommended - quality issues often cause problems later.

### Q: How do I resume a stopped pipeline?

**A**: Run the specific stage command with the config file:
```bash
# If stopped at creation
/create-stack config: tmp/stack_*.toml

# If stopped at fixing
/fix-stack config: tmp/stack_*.toml
```

### Q: Can I use this on a branch that's already pushed?

**A**: Yes, but ensure it's not already a PR. The pipeline creates new PRs.

### Q: What's the maximum number of PRs it can create?

**A**: Technically unlimited, but 4-6 is optimal for reviewability. If you get more, consider if your feature is too large.

### Q: Does it work with Linear/Jira issues?

**A**: Yes! If your branch name contains a ticket reference (e.g., `feature/AUTH-123-login`), it's automatically extracted and included in PR descriptions.

---

## Advanced Tips

### Tip 1: Pre-Planning with Analysis Only

```bash
# Just analyze to see structure
/analyze-branch

# Review the TOML file
cat tmp/stack_*.toml

# Decide if you want to proceed or restructure your branch first
```

### Tip 2: Custom Branch Naming

Edit the TOML after planning:
```toml
[[branches]]
branch = "feature/auth-01-foundation"  # Change this
description = "Foundation layer"
```

### Tip 3: Testing Before Full Pipeline

```bash
# Run analysis and planning only
/analyze-branch
/plan-stack config: tmp/stack_*.toml

# Review plan thoroughly
# If satisfied, then run creation
/create-stack config: tmp/stack_*.toml
```

### Tip 4: Parallel Review Strategy

After stack is created:
1. Announce in Slack
2. Assign different reviewers to different PRs
3. They can review in parallel (read-only)
4. Merge sequentially after all approved

### Tip 5: Emergency Fixes

If you need to fix something urgently in the middle of the stack:
```bash
# Make fix on the PR branch
git checkout feature/02-auth-repositories
# Make changes
git commit -m "fix: urgent security issue"

# Propagate through the stack
/handle-comments pr: <PR-NUMBER>
```

---

## Integration with Team Workflow

### Slack Announcement Template

Use the `/report-slack` output, or customize:

```
🚀 New PR Stack: [Feature Name]

I've split [feature description] into [N] reviewable PRs:

1️⃣ PR #1234: [Foundation] - [description]
2️⃣ PR #1235: [Repositories] - [description]
3️⃣ PR #1236: [Services] - [description]
4️⃣ PR #1237: [API] - [description]

📋 Review order: #1234 → #1235 → #1236 → #1237

Each PR targets the previous one. Please review in order and merge sequentially using "Squash and merge".

Related Issue: AUTH-123

cc: @reviewer1 @reviewer2
```

### Review Process

1. **Sequential Review**: Reviewers should review in order (foundation first)
2. **Parallel Reading**: Multiple reviewers can read simultaneously
3. **Sequential Approval**: PRs approved in dependency order
4. **Sequential Merge**: Merge one at a time, foundation first
5. **Use "Squash and Merge"**: Keeps git history clean

### Post-Merge Cleanup

After the last PR merges:
```bash
# Delete the feature branches (GitHub does this automatically)
# Clean up local branches
git branch -D feature/01-auth-foundation
git branch -D feature/02-auth-repositories
git branch -D feature/03-auth-services
git branch -D feature/04-auth-api

# Delete the original large branch
git branch -D feature/user-authentication
```

---

## Summary

The PR Stack Pipeline transforms large, hard-to-review pull requests into small, focused, dependency-ordered stacks that are:

✅ **Faster to Review** (200-400 lines vs 2000+ lines)
✅ **Safer to Merge** (validated at every step)
✅ **Easier to Understand** (clear layer separation)
✅ **Better Quality** (automatic quality assessment)
✅ **More Maintainable** (changes propagate correctly)

Use `/stack-pipeline` for the full guided experience, or run individual stages for more control.

For questions or issues, check the Troubleshooting section or ask in #engineering.
