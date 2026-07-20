#!/usr/bin/env bash
# task-body-lib.sh — shared `### Task N:` block parsing for validate-plan.sh
# and validate-draft.sh. Source only; never invoke directly (no `executable_`
# prefix, so chezmoi deploys it under the same name in both the source tree
# and the applied tree — no deployed/source fallback needed to find it, same
# as owns-lib.sh).
#
# This used to be two copies: validate-plan.sh's inline awk, and
# validate-draft.sh's own inline awk that only counted `### Task N:` titles
# and never checked what was inside them — so a draft with bare headings and
# zero Files/Interfaces/Steps content passed `draft-tasks-complete`. Both
# scripts now share this one definition of "a task block is real" so they
# can't quietly diverge on what "complete" means.

# task_title_count FILE — number of real (non-placeholder) `### Task N: <name>`
# blocks. Fence-aware: an illustrative `### Task N:` example inside a ``` block
# (a real task's own body may show one) must never be counted as a real title.
task_title_count() {
  awk '
    /^```/ { infence = !infence; next }
    infence { next }
    /^### Task [0-9]+: [^<]/ { c++ }
    END { print c + 0 }
  ' "$1"
}

# task_body_issues FILE — one line per task block missing a `**Files:**`
# block, a `**Interfaces:**` block, or fewer than 4 `- [ ] **Step` entries,
# formatted `<title>: <miss-tag> <miss-tag> ...`. Empty output means every
# task block found is complete. Fence-aware for the same reason as
# task_title_count above.
task_body_issues() {
  awk '
    /^```/ { infence = !infence; next }
    infence { next }
    /^### Task [0-9]+:/ {
      if (title != "") check()
      title = $0; files = 0; ifaces = 0; steps = 0; next
    }
    /^## / && title != "" { check(); title = "" }
    title != "" && /^\*\*Files:\*\*/      { files = 1 }
    title != "" && /^\*\*Interfaces:\*\*/ { ifaces = 1 }
    title != "" && /^- \[[ x]\] \*\*Step/ { steps++ }
    END { if (title != "") check() }
    function check(   miss) {
      miss = ""
      if (!files)  miss = miss " no-Files-block"
      if (!ifaces) miss = miss " no-Interfaces-block"
      if (steps < 4) miss = miss " only-" steps "-steps"
      if (miss != "") { gsub(/^### /, "", title); print title ":" miss }
    }
  ' "$1"
}
