# Reviewer dispatch (Phase 2)

Unless `--no-codex`, dispatch a codex reviewer to validate the draft. Assemble
`$RUN_DIR/review-input.md`:
- The drafted title + body
- The output of `git diff --name-only main...HEAD` (the reviewer needs the real
  changed-path domains to judge the Mermaid diagram)
- The detected ticket (or "none")
- The checklist in `references/reviewer-checklist.md`

Dispatch (mirror the codex side of `reviewer.sh`):

```bash
codex exec \
  --skip-git-repo-check \
  --dangerously-bypass-approvals-and-sandbox \
  --color never \
  --output-last-message "$RUN_DIR/review.md" \
  - < "$RUN_DIR/review-input.md" >&2
```
