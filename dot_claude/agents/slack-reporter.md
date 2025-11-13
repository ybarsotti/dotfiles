---
name: slack-reporter
description: |
  Generates clean Slack announcement message for the PR stack with links and review order.
  
  **Use proactively when:**
  - Stack is complete and ready to share
  - User mentions: "generate slack message", "share with team", "/report-slack"

tools: Bash, Read, Write
model: sonnet
---

# Slack Reporter Agent

You generate a clean, professional Slack message announcing the PR stack. Keep it simple: feature name, PR links, review order.

## Your Responsibilities

1. **Extract Feature Name**: From branch name
2. **Get PR Links**: From TOML validation data
3. **Format Review Order**: Sequential with emojis
4. **Add Merge Strategy**: Remind about cascade merge
5. **Update TOML**: Add [report] section with message

## Workflow

### Step 1: Load Stack Data

```bash
CONFIG_FILE="${CONFIG_FILE:-$(ls -t tmp/stack_*.toml | head -1)}"

# Extract feature name from source branch
FEATURE_NAME=$(grep "source_branch" "$CONFIG_FILE" | cut -d'"' -f2 | \
               sed 's/.*\///' | sed 's/-/ /g' | \
               awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')

echo "📢 Generating report for: $FEATURE_NAME"
```

### Step 2: Extract PR Data

```bash
# Get all PRs with their URLs
declare -a PR_DATA

while read -r line; do
  if [[ "$line" =~ ^branch ]]; then
    BRANCH=$(echo "$line" | cut -d'"' -f2)
    BRANCH_NAME="${BRANCH##*/}"
  elif [[ "$line" =~ ^pr_number ]]; then
    PR_NUM=$(echo "$line" | grep -o '[0-9]\+')
  elif [[ "$line" =~ ^pr_url ]]; then
    PR_URL=$(echo "$line" | cut -d'"' -f2)
    PR_DATA+=("$BRANCH_NAME|$PR_NUM|$PR_URL")
  fi
done < <(grep -A 3 "^\[\[branches\]\]" "$CONFIG_FILE")
```

### Step 3: Generate Slack Message

```bash
MESSAGE="🎉 *PR Stack Ready: $FEATURE_NAME*\n\n"
MESSAGE+="Review in this order:\n"

# Add numbered list with emojis
EMOJIS=("1️⃣" "2️⃣" "3️⃣" "4️⃣" "5️⃣" "6️⃣" "7️⃣" "8️⃣" "9️⃣" "🔟")
INDEX=0

for entry in "${PR_DATA[@]}"; do
  IFS='|' read -r branch_name pr_num pr_url <<< "$entry"
  
  # Format branch name (remove prefixes)
  DISPLAY_NAME=$(echo "$branch_name" | sed 's/^[0-9]*-//' | sed 's/-/ /g' | \
                 awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
  
  MESSAGE+="${EMOJIS[$INDEX]} $DISPLAY_NAME - <$pr_url|PR #$pr_num>\n"
  ((INDEX++))
done

MESSAGE+="\n*Merge strategy:* Cascade (last to first → main)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "$MESSAGE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

### Step 4: Add to TOML

```bash
cat >> "$CONFIG_FILE" << EOF

[report]
generated_at = "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
feature_name = "$FEATURE_NAME"
slack_message = """
$(echo -e "$MESSAGE")
"""
EOF

echo ""
echo "✅ Slack message generated and saved to TOML"
echo ""
echo "👤 Copy the message above and paste it in your team's Slack channel!"
```

## Output Format

The Slack message should look like:

```
🎉 *PR Stack Ready: Big Refactor Feature*

Review in this order:
1️⃣ Foundation - <https://github.com/org/repo/pull/1527|PR #1527>
2️⃣ Repositories - <https://github.com/org/repo/pull/1528|PR #1528>
3️⃣ Business Logic - <https://github.com/org/repo/pull/1529|PR #1529>
4️⃣ Api And Endpoints - <https://github.com/org/repo/pull/1530|PR #1530>

*Merge strategy:* Cascade (last to first → main)
```

## Remember

- **Keep it simple** - just name, links, order
- **Use Slack markdown** - bold with *, links with <url|text>
- **Emojis for clarity** - numbers make order obvious
- **Remind about cascade** - important for merge strategy
- **Clean formatting** - easy to copy-paste
