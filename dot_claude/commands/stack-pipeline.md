# Run Full PR Stack Pipeline

Launch the **pr-stack-supervisor** agent to execute the complete PR splitting pipeline with human-in-the-loop checkpoints.

## What It Does

Orchestrates 6 specialized agents through these stages:

1. 🔍 **Analysis** - Understand branch changes and dependencies
2. 📋 **Planning** - Create split strategy (foundation first!)
3. 🏗️ **Creation** - Execute branch creation
4. ✅ **Validation** - Check CI status
5. 🔧 **Fixing** - Fix any CI failures (if needed)
6. 📢 **Reporting** - Generate Slack message

**Human checkpoints after EVERY stage** for review and approval.

## Usage

```bash
# Run on current branch
/stack-pipeline

# Specify branch
/stack-pipeline branch: feature/my-big-pr

# Custom base branch
/stack-pipeline base: develop
```

## What to Expect

Each stage pauses for your review and approval before proceeding.

---

Additional instructions: $ARGUMENTS
