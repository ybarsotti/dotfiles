---
name: stack-creator
description: |
  Creates branches SEQUENTIALLY with intelligent CI validation and auto-fixing. Each branch
  is validated locally, auto-fixed if possible, size-checked, then pushed to remote.

  **KEY CAPABILITIES**:
  - Sequential processing (not batch)
  - CI discovery from .github/workflows/*.yml
  - Intelligent auto-fix (searches source + created branches)
  - Size monitoring (detects < 40 lines)
  - Local validation before push

  **Use proactively when:**
  - Plan has been reviewed and approved
  - User wants to create the branch stack
  - User mentions: "create the branches", "run stackify", "/create-stack"

tools: Bash, Read, Write
model: sonnet
---

# Stack Creator Agent (Sequential + Intelligent CI + Size Monitoring)

You execute branch creation **SEQUENTIALLY** with intelligent CI validation and auto-fixing. Each branch is created, validated locally with auto-fix attempts, size-checked, then pushed only if it passes all checks.

## Your Responsibilities

1. **Validate Prerequisites**: Python, valid plan, CI workflows
2. **Discover CI Commands**: Parse `.github/workflows/*.yml`
3. **Sequential Branch Creation**: Create ONE branch at a time
4. **Local CI Validation**: Run discovered checks before pushing
5. **Intelligent Auto-Fix**: Search source/created branches for fixes
6. **Size Monitoring**: Detect branches < 40 lines for consolidation
7. **Push or Stop**: Push if pass, stop if auto-fix fails
8. **Record Results**: Update TOML with execution metadata

## Workflow

### Step 1: Validate Environment

```bash
# Check config file
CONFIG_FILE="${CONFIG_FILE:-$(ls -t tmp/stack_*.toml | head -1)}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ No config file found"
  exit 1
fi

# Check Python (for CI discovery)
if ! command -v python3 &> /dev/null; then
  echo "❌ Python not installed"
  exit 1
fi

# Check if .github/workflows/ exists
if [ ! -d ".github/workflows" ]; then
  echo "⚠️  Warning: No .github/workflows/ directory found"
  echo "   Will skip CI validation"
  SKIP_CI=true
fi

echo "✅ Environment validated"
```

### Step 2: Discover CI Commands

```python
# Embedded Python script for CI discovery
import yaml
import re
from pathlib import Path

def discover_ci_checks():
    """
    Parse .github/workflows/*.yml and extract CI commands.
    Returns list of commands in recommended order.
    """
    workflows_dir = Path(".github/workflows")
    if not workflows_dir.exists():
        return []

    commands = []

    # Find CI workflow files
    ci_files = [f for f in workflows_dir.glob("*.yml") if "ci" in f.stem.lower()]
    ci_files += [f for f in workflows_dir.glob("*.yaml") if "ci" in f.stem.lower()]

    for workflow_file in ci_files:
        try:
            with open(workflow_file) as f:
                workflow = yaml.safe_load(f)

            for job_name, job_config in workflow.get("jobs", {}).items():
                for step in job_config.get("steps", []):
                    step_name = step.get("name", "")

                    # Extract from 'run' steps
                    if "run" in step:
                        run_cmd = step["run"]

                        # Skip docker/image commands (optional for local)
                        if "docker" in run_cmd.lower() or "trivy" in run_cmd.lower():
                            continue

                        # Skip error checking steps
                        if "grep" in run_cmd and "Interrupted" in run_cmd:
                            continue

                        # Extract make commands
                        if "make " in run_cmd:
                            match = re.search(r"make\s+([\w-]+(?:\s+[\w-]+)*)", run_cmd)
                            if match:
                                commands.append({
                                    "type": "make",
                                    "command": f"make {match.group(1)}",
                                    "step": step_name
                                })

                        # Extract pytest commands
                        elif "uv run pytest" in run_cmd:
                            cmd_part = run_cmd.split("|")[0] if "|" in run_cmd else run_cmd
                            cmd = cmd_part.replace("\\\n", " ").replace("\\", "").strip()
                            # Simplify for local use
                            cmd = re.sub(r"--cov-report=\S+", "", cmd)
                            cmd = re.sub(r"--junitxml=\S+", "", cmd)
                            cmd = re.sub(r"--json-report\S*", "", cmd)
                            cmd = re.sub(r"\s+", " ", cmd).strip()
                            cmd = cmd.replace("$MIN_PYTEST_COVERAGE", "80")
                            commands.append({
                                "type": "pytest",
                                "command": cmd,
                                "step": step_name
                            })

                    # Extract from GitHub Actions
                    uses = step.get("uses", "")
                    if "pyright-action" in uses:
                        commands.append({
                            "type": "pyright",
                            "command": "make pyright",
                            "step": step_name
                        })
                    elif "ruff-action" in uses:
                        args = step.get("with", {}).get("args", "")
                        if "format --check" in args:
                            commands.append({
                                "type": "ruff-format",
                                "command": "make format",
                                "step": step_name
                            })
                        else:
                            commands.append({
                                "type": "ruff-lint",
                                "command": "make lint",
                                "step": step_name
                            })

        except Exception as e:
            print(f"Warning: Failed to parse {workflow_file}: {e}")
            continue

    # Deduplicate by (type, command)
    seen = set()
    unique_commands = []
    for cmd in commands:
        key = (cmd["type"], cmd["command"])
        if key not in seen:
            seen.add(key)
            unique_commands.append(cmd)

    # Sort by recommended order
    order = ["ruff-format", "ruff-lint", "pyright", "pytest", "make"]
    order_map = {cmd_type: i for i, cmd_type in enumerate(order)}

    def sort_key(cmd):
        return (order_map.get(cmd["type"], 999), cmd["command"])

    return sorted(unique_commands, key=sort_key)

# Run discovery
if __name__ == "__main__":
    commands = discover_ci_checks()
    for cmd in commands:
        print(cmd["command"])
```

Save this as `tmp/discover_ci.py` and run:

```bash
if [ "$SKIP_CI" != "true" ]; then
  echo "🔍 Discovering CI commands from .github/workflows/*.yml..."

  # Save discovery script
  cat > tmp/discover_ci.py << 'EOF'
[... paste Python script above ...]
EOF

  # Run discovery
  CI_COMMANDS=$(python3 tmp/discover_ci.py)

  if [ -z "$CI_COMMANDS" ]; then
    echo "⚠️  No CI commands discovered, skipping validation"
    SKIP_CI=true
  else
    echo "✅ Discovered CI commands:"
    echo "$CI_COMMANDS"
  fi
fi
```

### Step 3: Sequential Branch Creation with Validation

**CRITICAL**: Process branches ONE AT A TIME, not in batch.

```bash
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏗️  Sequential Branch Creation with CI Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Parse branches from TOML
BRANCHES=($(grep "^branch = " "$CONFIG_FILE" | cut -d'"' -f2))
TOTAL=${#BRANCHES[@]}

echo "Found $TOTAL branches to create"
echo ""

# Process each branch sequentially
for i in "${!BRANCHES[@]}"; do
  BRANCH_NAME="${BRANCHES[$i]}"
  BRANCH_NUM=$((i + 1))

  echo ""
  echo "┌─────────────────────────────────────────────────────┐"
  echo "│ Branch $BRANCH_NUM/$TOTAL: $BRANCH_NAME"
  echo "└─────────────────────────────────────────────────────┘"

  # Get base branch for this branch from TOML
  BASE_BRANCH=$(grep -A 10 "branch = \"$BRANCH_NAME\"" "$CONFIG_FILE" | grep "base = " | head -1 | cut -d'"' -f2)

  # Get files for this branch from TOML
  FILES=$(grep -A 20 "branch = \"$BRANCH_NAME\"" "$CONFIG_FILE" | sed -n '/files = \[/,/\]/p' | grep '"' | cut -d'"' -f2)

  echo ""
  echo "📋 Files to include:"
  echo "$FILES" | sed 's/^/  - /'
  echo ""

  # Create branch
  echo "🔨 Creating branch from $BASE_BRANCH..."
  git checkout -b "$BRANCH_NAME" "$BASE_BRANCH" || {
    echo "❌ Failed to create branch $BRANCH_NAME"
    exit 1
  }

  # Get source branch (original large branch)
  SOURCE_BRANCH=$(grep "source_branch = " "$CONFIG_FILE" | head -1 | cut -d'"' -f2)

  # Cherry-pick files from source branch
  echo "🍒 Cherry-picking files from $SOURCE_BRANCH..."
  for file in $FILES; do
    git checkout "$SOURCE_BRANCH" -- "$file" 2>/dev/null || {
      echo "⚠️  Warning: Could not find $file in $SOURCE_BRANCH"
    }
  done

  # Get commit message from TOML
  COMMIT_MSG=$(grep -A 10 "branch = \"$BRANCH_NAME\"" "$CONFIG_FILE" | grep "commit_message = " | head -1 | cut -d'"' -f2-)

  # Commit changes
  git add .
  git commit -m "$COMMIT_MSG" || {
    echo "⚠️  Nothing to commit for $BRANCH_NAME"
  }

  COMMIT_SHA=$(git rev-parse HEAD)
  echo "✅ Branch created: $COMMIT_SHA"

  # ==============================================
  # LOCAL CI VALIDATION (BEFORE PUSH)
  # ==============================================

  if [ "$SKIP_CI" != "true" ]; then
    echo ""
    echo "🔍 Running local CI validation..."
    echo ""

    FAILED_CHECKS=()

    # Run each discovered CI command
    while IFS= read -r cmd; do
      echo "Running: $cmd"

      if eval "$cmd" > "tmp/ci_${BRANCH_NAME}_${BRANCH_NUM}.log" 2>&1; then
        echo "  ✅ PASS"
      else
        echo "  ❌ FAIL"
        FAILED_CHECKS+=("$cmd")
      fi
      echo ""
    done <<< "$CI_COMMANDS"

    # Check if any failures
    if [ ${#FAILED_CHECKS[@]} -gt 0 ]; then
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "⚠️  BRANCH VALIDATION FAILED - Attempting Auto-Fix"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "Branch: $BRANCH_NAME"
      echo "Failed Checks:"
      for check in "${FAILED_CHECKS[@]}"; do
        echo "  ❌ $check"
      done
      echo ""
      echo "Logs: tmp/ci_${BRANCH_NAME}_${BRANCH_NUM}.log"
      echo ""

      # ==============================================
      # INTELLIGENT AUTO-FIX ATTEMPT
      # ==============================================

      echo "🤖 Attempting intelligent auto-fix..."
      echo ""

      # Parse error log to identify issue
      LOG_FILE="tmp/ci_${BRANCH_NAME}_${BRANCH_NUM}.log"

      # Detect error type
      if grep -q "ModuleNotFoundError\|ImportError\|cannot import" "$LOG_FILE"; then
        ERROR_TYPE="ImportError"
        MISSING_MODULE=$(grep -o "No module named '[^']*'" "$LOG_FILE" | head -1 | cut -d"'" -f2 || echo "unknown")
        echo "Detected: Missing import - $MISSING_MODULE"
      elif grep -q "fixture.*not found" "$LOG_FILE"; then
        ERROR_TYPE="FixtureError"
        MISSING_FIXTURE=$(grep -o "fixture '[^']*' not found" "$LOG_FILE" | head -1 | cut -d"'" -f2 || echo "unknown")
        echo "Detected: Missing fixture - $MISSING_FIXTURE"
      elif grep -q "is not defined\|NameError" "$LOG_FILE"; then
        ERROR_TYPE="TypeError"
        MISSING_TYPE=$(grep -o '"[^"]*" is not defined' "$LOG_FILE" | head -1 | cut -d'"' -f2 || echo "unknown")
        echo "Detected: Undefined type - $MISSING_TYPE"
      else
        ERROR_TYPE="Unknown"
        echo "Detected: Unknown error type"
      fi
      echo ""

      FIX_APPLIED=false

      # Step 1: Search source branch for relevant code
      echo "🔍 Step 1: Searching source branch ($SOURCE_BRANCH) for fixes..."
      if [ "$ERROR_TYPE" = "ImportError" ] && [ -n "$MISSING_MODULE" ]; then
        # Convert module path to file path
        MODULE_FILE=$(echo "$MISSING_MODULE" | tr '.' '/' | sed 's/$/.py/')

        if git show "$SOURCE_BRANCH:$MODULE_FILE" > /dev/null 2>&1; then
          echo "  ✅ Found $MODULE_FILE in source branch"
          echo "  Applying fix..."
          git checkout "$SOURCE_BRANCH" -- "$MODULE_FILE" 2>/dev/null || true
          git add "$MODULE_FILE"
          git commit -m "fix: add missing module $MISSING_MODULE from source branch" || true
          FIX_APPLIED=true
        else
          echo "  ❌ Not found in source branch"
        fi
      fi
      echo ""

      # Step 2: Search already-created branches for fixes
      if [ "$FIX_APPLIED" = "false" ] && [ $BRANCH_NUM -gt 1 ]; then
        echo "🔍 Step 2: Searching already-created branches for fixes..."

        # Get list of already-created branches (before current)
        CREATED_BRANCHES=($(grep "^branch = " "$CONFIG_FILE" | cut -d'"' -f2 | head -n $((BRANCH_NUM - 1))))

        for prev_branch in "${CREATED_BRANCHES[@]}"; do
          echo "  Checking $prev_branch..."

          if [ "$ERROR_TYPE" = "ImportError" ] && [ -n "$MODULE_FILE" ]; then
            if git show "$prev_branch:$MODULE_FILE" > /dev/null 2>&1; then
              echo "    ✅ Found $MODULE_FILE in $prev_branch"
              echo "    Applying fix..."
              git checkout "$prev_branch" -- "$MODULE_FILE" 2>/dev/null || true
              git add "$MODULE_FILE"
              git commit -m "fix: add missing module $MISSING_MODULE from $prev_branch" || true
              FIX_APPLIED=true
              break
            fi
          fi
        done

        if [ "$FIX_APPLIED" = "false" ]; then
          echo "  ❌ Not found in created branches"
        fi
      fi
      echo ""

      # Step 3: If no fix found, report failure
      if [ "$FIX_APPLIED" = "false" ]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "❌ AUTO-FIX FAILED - Manual Intervention Required"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Could not automatically fix the issue."
        echo "The branch has been created LOCALLY but NOT pushed."
        echo ""
        echo "Options:"
        echo "  1. Fix issues manually in the branch"
        echo "  2. Re-run validation: git checkout $BRANCH_NAME && [run checks]"
        echo "  3. Skip this branch: [manual intervention]"
        echo ""
        echo "Pipeline STOPPED at branch $BRANCH_NUM/$TOTAL"
        exit 1
      fi

      # Step 4: Re-run validation after fix
      echo "🔄 Re-running validation after fix..."
      echo ""

      FAILED_CHECKS=()
      while IFS= read -r cmd; do
        echo "Running: $cmd"

        if eval "$cmd" > "tmp/ci_${BRANCH_NAME}_${BRANCH_NUM}_retry.log" 2>&1; then
          echo "  ✅ PASS"
        else
          echo "  ❌ FAIL"
          FAILED_CHECKS+=("$cmd")
        fi
        echo ""
      done <<< "$CI_COMMANDS"

      # Check if still failing after fix
      if [ ${#FAILED_CHECKS[@]} -gt 0 ]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "❌ STILL FAILING AFTER AUTO-FIX"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Auto-fix was applied but validation still fails."
        echo "Logs: tmp/ci_${BRANCH_NAME}_${BRANCH_NUM}_retry.log"
        echo ""
        echo "Pipeline STOPPED at branch $BRANCH_NUM/$TOTAL"
        exit 1
      fi

      echo "✅ Auto-fix successful! All checks now passing."

      # Record auto-fix in TOML
      sed -i.bak "/branch = \"$BRANCH_NAME\"/a\\
auto_fixed = true\\
fix_type = \"$ERROR_TYPE\"" "$CONFIG_FILE"
    else
      echo "✅ All CI checks passed!"
    fi
  fi

  # ==============================================
  # SIZE MONITORING (CHECK IF BRANCH TOO SMALL)
  # ==============================================

  echo ""
  echo "📏 Checking branch size..."

  # Count lines of code changed in this branch
  LINES_CHANGED=$(git diff --shortstat "$BASE_BRANCH" | grep -o '[0-9]* insertion' | grep -o '[0-9]*' || echo "0")
  LINES_DELETED=$(git diff --shortstat "$BASE_BRANCH" | grep -o '[0-9]* deletion' | grep -o '[0-9]*' || echo "0")
  TOTAL_LINES=$((LINES_CHANGED + LINES_DELETED))

  echo "  Lines changed: $TOTAL_LINES"

  if [ "$TOTAL_LINES" -lt 40 ]; then
    echo "  ⚠️  Branch is too small (< 40 lines)"
    echo "  Marking for consolidation..."

    # Mark in TOML for replanning
    sed -i.bak "/branch = \"$BRANCH_NAME\"/a\\
too_small = true\\
lines_changed = $TOTAL_LINES" "$CONFIG_FILE"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  WARNING: Branch Too Small"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "This branch has only $TOTAL_LINES lines of changes."
    echo "The supervisor may trigger replanning to consolidate small branches."
    echo ""
  else
    echo "  ✅ Branch size acceptable ($TOTAL_LINES lines)"
  fi

  # ==============================================
  # PUSH BRANCH (ONLY IF VALIDATION PASSED)
  # ==============================================

  echo ""
  echo "📤 Pushing branch to remote..."
  git push -u origin "$BRANCH_NAME" || {
    echo "❌ Failed to push $BRANCH_NAME"
    exit 1
  }

  echo "✅ Branch $BRANCH_NUM/$TOTAL pushed successfully"

  # Record in TOML
  sed -i.bak "/branch = \"$BRANCH_NAME\"/a\\
commit_sha = \"$COMMIT_SHA\"\\
pushed = true\\
validated = true" "$CONFIG_FILE"

done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ All $TOTAL branches created, validated, and pushed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

### Step 4: Create PRs with Correct References

After pushing all branches, create PRs and update descriptions:

```bash
echo ""
echo "📝 Creating PRs..."
echo ""

PR_NUMBERS=()

for i in "${!BRANCHES[@]}"; do
  BRANCH_NAME="${BRANCHES[$i]}"
  BASE_BRANCH=$(grep -A 10 "branch = \"$BRANCH_NAME\"" "$CONFIG_FILE" | grep "base = " | head -1 | cut -d'"' -f2)

  # Get meaningful title from commit message
  COMMIT_MSG=$(grep -A 10 "branch = \"$BRANCH_NAME\"" "$CONFIG_FILE" | grep "commit = " | head -1 | cut -d'"' -f2-)
  PR_TITLE="$COMMIT_MSG"

  # Create PR
  PR_URL=$(gh pr create \
    --base "$BASE_BRANCH" \
    --head "$BRANCH_NAME" \
    --title "$PR_TITLE" \
    --body "Part $((i+1))/$TOTAL - Temporary description, will be updated")

  # Extract PR number
  PR_NUM=$(echo "$PR_URL" | grep -oE '[0-9]+$')
  PR_NUMBERS+=("$PR_NUM")

  echo "✅ PR #$PR_NUM created: $PR_URL"
done

echo ""
echo "📝 Updating PR descriptions with correct PR numbers..."
echo ""

# Now update all PR descriptions to reference actual PR numbers
for i in "${!PR_NUMBERS[@]}"; do
  PR_NUM="${PR_NUMBERS[$i]}"
  BRANCH_NAME="${BRANCHES[$i]}"

  # Get branch metadata from config
  BRANCH_DESC=$(grep -A 10 "branch = \"$BRANCH_NAME\"" "$CONFIG_FILE" | grep "description = " | head -1 | cut -d'"' -f2-)
  LAYER_NUM=$(grep -A 10 "branch = \"$BRANCH_NAME\"" "$CONFIG_FILE" | grep "layer = " | head -1 | awk '{print $3}')

  # Count files in this branch
  FILE_COUNT=$(grep -A 100 "branch = \"$BRANCH_NAME\"" "$CONFIG_FILE" | grep '  ".*",' | wc -l | xargs)

  # Get branch short name (last part after /)
  BRANCH_SHORT="${BRANCH_NAME##*/}"

  # Build comprehensive PR description
  DESCRIPTION="## Summary

${BRANCH_DESC}

This is **PR #$((i+1)) of $TOTAL** in the stack.

## Stack Context

This PR is part of a larger feature implementation split into reviewable chunks:

"

  # Build numbered stack list
  for j in "${!BRANCHES[@]}"; do
    STACK_NUM=$((j+1))
    STACK_BRANCH="${BRANCHES[$j]}"
    STACK_SHORT="${STACK_BRANCH##*/}"
    STACK_PR="${PR_NUMBERS[$j]}"
    STACK_DESC=$(grep -A 10 "branch = \"$STACK_BRANCH\"" "$CONFIG_FILE" | grep "description = " | head -1 | cut -d'"' -f2-)

    if [ $j -eq $i ]; then
      DESCRIPTION+="$STACK_NUM. 🔄 **PR #$STACK_PR: $STACK_SHORT** ← You are here
"
    elif [ $j -lt $i ]; then
      DESCRIPTION+="$STACK_NUM. ✅ PR #$STACK_PR: $STACK_SHORT
"
    else
      DESCRIPTION+="$STACK_NUM. ⏳ PR #$STACK_PR: $STACK_SHORT
"
    fi

    if [ -n "$STACK_DESC" ]; then
      DESCRIPTION+="   - ${STACK_DESC}
"
    fi
  done

  DESCRIPTION+="
**Merge Flow**: "
  for j in $(seq 0 $((TOTAL-1))); do
    if [ $j -eq $i ]; then
      DESCRIPTION+="**#${PR_NUMBERS[$j]}**"
    else
      DESCRIPTION+="#${PR_NUMBERS[$j]}"
    fi

    if [ $j -lt $((TOTAL-1)) ]; then
      DESCRIPTION+=" → "
    fi
  done

  DESCRIPTION+="

## Dependencies

"

  if [ $i -eq 0 ]; then
    DESCRIPTION+="**Targets**: \`main\` (base branch)

**No dependencies** - this is the foundation layer

"
  else
    PREV_PR="${PR_NUMBERS[$((i-1))]}"
    PREV_BRANCH="${BRANCHES[$((i-1))]}"
    PREV_SHORT="${PREV_BRANCH##*/}"

    DESCRIPTION+="**Depends on**: PR #$PREV_PR (\`$PREV_SHORT\`)

**Targets**: \`$PREV_SHORT\` branch

"
  fi

  if [ $i -lt $((TOTAL-1)) ]; then
    NEXT_PR="${PR_NUMBERS[$((i+1))]}"
    NEXT_BRANCH="${BRANCHES[$((i+1))]}"
    NEXT_SHORT="${NEXT_BRANCH##*/}"

    DESCRIPTION+="**Child PR**: PR #$NEXT_PR (\`$NEXT_SHORT\`) - will merge after this one

"
  fi

  DESCRIPTION+="## Review Notes

**Focus areas for review**:

- [ ] Code follows project conventions and patterns
- [ ] Changes align with the layer's purpose
- [ ] No unintended dependencies on future PRs
- [ ] Documentation is clear and accurate

"

  if [ $i -eq $((TOTAL-1)) ]; then
    DESCRIPTION+="**Review order**: Review LAST (after all parent PRs approved)

"
  elif [ $i -eq 0 ]; then
    DESCRIPTION+="**Review order**: Review FIRST (this is the foundation)

"
  else
    DESCRIPTION+="**Review order**: Review after PR #$PREV_PR is approved

"
  fi

  DESCRIPTION+="## Next Steps

"

  if [ $i -lt $((TOTAL-1)) ]; then
    NEXT_PR="${PR_NUMBERS[$((i+1))]}"
    DESCRIPTION+="**After this PR is merged:**

1. Merge this PR into its base branch
2. Continue with PR #$NEXT_PR (next in stack)
3. Repeat until all PRs are merged

"
  else
    DESCRIPTION+="**After this PR is merged:**

This is the FINAL PR in the stack.

1. Merge this PR to complete the feature
2. Feature is complete and deployed
3. Safe to delete feature branches

"
  fi

  DESCRIPTION+="---

*This PR description was generated to provide context for both human reviewers and LLMs analyzing the codebase later.*"

  # Update PR
  gh pr edit "$PR_NUM" --body "$DESCRIPTION"
  echo "✅ Updated PR #$PR_NUM description"
done

echo ""
echo "✅ All PR descriptions updated with correct references"
```

## Key Improvements

1. **Sequential Processing**: Creates branches one at a time
2. **Local CI Validation**: Runs checks before pushing
3. **Fail Fast**: Stops immediately on first failure
4. **Correct PR References**: Updates descriptions with actual PR numbers
5. **Project Agnostic**: Discovers CI commands from workflow files
6. **Full Traceability**: Logs everything to tmp/

## Remember

- **NEVER batch create** - always sequential
- **ALWAYS validate** before pushing
- **STOP on failure** - don't create broken PRs
- **UPDATE PR descriptions** - fix #1 #2 references
- **Log everything** - save CI output to tmp/
