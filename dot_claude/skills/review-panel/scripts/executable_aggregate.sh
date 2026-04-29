#!/usr/bin/env bash
# aggregate.sh — single claude -p call that consolidates all reviewer outputs into report.md.
#
# Usage: aggregate.sh <run-dir> [variant-name]
#
# Reads <run-dir>/results/*.md and <run-dir>/context.md.
# Writes <run-dir>/report.md (and <run-dir>/aggregate.log for stderr).
# Prints report.md to stdout.

set -euo pipefail

RUN_DIR="$1"
VARIANT_NAME="${2:-default}"
RESULTS_DIR="${RUN_DIR}/results"
REPORT_FILE="${RUN_DIR}/report.md"
LOG_FILE="${RUN_DIR}/aggregate.log"

err() { printf 'aggregate: ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf 'aggregate: %s\n' "$*" >&2; }

[ -d "$RESULTS_DIR" ] || err "results dir missing: $RESULTS_DIR"

RESULT_FILES=("$RESULTS_DIR"/*.md)
if [ ! -e "${RESULT_FILES[0]}" ]; then
  err "no reviewer results found"
fi

log "aggregating ${#RESULT_FILES[@]} reviewer outputs (schema=${VARIANT_NAME})..."

SYNTH_PROMPT=$(mktemp)
trap 'rm -f "$SYNTH_PROMPT"' EXIT

# --- Schema-specific aggregator instructions ---
# Adversarial variants emit position/dimension/arguments; everything else emits
# the default findings/verdict/severity schema. Branch on variant name.
case "$VARIANT_NAME" in
  adversarial-debate|adversarial*)
    cat > "$SYNTH_PROMPT" <<'EOF'
You are the AGGREGATOR for an adversarial-debate review panel. Reviewers came in
matched pairs: per dimension (architecture, security, performance, completeness,
simplicity), one persona argued APPROVER, the other REJECTER. Each output is YAML
with `position`, `dimension`, `arguments`, `verdict`.

Your job:

1. Group outputs by `dimension`. There should be one approver and one rejecter per dimension.
2. For each dimension, weigh the arguments on both sides. Decide a per-dimension verdict:
   - REQUEST_CHANGES if the rejecter raised material, evidence-backed concerns the approver did not refute
   - APPROVE if the approver's arguments hold and the rejecter's are speculative or weak
   - REJECT if the rejecter's arguments are not just material but blocking (security, correctness, scope)
3. Decide an overall verdict: REJECT if any dimension is REJECT; otherwise REQUEST_CHANGES if any is REQUEST_CHANGES; otherwise APPROVE.
4. Produce a markdown report with EXACTLY this structure:

```markdown
# Review Panel Report (Adversarial Debate)

**Verdict: APPROVE | REQUEST_CHANGES | REJECT**

## Summary
- Dimensions evaluated: <count>
- Per-dimension: X APPROVE, Y REQUEST_CHANGES, Z REJECT
- One-line takeaway: ...

## Per-dimension verdicts

### Architecture: <verdict>
**Approver argued:** <one-paragraph synthesis>
**Rejecter argued:** <one-paragraph synthesis>
**Resolution:** <one paragraph: which side won and why>
**Open questions:** <any unresolved tensions worth surfacing>

(repeat for each dimension)

## Strongest claims (cited)
| Dimension | Side | Claim | Evidence |
|-----------|------|-------|----------|
| ... | approver | ... | file:line |

## Notes
- (any cross-dimension observations, e.g. the same file appearing in multiple dimensions)
```

Be terse. Keep cited claims grounded in what the reviewers actually wrote — do NOT add new claims. If a dimension is missing one side (e.g., approver failed), note that and weight accordingly.

---

## Reviewer outputs

EOF
    ;;
  *)
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
    ;;
esac

for f in "${RESULT_FILES[@]}"; do
  PERSONA=$(basename "$f" .md)
  printf '\n### Reviewer: %s\n\n' "$PERSONA" >> "$SYNTH_PROMPT"
  cat "$f" >> "$SYNTH_PROMPT"
done

# Run claude in headless mode for the synthesis.
# Separate stdout (clean report) from stderr (progress / warnings) — don't pollute report.md.
claude -p \
  --model sonnet \
  --output-format text \
  --max-turns 2 \
  --dangerously-skip-permissions \
  < "$SYNTH_PROMPT" \
  > "$REPORT_FILE" \
  2> "$LOG_FILE" || err "claude aggregator failed (see $LOG_FILE)"

log "wrote $REPORT_FILE ($(wc -l < "$REPORT_FILE") lines)"

cat "$REPORT_FILE"
