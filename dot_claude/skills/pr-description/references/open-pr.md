# Create and update commands (Phase 3)

**Create** (no `--update`):

```bash
gh pr create \
  [--draft] \
  --title "$TITLE" \
  --body-file "$RUN_DIR/pr-body.md" \
  --assignee @me \
  --label "$PR_TYPE" \
  [--reviewer <owner> ...]
```

Retry without `--label`/`--reviewer` if `gh` errors (remote may lack them), same as pr-open.sh.

**Update** (`--update <n>`):

```bash
gh pr edit <n> \
  --title "$TITLE" \
  --body-file "$RUN_DIR/pr-body.md" \
  --add-assignee @me
```
