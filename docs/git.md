# Git workflow

The merge tool and the Git aliases.

## P4Merge - Visual Merge Tool

P4Merge (Perforce Visual Merge Tool) is configured as the default merge and diff tool for handling merge conflicts visually.

**Usage:**
```bash
# Resolve merge conflicts visually
git mergetool

# Compare files visually
git difftool <file>

# Switch back to nvim for quick merges (optional)
git config merge.tool nvimdiff
```

**Features:**
- 3-way merge view (BASE, LOCAL, REMOTE)
- Visual conflict highlighting
- Side-by-side diff comparison
- Better for complex conflicts than terminal-based tools

## Git Aliases
Over 40 useful git aliases are configured in `.gitconfig`:

**Status & Info:**
- `git s` - Short status
- `git st` - Full status

**Branches:**
- `git br` - List branches
- `git bra` - List all branches (including remotes)

**Log:**
- `git l` - Oneline log with graph
- `git lg` - Pretty log with colors
- `git last` - Show last commit with stats

**Common Operations:**
- `git co` - Checkout
- `git cm` - Commit with message
- `git ps` - Push
- `git p` - Pull
- `git d` - Diff
- `git ds` - Diff staged

**Utilities:**
- `git unstage` - Unstage files
- `git undo` - Undo last commit (soft reset)
- `git clean-branches` - Delete merged branches

Run `git config --get-regexp alias` to see all configured aliases.
