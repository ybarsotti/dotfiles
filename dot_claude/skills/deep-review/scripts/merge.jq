# Merges recorded findings that name the same defect. Used by report.sh and sarif.sh
# with `jq -s -f merge.jq findings.jsonl`, so both agree on what counts as one finding.
#
# Two reviewers reaching the same file, line and category found one problem, not two.
# The merged entry keeps the highest severity, credits every reviewer that saw it, and
# keeps the first non-empty prose — the reviewer with the worst severity is often not
# the one who explained it best.

def rank: {"CRITICAL":0,"HIGH":1,"MEDIUM":2,"LOW":3}[.] // 4;
def first_nonempty(f): (map(f) | map(select(. != null and . != "")) | first) // "";

# A finding that names no file lands at file "-" and line 0, so file+line+category would
# collapse two unrelated repo-wide findings into one and lose the second title. Key those
# on the title instead; located findings still merge across personas as before.
group_by(if .line > 0 and .file != "-" then [.file, .line, .category] else [.file, .line, .category, (.title | ascii_downcase)] end)
| map(
    (sort_by(.severity | rank) | .[0]) as $top
    | $top + {
        personas: (map(.persona) | unique),
        evidence: (map(.evidence) | unique | join(" | ")),
        description: first_nonempty(.description),
        suggestion: first_nonempty(.suggestion)
      }
  )
| sort_by([(.severity | rank), .category, .file])
