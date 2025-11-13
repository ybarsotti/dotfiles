
# Split Large PR into Reviewable Stack

Launch the **pr-stack-splitter** agent to analyze your feature branch and split it into a stack of reviewable, dependent PRs.

## What It Does

The agent will:

1. ✅ **Verify Ruby environment** (installs if needed)
2. 🔍 **Analyze all changed files** in your branch compared to main
3. 🧩 **Group files by logical concern** (models → repositories → services → API)
4. 📝 **Generate TOML configuration** for the stackify script
5. 👀 **Present the plan** for your review and approval
6. 🚀 **Create the branch stack** when you approve
7. 📋 **Report results** with next steps for pushing and creating PRs

## Requirements

- **Ruby** installed (agent checks and provides install instructions)
- **TOML gem** (`gem install toml` - agent checks and provides install instructions)
- **Git repository** with a feature branch that has diverged from main

## Usage Examples

```bash
# Split current branch into a stack
/stackify

# Split specific branch
/stackify branch: yourname/feature/big-refactor

# Use custom base branch instead of main
/stackify base: develop

# Provide grouping hints to the agent
/stackify hint: separate database changes from API changes

# Custom branch prefix
/stackify prefix: yourname/refactor
```

## What Gets Created

The agent creates a stack of branches following this pattern:

```
main (or base branch)
  └─▶ feature/01-database-models     (models, migrations, model tests)
       └─▶ feature/02-repositories    (repos, repo tests)
            └─▶ feature/03-business-logic    (services, service tests)
                 └─▶ feature/04-api-endpoints    (API, API tests)
```

Each branch:
- Builds on the previous branch (forms a dependency chain)
- Contains a logical, reviewable unit of work
- Includes relevant tests alongside implementation
- Has a descriptive name and commit message

## Safety Features

- 🛡️ **Automatic backup branch** created before any changes
- 🔍 **Validates every file is accounted for** exactly once
- ⏮️ **Automatic rollback** if any errors occur
- 👀 **User review and approval** before creating branches
- 📝 **Configuration saved** for reference

## Next Steps After Stack Creation

1. **Push branches** to remote:
   ```bash
   git push -u origin feature/01-database-models
   git push -u origin feature/02-repositories
   # ... etc
   ```

2. **Create PRs in dependency order**:
   - PR #1: `01-database-models` → `main`
   - PR #2: `02-repositories` → `01-database-models`
   - PR #3: `03-business-logic` → `02-repositories`
   - PR #4: `04-api-endpoints` → `03-business-logic`

3. **Review and merge sequentially** (PR #1 first, then #2, etc.)

## Troubleshooting

**Ruby not installed?**
```bash
# macOS
brew install ruby

# Linux (Ubuntu/Debian)
sudo apt-get install ruby-full
```

**TOML gem not installed?**
```bash
gem install toml

# If permission errors
gem install --user-install toml
```

**Want to customize the split?**
The agent will show you the proposed TOML configuration and allow you to modify it before execution.

**Something went wrong?**
Stackify automatically rolls back changes and preserves your original branch. Your backup branch is named `[original-branch]-BACKUP`.

---

Additional instructions: $ARGUMENTS
