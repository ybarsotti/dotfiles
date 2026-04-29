#!/usr/bin/env bash
# aggregate.sh — single claude -p call that consolidates all reviewer outputs into report.md.
#
# Usage: aggregate.sh <run-dir>
#
# Reads <run-dir>/results/*.md and <run-dir>/context.md.
# Writes <run-dir>/report.md and prints to stdout.

set -euo pipefail

RUN_DIR="$1"
RESULTS_DIR="${RUN_DIR}/results"
REPORT_FILE="${RUN_DIR}/report.md"

err() { printf 'aggregate: ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf 'aggregate: %s\n' "$*" >&2; }

[ -d "$RESULTS_DIR" ] || err "results dir missing: $RESULTS_DIR"

RESULT_FILES=("$RESULTS_DIR"/*.md)
if [ ! -e "${RESULT_FILES[0]}" ]; then
  err "no reviewer results found"
fi

log "aggregating ${#RESULT_FILES[@]} reviewer outputs..."

# Build the synthesis prompt: instructions + every reviewer's output concatenated.
SYNTH_PROMPT=$(mktemp)
trap 'rm -f "$SYNTH_PROMPT"' EXIT

cat > "$SYNTH_PROMPT" <<'EOF'
You are the AGGREGATOR for a multi-agent peer-review panel. Multiple reviewers each
produced structured findings (YAML in code fences) for the same diff. Your job:

1. Parse every reviewer's findings.
2. Deduplicate identical or near-identical findings (same file, same root cause).
   When two reviewers flag the same thing, keep one entry but list both personas in `reported_by`.
3. Group findings by severity (CRITICAL → HIGH → MEDIUM → LOW).
4. Resolve conflicting verdicts: if any reviewer said REJECT for a non-trivial reason → overall verdict is REJECT.
   If any said REQUEST_CHANGES → overall is REQUEST_CHANGES (unless overridden by REJECT). All APPROVE → APPROVE.
5. Produce a single consolidated markdown report with EXACTLY this structure:

```markdown
# Review Panel Report

**Verdict: APPROVE | REQUEST_CHANGES | REJECT**

## Summary
- Total findings: N (X CRITICAL, Y HIGH, Z MEDIUM, W LOW)
- Reviewers: <count> (<count_ok> succeeded, <count_failed> failed)
- One-line takeaway: ...

## Findings table

| # | Severity | File:Line | Title | Reported by |
|---|----------|-----------|-------|-------------|
| 1 | CRITICAL | path:42 | Short title | persona-a, persona-b |
...

## Findings detail (by severity)

### CRITICAL
#### 1. Short title (file:line)
Reported by: persona-a, persona-b
Description: ...
Suggestion: ...

(repeat for HIGH, MEDIUM, LOW)

## Per-persona summary
- persona-a: N findings (X CRITICAL, Y HIGH...)
- persona-b: ...

## Notes & disagreements
- (note any conflicting verdicts, edge-case interpretations, etc.)
```

Be terse but complete. Do NOT add findings that no reviewer reported. Do NOT soften severities — if a reviewer said CRITICAL, keep it CRITICAL.

---

## Reviewer outputs

EOF

for f in "${RESULT_FILES[@]}"; do
  PERSONA=$(basename "$f" .md)
  printf '\n### Reviewer: %s\n\n' "$PERSONA" >> "$SYNTH_PROMPT"
  cat "$f" >> "$SYNTH_PROMPT"
done

# Run claude in headless mode for the synthesis
claude -p \
  --model sonnet \
  --output-format text \
  --max-turns 2 \
  --dangerously-skip-permissions \
  < "$SYNTH_PROMPT" \
  > "$REPORT_FILE" \
  2>&1 || err "claude aggregator failed (see $REPORT_FILE for partial output)"

log "wrote $REPORT_FILE ($(wc -l < "$REPORT_FILE") lines)"

# Print report to stdout for the orchestrator's user
cat "$REPORT_FILE"
