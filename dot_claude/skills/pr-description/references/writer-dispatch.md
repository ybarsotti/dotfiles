# Writer dispatch (Phase 1)

Assemble the writer input into `$RUN_DIR/writer-input.md`:
1. The persona prompt: `~/.claude/skills/pr-description/personas/pr-writer.md`
2. `---`
3. Context: detected ticket, `git diff --stat main...HEAD` **for the writer's private
   understanding only** (remind it: never echo file names/counts into the body), the
   changed-path domains from `git diff --name-only main...HEAD`, the recent commit
   subjects (`git log --pretty=%s main..HEAD`), and — if a plan exists — the extracted
   `## Context`, `## Ticket and Slack context`, `## Requirements matrix`,
   `## Flow diagram`, `## Rationale & key decisions`, `## Stages` and
   `## Edge cases & failure modes` verbatim, plus `$RUN_DIR/evidence.tsv` and the plan's
   `## Deviations`. Tell writer to reconcile
   every requirement against finished diff/tests: `✅ Implemented`, `⚠️ Partial`, or
   `❌ Missing`; never carry `✅ Planned` forward blindly.

Dispatch the writer headless (mirror `~/.claude/skills/deep-review/scripts/reviewer.sh` flags):

```bash
claude -p \
  --model sonnet \
  --output-format text \
  --max-turns 4 \
  --strict-mcp-config \
  --dangerously-skip-permissions \
  < "$RUN_DIR/writer-input.md" > "$RUN_DIR/draft.md"
```

The writer returns a single fenced block: `TITLE:` line, then `---`, then the markdown
body. Parse the title from the `TITLE:` line and the body from everything after `---`.
Write the parsed body to `$RUN_DIR/pr-body.md` and store the title.

**Reject inline** if the draft body contains an "Affected files"/"Files changed"/"Changes"
section or a `+/-` stat block — if so, re-dispatch the writer once with an explicit note
to remove it, then continue.
