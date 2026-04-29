#!/usr/bin/env bash
# collect-context.sh — assembles context.md for reviewers.
#
# Usage: collect-context.sh <run-dir> <scope> [task-id]
#
# Scope values:
#   main...HEAD            git range (default for branch review)
#   PR-1234                GitHub PR number (uses gh)
#   file:path/to/file.ext  single-file diff vs base
#   <any git ref>          arbitrary git diff target

set -euo pipefail

RUN_DIR="$1"
SCOPE="${2:-main...HEAD}"
TASK_ID="${3:-}"
OUT="${RUN_DIR}/context.md"

err() { printf 'collect-context: ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf 'collect-context: %s\n' "$*" >&2; }

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || err "not in a git repo"
REPO_NAME=$(basename "$REPO_ROOT")
BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT=$(git rev-parse --short HEAD)

# --- Resolve scope into a diff command + base description ---
DIFF_CMD=""
SCOPE_DESC=""
case "$SCOPE" in
  PR-*)
    PR_NUM="${SCOPE#PR-}"
    command -v gh >/dev/null 2>&1 || err "gh CLI required for PR scope"
    DIFF_CMD="gh pr diff $PR_NUM"
    SCOPE_DESC="GitHub PR #${PR_NUM}"
    ;;
  file:*)
    FILE_PATH="${SCOPE#file:}"
    [ -f "$FILE_PATH" ] || err "file not found: $FILE_PATH"
    DIFF_CMD="git diff main...HEAD -- $FILE_PATH"
    SCOPE_DESC="single file: $FILE_PATH (vs main)"
    ;;
  *)
    DIFF_CMD="git diff $SCOPE"
    SCOPE_DESC="git range: $SCOPE"
    ;;
esac

# --- Run the diff ---
DIFF_OUTPUT=$(eval "$DIFF_CMD" 2>/dev/null) || err "diff command failed: $DIFF_CMD"

if [ -z "$DIFF_OUTPUT" ]; then
  err "diff is empty — nothing to review for scope '$SCOPE'"
fi

# --- File-list + stats ---
case "$SCOPE" in
  PR-*)
    FILES=$(gh pr view "${SCOPE#PR-}" --json files -q '.files[].path' 2>/dev/null || echo "")
    STATS=$(echo "$DIFF_OUTPUT" | awk '/^\+[^+]/{add++} /^-[^-]/{del++} END{printf "%d insertions, %d deletions", add+0, del+0}')
    FILE_COUNT=$(echo "$FILES" | grep -c . || true)
    ;;
  file:*)
    FILES="${SCOPE#file:}"
    FILE_COUNT=1
    STATS=$(echo "$DIFF_OUTPUT" | awk '/^\+[^+]/{add++} /^-[^-]/{del++} END{printf "%d insertions, %d deletions", add+0, del+0}')
    ;;
  *)
    FILES=$(git diff --name-only "$SCOPE" 2>/dev/null || echo "")
    FILE_COUNT=$(echo "$FILES" | grep -c . || true)
    STATS=$(git diff --shortstat "$SCOPE" 2>/dev/null || echo "(stats unavailable)")
    ;;
esac

# --- Categorize files (lightweight stack detection) ---
# Order matters: more specific patterns must precede generic ones (e.g. *.proto
# before *.ts so that proto-generated *_pb.ts is caught as PROTO not FRONTEND).
declare -a BACKEND FRONTEND PROTO MIGRATION INFRA DOCS CONFIG OTHER
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    *.proto|*/gen/*|*_pb.ts|*_pb.go|*_connect.ts)         PROTO+=("$f") ;;
    *.sql|*/migrations/*|*/seeds/*)                       MIGRATION+=("$f") ;;
    Dockerfile*|docker-compose*|.github/*|*/k8s/*|Justfile|justfile) INFRA+=("$f") ;;
    *.md|docs/*)                                          DOCS+=("$f") ;;
    *.go|*/internal/*|*/cmd/*|*-backend/*)                BACKEND+=("$f") ;;
    *.tsx|*.ts|*.jsx|*.js|*-client/*|*/components/*|*.css|*.scss) FRONTEND+=("$f") ;;
    .env*|*.toml|*.yaml|*.yml|*.json)                     CONFIG+=("$f") ;;
    *)                                                    OTHER+=("$f") ;;
  esac
done <<< "$FILES"

format_list() {
  local arr=("$@")
  if [ "${#arr[@]}" -eq 0 ]; then echo "(none)"
  else printf '%s\n' "${arr[@]}" | sed 's/^/  - /'; fi
}

# --- Linked task body (best-effort) ---
TASK_SECTION=""
if [ -z "$TASK_ID" ]; then
  # Auto-detect from branch name then commit messages
  TASK_ID=$(echo "$BRANCH" | grep -oE '[A-Z]+-[0-9]+' | head -1 || true)
  [ -z "$TASK_ID" ] && TASK_ID=$(git log -10 --pretty=%B 2>/dev/null | grep -oE '[A-Z]+-[0-9]+' | head -1 || true)
fi

if [ -n "$TASK_ID" ]; then
  TASK_BODY=""
  # Try lineark CLI (Linear)
  if command -v lineark >/dev/null 2>&1; then
    TASK_BODY=$(lineark issue view "$TASK_ID" 2>/dev/null || true)
  fi
  if [ -z "$TASK_BODY" ]; then
    TASK_BODY="(task ID detected: ${TASK_ID}, but no integration available to fetch body — reviewers should note this gap)"
  fi
  TASK_SECTION="## Linked task

ID: ${TASK_ID}

\`\`\`
${TASK_BODY}
\`\`\`
"
fi

# --- Write context.md ---
cat > "$OUT" <<EOF
# Review Context

## Repo
- name: ${REPO_NAME}
- branch: ${BRANCH}
- commit: ${COMMIT}
- scope: ${SCOPE_DESC}

## Diff stats
- files changed: ${FILE_COUNT}
- ${STATS}

## Changed files by category
### Backend
$(format_list "${BACKEND[@]}")

### Frontend
$(format_list "${FRONTEND[@]}")

### Proto / generated
$(format_list "${PROTO[@]}")

### Migrations / SQL
$(format_list "${MIGRATION[@]}")

### Infra / CI
$(format_list "${INFRA[@]}")

### Docs
$(format_list "${DOCS[@]}")

### Config
$(format_list "${CONFIG[@]}")

### Other
$(format_list "${OTHER[@]}")

${TASK_SECTION}

## Diff

\`\`\`diff
${DIFF_OUTPUT}
\`\`\`
EOF

log "wrote $OUT (${FILE_COUNT} files, $(wc -l < "$OUT") lines)"
