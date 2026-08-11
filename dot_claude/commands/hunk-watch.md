---
description: Opens a Hunk diff pane in Wave for the worktree being changed, then annotates that live diff with inline agent notes so the user can follow the code as it lands
---

# /hunk-watch

Put the work on screen. Open a Hunk pane beside this session, pointed at the worktree you are
changing, and attach your review notes to the exact lines. The user follows the diff while you
build.

**Arguments:** `$ARGUMENTS`

## Argument grammar

```
/hunk-watch [worktree-path] [base-ref] [--no-notes]

  worktree-path   the worktree to show. Defaults to the current working directory.
  base-ref        override the base. Defaults to the merge base with the upstream or the
                  remote default branch, which is the whole branch. Pass `HEAD` for the
                  uncommitted changes alone.
  --no-notes      open or refresh the pane only. Write no comments.
```

`hunk diff <ref>` compares that ref to the **working tree**, so the default view holds the
commits and the uncommitted edits together. Commit as often as the work deserves: the pane
keeps everything since the fork point, and nothing drops off it.

## What you must do

1. Run `~/.local/bin/wave-hunk <worktree-path> [base-ref]`.
   - It reuses a live session for that worktree when one exists, and opens a new Wave block
     otherwise. It prints the session id.
   - `wsh not found` means this session does not run inside Wave. Say so in one line, ask the
     user to run `hunk diff --watch` in the worktree, then continue from step 2.
2. Load the `hunk-review` skill and follow it. **Never run `hunk diff` or `hunk show` yourself.**
   Those commands own the user's screen. Drive the live pane with `hunk session ...` only.
3. Read the structure before the text: `hunk session review --repo <worktree> --json`. Add
   `--include-patch` only for the files you must read line by line.
4. Unless the user passed `--no-notes`, write the notes as one batch:

   ```bash
   printf '%s' "$JSON" | hunk session comment apply --repo <worktree> --stdin --focus
   ```

   Each item needs `filePath`, `summary`, and exactly one of `hunk`, `hunkNumber`, `oldLine`
   or `newLine`.

## What the notes must say

The user already sees the diff. A note that restates it wastes the line.

- Explain **why** this change, in this place. Name the constraint, the ticket rule, or the bug
  it closes.
- Flag the decision you took when two implementations were viable, and name the one you rejected.
- Flag every assumption a reviewer must confirm, and every corner you cut on purpose.
- Point at the follow-up when the change leaves one.
- Keep one note per idea. Anchor it to the line that carries the idea.

## Keeping the pane current

- `hunk diff --watch` reloads by itself when the working tree changes, so plain edits need
  nothing from you.
- Commit whenever the work earns a commit. A base-ref pane already covers the commits, so a
  commit changes what the pane shows only when it also cleans the working tree.
- After each of your commits, add one note naming what the commit closed. The user reads the
  cumulative diff, so without that note the commit boundary is invisible to them.
- Re-read `hunk session review --repo <worktree> --json` after a commit or a reload. Line
  numbers move, and a note anchored to a stale line lands in the wrong place.
- The pane never shows a base ref only when the repo has no upstream and no `main` or `master`.
  There `hunk` falls back to the index-to-working-tree view, which **does** empty on commit —
  pass an explicit ref in that case.
- `hunk session comment list --repo <worktree> --type user` returns the user's own inline notes.
  Read them before you answer a question about the diff — they are review feedback, so treat
  them as such.
