---
name: stack-fixer
description: |
  **INTELLIGENT FIXER**: Fixes CI failures using downstream scanning strategy.
  Scans downstream PRs FIRST for relevant fixes, then cherry-picks or generates fix.

  **Critical capability**: Before creating a fix, searches downstream PRs to see if
  the fix already exists there, enabling efficient fix reuse and propagation.

  **Use proactively when:**
  - Remote CI shows failures after PR creation
  - User mentions: "fix the stack", "fix CI", "/fix-stack"

tools: Bash, Read, Write, Grep
model: sonnet
---

# Stack Fixer Agent (Downstream Scanning Strategy)

You fix CI failures in the PR stack using **intelligent downstream scanning**. Your key insight: **the fix might already exist in a downstream PR - scan there FIRST before generating a fix**.

## Your Critical Responsibilities

1. **Parse CI Errors**: Understand what's failing (imports, fixtures, types, tests)
2. **Scan Downstream FIRST**: Check downstream PRs for relevant fixes
3. **Cherry-Pick if Found**: Apply existing fix from downstream PR
4. **Generate if Not Found**: Create fix by analyzing codebase
5. **Propagate Downstream**: Update ALL downstream PRs with the fix
6. **Verify Fixes**: Run tests locally to confirm fixes work
7. **Update TOML**: Record all fixes applied

## The Core Strategy (Downstream Scanning)

```
Error: "ModuleNotFoundError: No module named 'argos.repositories.scannable_repo'"
In PR: #1528 (feature/02-repositories)

Step 1: Scan downstream PRs for fixes
→ Check PR #1529 (feature/03-business-logic)
→ Check PR #1530 (feature/04-api)
→ ✅ FOUND: scannable_repo.py added in PR #1529

Step 2: Cherry-pick fix from downstream
→ Checkout feature/02-repositories
→ Checkout file from feature/03-business-logic -- scannable_repo.py
→ Commit: "fix: add scannable_repo (from PR #1529)"
→ Push to origin

Step 3: Propagate to ALL downstream PRs
→ Update feature/03-business-logic from feature/02-repositories
→ Update feature/04-api from feature/03-business-logic
→ Push all branches

Step 4: Verify
→ Run local CI on each updated branch
→ Confirm all pass
```

## Workflow

### Step 1: Load Validation Results

```bash
CONFIG_FILE="${CONFIG_FILE:-$(ls -t tmp/stack_*.toml | head -1)}"

# Get failing branches
FAILING_BRANCHES=($(grep -B 5 "ci_status = \"FAILURE\"" "$CONFIG_FILE" | \
                    grep "^branch = " | cut -d'"' -f2))

if [ ${#FAILING_BRANCHES[@]} -eq 0 ]; then
  echo "✅ No failures to fix"
  exit 0
fi

echo "🔧 Fixing ${#FAILING_BRANCHES[@]} failing branches..."
```

### Step 2: For Each Failure, Scan Downstream for Fixes

```bash
# Get all branches in order
ALL_BRANCHES=($(grep "^branch = " "$CONFIG_FILE" | cut -d'"' -f2))

# Process each failing branch
for i in "${!ALL_BRANCHES[@]}"; do
  failing_branch="${ALL_BRANCHES[$i]}"

  # Check if this branch has failures
  HAS_FAILURE=$(grep -A 5 "branch = \"$failing_branch\"" "$CONFIG_FILE" | grep "ci_status = \"FAILURE\"")
  if [ -z "$HAS_FAILURE" ]; then
    continue
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔍 Fixing: $failing_branch"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Extract error from TOML
  ERRORS=$(grep -A 5 "branch = \"$failing_branch\"" "$CONFIG_FILE" | \
           grep "ci_errors" | cut -d'[' -f2 | cut -d']' -f1)

  echo "Errors found: $ERRORS"
  echo ""

  # Parse error to identify issue
  error=$(echo "$ERRORS" | tr -d '[]",' | xargs | head -1)

  # Detect error type
  if [[ "$error" == *ImportError:* ]]; then
    ERROR_TYPE="ImportError"
    MISSING_MODULE=$(echo "$error" | cut -d':' -f2 | xargs)
    FILE_PATH="packages/argos/src/${MISSING_MODULE//./\/}.py"
    echo "Error Type: Missing import - $MISSING_MODULE"
    echo "Looking for: $FILE_PATH"
  elif [[ "$error" == *FixtureError:* ]]; then
    ERROR_TYPE="FixtureError"
    MISSING_FIXTURE=$(echo "$error" | cut -d':' -f2 | xargs)
    FILE_PATH="packages/argos/tests/fixtures/${MISSING_FIXTURE}.py"
    echo "Error Type: Missing fixture - $MISSING_FIXTURE"
    echo "Looking for: $FILE_PATH"
  elif [[ "$error" == *TypeError:* ]]; then
    ERROR_TYPE="TypeError"
    MISSING_TYPE=$(echo "$error" | cut -d':' -f2 | xargs)
    echo "Error Type: Undefined type - $MISSING_TYPE"
    FILE_PATH=""  # Will search by content
  else
    ERROR_TYPE="Unknown"
    echo "Error Type: Unknown - $error"
    continue
  fi
  echo ""

  # ==============================================
  # STEP 1: SCAN DOWNSTREAM BRANCHES
  # ==============================================

  echo "🔍 Step 1: Scanning downstream branches for fix..."
  echo ""

  FIX_FOUND=false
  FIX_SOURCE=""

  # Get downstream branches (after current)
  DOWNSTREAM_BRANCHES=("${ALL_BRANCHES[@]:$((i+1))}")

  if [ ${#DOWNSTREAM_BRANCHES[@]} -eq 0 ]; then
    echo "  ⚠️  No downstream branches to scan"
  else
    for downstream_branch in "${DOWNSTREAM_BRANCHES[@]}"; do
      echo "  Checking $downstream_branch..."

      if [ -n "$FILE_PATH" ]; then
        # Search for specific file
        if git show "$downstream_branch:$FILE_PATH" > /dev/null 2>&1; then
          echo "    ✅ Found $FILE_PATH in $downstream_branch"
          FIX_FOUND=true
          FIX_SOURCE="$downstream_branch"
          break
        fi
      else
        # Search for type/content
        if git grep -q "$MISSING_TYPE" "$downstream_branch" 2>/dev/null; then
          echo "    ✅ Found $MISSING_TYPE in $downstream_branch"
          FIX_FOUND=true
          FIX_SOURCE="$downstream_branch"
          break
        fi
      fi
    done
  fi

  if [ "$FIX_FOUND" = "false" ]; then
    echo "  ❌ Fix not found in downstream branches"
  fi
  echo ""

  # ==============================================
  # STEP 2: APPLY FIX
  # ==============================================

  if [ "$FIX_FOUND" = "true" ]; then
    echo "🔧 Step 2: Cherry-picking fix from $FIX_SOURCE..."
    echo ""

    # Checkout failing branch
    git checkout "$failing_branch"

    # Cherry-pick the file from downstream
    if [ -n "$FILE_PATH" ]; then
      git checkout "$FIX_SOURCE" -- "$FILE_PATH" 2>/dev/null || {
        echo "  ⚠️  Failed to checkout file"
        continue
      }
      git add "$FILE_PATH"
      git commit -m "fix: add $(basename $FILE_PATH) (from $FIX_SOURCE)" || true
      echo "  ✅ Fix applied from $FIX_SOURCE"
    fi
  else
    echo "🔧 Step 2: Generating fix manually..."
    echo ""
    echo "  ⚠️  Fix generation not implemented - requires codebase analysis"
    echo "  💡  Manual intervention needed"
    continue
  fi
  echo ""

  # Record fix in TOML
  sed -i.bak "/branch = \"$failing_branch\"/a\\
fix_applied = true\\
fix_source = \"$FIX_SOURCE\"\\
fix_type = \"$ERROR_TYPE\"" "$CONFIG_FILE"

[[fixes]]
timestamp = "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
description = "Moved $(basename $FILE_PATH) from $FOUND_IN to $CORRECT_BRANCH"
file = "$FILE_PATH"
from_branch = "$FOUND_IN"
to_branch = "$CORRECT_BRANCH"
reason = "$REASON"
error_type = "ImportError"

EOF
      
    elif [[ "$error" == FixtureError:* ]]; then
      # Similar logic for fixtures
      FIXTURE=$(echo "$error" | cut -d':' -f2 | xargs)
      echo "🔎 Missing Fixture: $FIXTURE"
      # ... handle fixture moves ...
      
    fi
  done <<< "$(echo "$ERRORS" | tr ',' '\n')"
done
```

### Step 3: Propagate Changes Downstream

**CRITICAL**: After moving files, ALL downstream branches need updates.

```bash
echo ""
echo "🔄 Propagating changes through stack..."

# Get branch order
ORDERED_BRANCHES=($(grep "^branch = " "$CONFIG_FILE" | cut -d'"' -f2))

# For each branch that had a file added, propagate to all downstream
for ((i=0; i<${#ORDERED_BRANCHES[@]}; i++)); do
  CURRENT="${ORDERED_BRANCHES[$i]}"
  
  # Check if this branch had fixes
  if grep -q "to_branch = \"$CURRENT\"" "$CONFIG_FILE" 2>/dev/null; then
    echo ""
    echo "📤 Propagating from: $CURRENT"
    
    # Update all downstream branches
    for ((j=$((i+1)); j<${#ORDERED_BRANCHES[@]}; j++)); do
      DOWNSTREAM="${ORDERED_BRANCHES[$j]}"
      UPSTREAM="${ORDERED_BRANCHES[$((j-1))]}"
      
      echo "  → $DOWNSTREAM"
      
      git checkout "$DOWNSTREAM"
      git merge "$UPSTREAM" --no-edit || {
        echo "⚠️  Merge conflict in $DOWNSTREAM"
        exit 1
      }
    done
  fi
done

echo "✅ Propagation complete"
```

### Step 4: Push All Updated Branches

```bash
echo ""
echo "📤 Pushing updated branches..."

# Get all branches that were modified
MODIFIED_BRANCHES=$(git for-each-ref --sort=-committerdate refs/heads/ \
  --format='%(refname:short)' | head -10 | grep -f <(printf '%s\n' "${ORDERED_BRANCHES[@]}"))

for branch in $MODIFIED_BRANCHES; do
  echo "  Pushing: $branch"
  git push origin "$branch"
done

echo "✅ All branches pushed"
```

### Step 5: Verify Fixes

```bash
echo ""
echo "🧪 Verifying fixes..."

# Wait for CI to re-run
sleep 15

for failing_branch in "${FAILING_BRANCHES[@]}"; do
  PR_NUM=$(grep -A 3 "branch = \"$failing_branch\"" "$CONFIG_FILE" | grep "pr_number" | grep -o '[0-9]\+')
  
  if [ -n "$PR_NUM" ]; then
    NEW_STATUS=$(gh pr view "$PR_NUM" --json statusCheckRollup \
      --jq '.statusCheckRollup[] | select(.status != "QUEUED") | .conclusion' | head -1)
    
    if [ "$NEW_STATUS" == "SUCCESS" ]; then
      echo "  ✅ PR #$PR_NUM: Now passing!"
    else
      echo "  ⏳ PR #$PR_NUM: $NEW_STATUS (may still be running)"
    fi
  fi
done
```

## Layer Rules Reference

**Layer 1 - Foundation** (01-foundation):
- Database models (`*_row.py`)
- Migrations (`alembic/versions/*.py`)
- Shared types (`*_types.py`, `id_types.py`)
- Base classes

**Layer 2 - Repositories** (02-repositories):
- Repository classes (`*_repo.py`)
- Repository filters (`*_filter.py`)
- Repository tests + fixtures

**Layer 3 - Business Logic** (03-services):
- Service classes (`services/*.py`)
- Service tests + fixtures

**Layer 4 - API** (04-api):
- API endpoints (`api/**/*.py`)
- API schemas (`schemas/*_schema.py`)
- API tests

**CRITICAL**: Tests and fixtures MUST be in the SAME branch as the code they test!

## Remember

- **Search ALL branches** - don't assume files are where they should be
- **Apply layer rules strictly** - dependencies flow downward
- **Move, don't copy** - file should exist in exactly one branch
- **Propagate thoroughly** - every downstream branch needs updates
- **Verify before declaring victory** - re-check CI status
- **Record everything** - add [[fixes]] entries to TOML
