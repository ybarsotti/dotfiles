#!/usr/bin/env bash
# Tests for launch-workers.sh's `name:runner:model@effort` worker-spec
# grammar: backward compatibility with bare names, the claude/codex runner
# dispatch, and the "fail loudly on malformed input" contract.
set -eufo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
# shellcheck source=/dev/null
. "${ROOT}/dot_claude/skills/_shared/executable_assert.sh"
LAUNCHER="${ROOT}/dot_claude/skills/cmux-orchestrator/scripts/executable_launch-workers.sh"
PREPARE="${ROOT}/dot_claude/skills/cmux-orchestrator/scripts/executable_prepare-run.sh"
MONITOR="${ROOT}/dot_claude/skills/cmux-orchestrator/scripts/executable_monitor-workers.sh"
TEMPLATE="${ROOT}/dot_claude/skills/cmux-orchestrator/templates/system-prompt.txt"
SKILL_MD="${ROOT}/dot_claude/skills/cmux-orchestrator/SKILL.md"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ─── cmux stub: logs argv faithfully, returns canned pane/surface JSON ────
# Exit code 97 on any subcommand the launcher doesn't actually use, so a
# stub malfunction is never confused with a real assertion failure below.
CMUX_STUB="${WORK}/stub-src/cmux"
mkdir -p "${WORK}/stub-src"
cat >"$CMUX_STUB" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
: "${CMUX_STUB_LOG:?}"
: "${CMUX_STUB_STATE:?}"
STUB_FAIL=97

{
  printf 'ARGV'
  for a in "$@"; do printf '\x1f%s' "$a"; done
  printf '\n'
} >>"$CMUX_STUB_LOG"

next_ref() {
  local kind="$1"
  local counter_file="${CMUX_STUB_STATE}/${kind}-counter"
  local n
  n=$(cat "$counter_file" 2>/dev/null || echo 0)
  echo $((n + 1)) >"$counter_file"
  echo "${kind}:${n}"
}

case "${1:-}" in
  identify)
    echo '{"ok":true}'
    ;;
  --json)
    case "${2:-}" in
      new-pane)
        PANE=$(next_ref pane)
        SURFACE=$(next_ref surface)
        printf '{"pane_ref":"%s","surface_ref":"%s"}\n' "$PANE" "$SURFACE"
        ;;
      new-surface)
        SURFACE=$(next_ref surface)
        printf '{"surface_ref":"%s"}\n' "$SURFACE"
        ;;
      *)
        echo "cmux-stub: unknown --json subcommand: ${2:-}" >&2
        exit "$STUB_FAIL"
        ;;
    esac
    ;;
  send | rename-tab)
    : # argv already logged above; nothing else the launcher needs back
    ;;
  *)
    echo "cmux-stub: unknown subcommand: ${1:-}" >&2
    exit "$STUB_FAIL"
    ;;
esac
STUB
chmod +x "$CMUX_STUB"

noop_bin() {
  # $1 = path to create; a placeholder binary that satisfies `command -v`
  # preflight checks but is never actually executed (launching happens by
  # typing text into a cmux pane, not by running claude/codex in this test).
  printf '#!/usr/bin/env bash\nexit 0\n' >"$1"
  chmod +x "$1"
}

# Each bin dir is run with PATH="<dir>:/usr/bin:/bin" (see run_launcher) —
# a minimal base, deliberately NOT the test runner's real $PATH, so a
# "codex/claude missing" scenario is actually missing rather than falling
# through to whatever the developer machine happens to have installed.
# jq is a real launcher dependency (parses cmux's JSON), so a real jq is
# symlinked into every bin dir; claude/codex are noop placeholders added
# only where that runner's preflight is meant to succeed.
REAL_JQ=$(command -v jq)

BIN_ALL="${WORK}/bin-all"
BIN_NO_CODEX="${WORK}/bin-no-codex"
BIN_NO_CLAUDE="${WORK}/bin-no-claude"
mkdir -p "$BIN_ALL" "$BIN_NO_CODEX" "$BIN_NO_CLAUDE"
for d in "$BIN_ALL" "$BIN_NO_CODEX" "$BIN_NO_CLAUDE"; do
  ln -s "$CMUX_STUB" "${d}/cmux"
  ln -s "$REAL_JQ" "${d}/jq"
done
noop_bin "${BIN_ALL}/claude"
noop_bin "${BIN_ALL}/codex"
noop_bin "${BIN_NO_CODEX}/claude"
noop_bin "${BIN_NO_CLAUDE}/codex"

RUN_DIR="${WORK}/run"
mkdir -p "$RUN_DIR"
echo "you are a worker" >"${RUN_DIR}/system-prompt.txt"

CWD="${WORK}/cwd"
mkdir -p "$CWD"

LOG="${WORK}/cmux.log"
OUT="${WORK}/launcher.out"
ERR="${WORK}/launcher.err"

# run_launcher BIN_DIR ARGS... — runs the launcher with a fresh log/state and
# PATH="<BIN_DIR>:/usr/bin:/bin" (cmux/claude/codex/jq resolve to whatever
# BIN_DIR provides — never the test runner's own $PATH, so a "codex is
# missing" scenario can't accidentally find a real codex elsewhere).
# Stdout -> $OUT, stderr -> $ERR, exit code returned.
run_launcher() {
  local bin_dir="$1"
  shift
  : >"$LOG"
  local state
  state=$(mktemp -d)
  local rc=0
  PATH="${bin_dir}:/usr/bin:/bin" CMUX_STUB_LOG="$LOG" CMUX_STUB_STATE="$state" \
    LAUNCH_WORKERS_INIT_DELAY=0 \
    "$LAUNCHER" "$@" >"$OUT" 2>"$ERR" || rc=$?
  rm -rf "$state"
  return "$rc"
}

# ─── Step 1 / brief assertions: bare spec, claude triple, codex triple, ───
# codex effort — all through one real launcher invocation.
# (`|| LAUNCHER_RC=$?` guards each call below against `set -e`: several of
# these are expected to fail, and a bare failing statement would abort this
# test script before its exit code could be inspected.)
LAUNCHER_RC=0
run_launcher "$BIN_ALL" "$RUN_DIR" "$CWD" legacy backend:claude:opus@high frontend:codex:gpt-5.6-terra@high || LAUNCHER_RC=$?
assert_eq "$LAUNCHER_RC" 0 "well-formed multi-spec run exits 0"
LOG_TEXT=$(cat "$LOG")
assert_contains "$LOG_TEXT" 'claude --model sonnet' "bare spec"
assert_contains "$LOG_TEXT" 'claude --model opus' "claude triple"
assert_contains "$LOG_TEXT" 'codex --model gpt-5.6-terra' "codex triple"
assert_contains "$LOG_TEXT" 'model_reasoning_effort="high"' "codex effort"
assert_contains "$LOG_TEXT" '--effort high' "claude effort: --effort flag is present when effort is set"

# ─── Backward compatibility: bare names still mean claude+sonnet, and the ──
# emitted JSON keeps pane_ref + a per-worker surface_ref (shape unchanged,
# with `runner` now added alongside `name`).
OUT_JSON=$(cat "$OUT")
assert_eq "$(jq -r '.pane_ref' <<<"$OUT_JSON")" "pane:0" "JSON keeps pane_ref"
assert_eq "$(jq '.workers | length' <<<"$OUT_JSON")" 3 "JSON has one entry per worker"
assert_eq "$(jq -r '.workers[0].name' <<<"$OUT_JSON")" "legacy" "bare spec's parsed name is the bare string"
assert_eq "$(jq -r '.workers[0].runner' <<<"$OUT_JSON")" "claude" "bare spec's runner defaults to claude"
assert_eq "$(jq '[.workers[].surface_ref] | all(type == "string" and length > 0)' <<<"$OUT_JSON")" \
  "true" "every worker keeps a non-empty surface_ref"

# ─── Content-level check: the no-effort grammar (`name:runner:model`, no ──
# `@effort`) must omit the effort flag entirely for BOTH runners, not emit
# it empty. Regression test for a codex-branch bug where
# `-c model_reasoning_effort="${effort}"` was always appended even when
# effort was unset, producing `model_reasoning_effort=""` — an empty
# string spliced into an enum-typed override that a real codex CLI would
# likely reject. The claude branch already guarded this with
# `if [ -n "$effort" ]`; the codex branch did not.
NOEFFORT_RC=0
run_launcher "$BIN_ALL" "$RUN_DIR" "$CWD" w-codex:codex:gpt-5 w-claude:claude:opus || NOEFFORT_RC=$?
assert_eq "$NOEFFORT_RC" 0 "no-effort multi-runner run exits 0"
NOEFFORT_LOG=$(cat "$LOG")
assert_contains "$NOEFFORT_LOG" 'codex --model gpt-5' "codex no-effort: command still launches with the right model"
HAS_REASONING_EFFORT="no"
case "$NOEFFORT_LOG" in *model_reasoning_effort*) HAS_REASONING_EFFORT="yes" ;; esac
assert_eq "$HAS_REASONING_EFFORT" "no" "codex no-effort: model_reasoning_effort flag is omitted, not emitted empty"
assert_contains "$NOEFFORT_LOG" 'claude --model opus' "claude no-effort: command still launches with the right model"
HAS_CLAUDE_EFFORT="no"
case "$NOEFFORT_LOG" in *'--effort'*) HAS_CLAUDE_EFFORT="yes" ;; esac
assert_eq "$HAS_CLAUDE_EFFORT" "no" "claude no-effort: --effort flag is omitted"

# ─── parse_spec is unit-testable via LAUNCH_WORKERS_LIB_ONLY, no cmux ──────
# needed at all.

# parse_case SPEC — sources the launcher with LAUNCH_WORKERS_LIB_ONLY=1 in a
# clean environment (no cmux, claude, or codex on PATH) and runs parse_spec
# on SPEC. Exit status is parse_spec's; used with assert_exit.
parse_case() {
  env -i PATH="/usr/bin:/bin" LAUNCH_WORKERS_LIB_ONLY=1 \
    bash -c '. "$1"; parse_spec "$2"' _ "$LAUNCHER" "$1"
}

# parse_case_stderr SPEC — same, but captures stderr for diagnostic checks.
# (parse_spec never writes to stdout, so a plain `2>&1` merge is enough —
# no need for the discard-stdout swap trick.)
parse_case_stderr() {
  env -i PATH="/usr/bin:/bin" LAUNCH_WORKERS_LIB_ONLY=1 \
    bash -c '. "$1"; parse_spec "$2"' _ "$LAUNCHER" "$1" 2>&1 || true
}

# parse_case_values SPEC — same, prints "name|runner|model|effort" on success.
parse_case_values() {
  env -i PATH="/usr/bin:/bin" LAUNCH_WORKERS_LIB_ONLY=1 \
    bash -c '. "$1"; parse_spec "$2"; printf "%s|%s|%s|%s" "$name" "$runner" "$model" "$effort"' \
    _ "$LAUNCHER" "$1"
}

# Sourcing with the guard set requires nothing beyond bash — no positional
# args, no cmux, no claude/codex — proving the guard short-circuits before
# argument validation and before any cmux call.
assert_exit 0 env -i PATH="/usr/bin:/bin" LAUNCH_WORKERS_LIB_ONLY=1 \
  bash -c '. "$1"' _ "$LAUNCHER"

assert_eq "$(parse_case_values legacy)" "legacy|claude|sonnet|" \
  "parse_spec: bare name -> claude/sonnet/no effort"
assert_eq "$(parse_case_values backend:claude:opus@high)" "backend|claude|opus|high" \
  "parse_spec: claude triple with effort"
assert_eq "$(parse_case_values frontend:codex:gpt-5.6-terra@high)" "frontend|codex|gpt-5.6-terra|high" \
  "parse_spec: codex triple with effort"
assert_eq "$(parse_case_values worker:claude:sonnet)" "worker|claude|sonnet|" \
  "parse_spec: explicit triple with no effort"

# ─── Malformed specs must fail loudly (diagnostic + non-zero exit), never ──
# parse into a well-formed launch of the wrong thing.

assert_exit 1 parse_case "name:python:foo"
assert_contains "$(parse_case_stderr name:python:foo)" "unknown runner" \
  "unknown runner names the bad runner"

assert_exit 1 parse_case "name::model"
assert_contains "$(parse_case_stderr name::model)" "empty" \
  "empty runner field is rejected, not silently defaulted"

assert_exit 1 parse_case ":claude:sonnet"
assert_contains "$(parse_case_stderr :claude:sonnet)" "empty" \
  "empty name field is rejected"

assert_exit 1 parse_case "name:claude:opus:extra"
assert_contains "$(parse_case_stderr name:claude:opus:extra)" "too many colons" \
  "too many colons is rejected"

assert_exit 1 parse_case "name:claude:opus@"
assert_contains "$(parse_case_stderr name:claude:opus@)" "empty effort" \
  "trailing @ with no effort is rejected"

assert_exit 1 parse_case "name:claude:opus@ultra"
assert_contains "$(parse_case_stderr name:claude:opus@ultra)" "unknown effort" \
  "an effort outside the known levels is rejected"

assert_exit 1 parse_case "name:claude:@high"
assert_contains "$(parse_case_stderr name:claude:@high)" "empty model" \
  "empty model field is rejected"

# ─── Preflight: codex is only required when a codex spec is present, and ──
# likewise for claude — a single-runner run must not need the other CLI.

NO_CODEX_RC=0
run_launcher "$BIN_NO_CODEX" "$RUN_DIR" "$CWD" solo || NO_CODEX_RC=$?
assert_eq "$NO_CODEX_RC" 0 "claude-only run succeeds without codex on PATH"

NO_CLAUDE_RC=0
run_launcher "$BIN_NO_CLAUDE" "$RUN_DIR" "$CWD" solo:codex:gpt-5.6-terra || NO_CLAUDE_RC=$?
assert_eq "$NO_CLAUDE_RC" 0 "codex-only run succeeds without claude on PATH"

CODEX_MISSING_RC=0
run_launcher "$BIN_NO_CODEX" "$RUN_DIR" "$CWD" solo:codex:gpt-5.6-terra || CODEX_MISSING_RC=$?
assert_eq "$CODEX_MISSING_RC" 1 "a codex spec without codex on PATH fails"
assert_contains "$(cat "$ERR")" "codex CLI not found" \
  "missing-codex diagnostic names codex"

CLAUDE_MISSING_RC=0
run_launcher "$BIN_NO_CLAUDE" "$RUN_DIR" "$CWD" solo || CLAUDE_MISSING_RC=$?
assert_eq "$CLAUDE_MISSING_RC" 1 "a bare (claude) spec without claude on PATH fails"
assert_contains "$(cat "$ERR")" "claude CLI not found" \
  "missing-claude diagnostic names claude"

# ─── Quoting: a worker name or cwd containing a space must round-trip ─────
# through `cmux send` unbroken, not just avoid a crash.

SPACE_CWD="${WORK}/dir with spaces"
mkdir -p "$SPACE_CWD"
SPACE_RC=0
run_launcher "$BIN_ALL" "$RUN_DIR" "$SPACE_CWD" "solo person:claude:opus@high" || SPACE_RC=$?
assert_eq "$SPACE_RC" 0 "a worker name and cwd containing spaces do not break the launch"

# Pull the exact text handed to `cmux send` for that worker and replay it
# through a real shell with `claude` overridden to dump its argv — proving
# the %q-quoting reconstructs the original name/cwd, not a fresh test that
# merely re-derives what the script already believes.
SEND_TEXT=""
while IFS= read -r line; do
  case "$line" in
    $'ARGV\x1fsend'*)
      declare -a fields=()
      IFS=$'\x1f' read -ra fields <<<"$line"
      SEND_TEXT="${fields[$((${#fields[@]} - 1))]}"
      break
      ;;
  esac
done <"$LOG"
SEND_TEXT="${SEND_TEXT%\\n}"

REPLAY=$(bash -c '
  set -e
  claude() { printf "PWD=%s\x1f" "$PWD"; for a in "$@"; do printf "%s\x1f" "$a"; done; }
  eval "$1"
' _ "$SEND_TEXT")
declare -a REPLAY_FIELDS=()
IFS=$'\x1f' read -ra REPLAY_FIELDS <<<"$REPLAY"
REPLAY_PWD="${REPLAY_FIELDS[0]#PWD=}"
REPLAY_NAME=""
for ((i = 0; i < ${#REPLAY_FIELDS[@]}; i++)); do
  if [ "${REPLAY_FIELDS[i]}" = "--name" ]; then
    REPLAY_NAME="${REPLAY_FIELDS[$((i + 1))]}"
    break
  fi
done
assert_eq "$REPLAY_PWD" "$SPACE_CWD" "cwd with a space round-trips through cmux send"
assert_eq "$REPLAY_NAME" "solo person" "worker name with a space round-trips through cmux send"

# ─── prepare-run.sh: fixed scaffolding, RUN_DIR CWD ORCH_SURFACE SPEC... ───
# Reuses launch-workers.sh's parse_spec (same SPEC grammar) rather than a
# second parser, so a malformed spec fails the same way through both
# scripts — proven below, not just asserted in a comment.

PREP_WORK=$(mktemp -d)
PREP_RUN="${PREP_WORK}/run"
PREP_CWD="${PREP_WORK}/cwd"
mkdir -p "$PREP_RUN" "$PREP_CWD"

PREP_RC=0
"$PREPARE" "$PREP_RUN" "$PREP_CWD" "surface:orch" auth-refactor add-tests \
  >"${PREP_WORK}/prepare.out" 2>"${PREP_WORK}/prepare.err" || PREP_RC=$?
assert_eq "$PREP_RC" 0 "prepare-run.sh: two specs exits 0"

assert_exit 0 test -f "${PREP_RUN}/system-prompt.txt"
assert_exit 0 test -f "${PREP_RUN}/worker-auth-refactor.prompt.md"
assert_exit 0 test -f "${PREP_RUN}/worker-add-tests.prompt.md"
assert_exit 0 test -f "${PREP_RUN}/worker-auth-refactor.result.md"
assert_exit 0 test -f "${PREP_RUN}/worker-add-tests.result.md"

MANIFEST_JSON=$(cat "${PREP_RUN}/manifest.json")
assert_eq "$(jq '.workers | length' <<<"$MANIFEST_JSON")" 2 \
  "prepare-run.sh: manifest.json has one entry per spec"
assert_eq "$(jq -r '.worker_pane_ref' <<<"$MANIFEST_JSON")" "null" \
  "prepare-run.sh: manifest.json worker_pane_ref starts null (not launched yet)"
assert_eq "$(jq -c '[.workers[].name] | sort' <<<"$MANIFEST_JSON")" \
  '["add-tests","auth-refactor"]' \
  "prepare-run.sh: manifest.json worker names match the specs"
assert_eq "$(jq -r '.workers[0].status' <<<"$MANIFEST_JSON")" "pending" \
  "prepare-run.sh: a fresh worker's status is pending"
assert_eq "$(jq -r '.workers[0].prompt_file' <<<"$MANIFEST_JSON")" \
  "${PREP_RUN}/worker-auth-refactor.prompt.md" \
  "prepare-run.sh: manifest.json prompt_file is the real path prepare-run.sh wrote"
assert_eq "$(jq -r '.cwd' <<<"$MANIFEST_JSON")" "$PREP_CWD" \
  "prepare-run.sh: manifest.json records the cwd argument"
assert_eq "$(jq -r '.orchestrator_surface' <<<"$MANIFEST_JSON")" "surface:orch" \
  "prepare-run.sh: manifest.json records the orchestrator surface argument"

PROMPT_TEXT=$(cat "${PREP_RUN}/worker-auth-refactor.prompt.md")
assert_contains "$PROMPT_TEXT" "Done marker: ${PREP_RUN}/worker-auth-refactor.done" \
  "prepare-run.sh: prompt file names the real done-marker path, not a placeholder"
assert_contains "$PROMPT_TEXT" "<Detailed task description" \
  "prepare-run.sh: prompt file leaves the Task section as a judgement placeholder"

# ─── Idempotence: re-running with the same args leaves every file byte- ───
# identical — hashed, not just re-checked for exit 0 (exit 0 alone would
# pass even if manifest.json's created_at silently drifted with `date`).
HASH_BEFORE=$(find "$PREP_RUN" -type f -exec sha256sum {} \; | sort)
PREP_RC2=0
"$PREPARE" "$PREP_RUN" "$PREP_CWD" "surface:orch" auth-refactor add-tests \
  >/dev/null 2>&1 || PREP_RC2=$?
assert_eq "$PREP_RC2" 0 "prepare-run.sh: re-run with identical args exits 0"
HASH_AFTER=$(find "$PREP_RUN" -type f -exec sha256sum {} \; | sort)
assert_eq "$HASH_AFTER" "$HASH_BEFORE" \
  "prepare-run.sh: re-run leaves every file byte-identical (hash comparison, not just exit code)"

# ─── Re-running must not clobber a prompt file the orchestrator has since ──
# hand-edited to replace the placeholder judgement sections with real task
# content — a second prepare-run.sh call (e.g. adding a worker) has to
# leave that edit alone.
{
  echo "## Task"
  echo "Refactor the auth middleware to use JWT."
} >>"${PREP_RUN}/worker-auth-refactor.prompt.md"
EDITED_HASH=$(sha256sum "${PREP_RUN}/worker-auth-refactor.prompt.md")
"$PREPARE" "$PREP_RUN" "$PREP_CWD" "surface:orch" auth-refactor add-tests api-docs \
  >/dev/null 2>&1
assert_eq "$(sha256sum "${PREP_RUN}/worker-auth-refactor.prompt.md")" "$EDITED_HASH" \
  "prepare-run.sh: adding a third worker does not touch an already hand-edited prompt file"
assert_exit 0 test -f "${PREP_RUN}/worker-api-docs.prompt.md"

rm -rf "$PREP_WORK"

# ─── --system-prompt FILE overrides the packaged template verbatim ────────
PREP_WORK2=$(mktemp -d)
CUSTOM_PROMPT="${PREP_WORK2}/custom-system-prompt.txt"
echo "custom system prompt content" >"$CUSTOM_PROMPT"
"$PREPARE" "${PREP_WORK2}/run" "${PREP_WORK2}/cwd" "surface:1" \
  --system-prompt "$CUSTOM_PROMPT" solo >/dev/null 2>&1
assert_eq "$(cat "${PREP_WORK2}/run/system-prompt.txt")" "custom system prompt content" \
  "prepare-run.sh: --system-prompt FILE overrides the packaged template"
rm -rf "$PREP_WORK2"

# ─── Malformed specs fail the same way as launch-workers.sh — same parser, ─
# same failure mode, because prepare-run.sh reuses parse_spec rather than
# re-implementing the grammar.
PREP_WORK3=$(mktemp -d)
mkdir -p "${PREP_WORK3}/run" "${PREP_WORK3}/cwd"
BAD_RC=0
"$PREPARE" "${PREP_WORK3}/run" "${PREP_WORK3}/cwd" "surface:1" "name:python:foo" \
  >/dev/null 2>"${PREP_WORK3}/err" || BAD_RC=$?
assert_eq "$BAD_RC" 1 "prepare-run.sh: a malformed spec fails (same grammar as launch-workers.sh)"
assert_contains "$(cat "${PREP_WORK3}/err")" "unknown runner" \
  "prepare-run.sh: malformed-spec diagnostic comes from the shared parse_spec, not a second parser"
rm -rf "$PREP_WORK3"

# ─── Usage errors: missing SPEC is a clean exit 2, not a crash mid-script ──
# (--system-prompt FILE consumes the only extra token, leaving zero SPECs —
# this exercises the specific "no SPEC" diagnostic, not the coarser
# too-few-args guard that a bare 3-arg call would hit instead.)
PREP_WORK4=$(mktemp -d)
mkdir -p "${PREP_WORK4}/run" "${PREP_WORK4}/cwd"
echo "prompt" >"${PREP_WORK4}/sp.txt"
NOSPEC_RC=0
"$PREPARE" "${PREP_WORK4}/run" "${PREP_WORK4}/cwd" "surface:1" \
  --system-prompt "${PREP_WORK4}/sp.txt" \
  >/dev/null 2>"${PREP_WORK4}/err" || NOSPEC_RC=$?
assert_eq "$NOSPEC_RC" 2 "prepare-run.sh: no worker SPEC given exits 2"
assert_contains "$(cat "${PREP_WORK4}/err")" "at least one worker SPEC required" \
  "prepare-run.sh: missing-spec diagnostic names the problem"
rm -rf "$PREP_WORK4"

# ─── monitor-workers.sh: blocks until done/blocked/crashed/failed, then ───
# emits exactly one trigger JSON and exits — content-level assertions, not
# just "it produced output".

MON_WORK=$(mktemp -d)
mkdir -p "${MON_WORK}/run"
cat >"${MON_WORK}/run/manifest.json" <<EOF
{"workers":[{"name":"w1","done_marker":"${MON_WORK}/run/w1.done","surface_ref":"surface:1"}]}
EOF

echo "done" >"${MON_WORK}/run/w1.done"
DONE_JSON=$("$MONITOR" "${MON_WORK}/run")
assert_eq "$(jq -r '.type' <<<"$DONE_JSON")" "done" \
  "monitor-workers.sh: a done marker produces a done trigger"
assert_eq "$(jq -r '.worker' <<<"$DONE_JSON")" "w1" \
  "monitor-workers.sh: done trigger names the worker"
rm -f "${MON_WORK}/run/w1.done"

echo "blocked: needs human review" >"${MON_WORK}/run/w1.done"
BLOCKED_JSON=$("$MONITOR" "${MON_WORK}/run")
assert_eq "$(jq -r '.type' <<<"$BLOCKED_JSON")" "blocked" \
  "monitor-workers.sh: a 'blocked: ...' marker produces a blocked trigger"
assert_eq "$(jq -r '.reason' <<<"$BLOCKED_JSON")" "needs human review" \
  "monitor-workers.sh: blocked trigger's reason strips the 'blocked: ' prefix"
rm -f "${MON_WORK}/run/w1.done"

# cmux stub for the liveness path: capture-pane always fails (vanished pane)
MON_BIN_CRASH="${MON_WORK}/bin-crash"
mkdir -p "$MON_BIN_CRASH"
cat >"${MON_BIN_CRASH}/cmux" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "${MON_BIN_CRASH}/cmux"
CRASHED_JSON=$(PATH="${MON_BIN_CRASH}:${PATH}" MONITOR_LIVENESS_INTERVAL=0 MONITOR_POLL_INTERVAL=1 MONITOR_MAX_WAIT=5 "$MONITOR" "${MON_WORK}/run")
assert_eq "$(jq -r '.type' <<<"$CRASHED_JSON")" "crashed" \
  "monitor-workers.sh: a vanished pane (capture-pane fails) produces a crashed trigger"
assert_contains "$(jq -r '.reason' <<<"$CRASHED_JSON")" "pane vanished" \
  "monitor-workers.sh: crashed trigger's reason says the pane vanished"

# cmux stub for the liveness path: capture-pane succeeds but the pane log
# contains a fatal signature
MON_BIN_FATAL="${MON_WORK}/bin-fatal"
mkdir -p "$MON_BIN_FATAL"
cat >"${MON_BIN_FATAL}/cmux" <<'STUB'
#!/usr/bin/env bash
echo "some ordinary output"
echo "panic: something exploded"
exit 0
STUB
chmod +x "${MON_BIN_FATAL}/cmux"
FAILED_RC=0
FAILED_JSON=$(PATH="${MON_BIN_FATAL}:${PATH}" MONITOR_LIVENESS_INTERVAL=0 MONITOR_POLL_INTERVAL=1 MONITOR_MAX_WAIT=5 "$MONITOR" "${MON_WORK}/run") || FAILED_RC=$?
assert_eq "$(jq -r '.type' <<<"$FAILED_JSON")" "failed" \
  "monitor-workers.sh: a fatal signature in the pane log produces a failed trigger"
assert_contains "$(jq -r '.reason' <<<"$FAILED_JSON")" "panic: something exploded" \
  "monitor-workers.sh: failed trigger's reason quotes the matched fatal-signature line"
assert_eq "$FAILED_RC" 0 \
  "monitor-workers.sh: a fatal-signature failed trigger still exits 0 — the monitor did its job of detecting and reporting it"

# ─── Bounded wait: exhausting MAX_WAIT with no marker and no pane to check ─
# still emits a trigger — the "never hang, never report success by
# silence" requirement — rather than blocking forever. This is the one
# case that exits nonzero: the monitor itself found nothing to report.
mkdir -p "${MON_WORK}/run2"
cat >"${MON_WORK}/run2/manifest.json" <<EOF
{"workers":[{"name":"w1","done_marker":"${MON_WORK}/run2/w1.done","surface_ref":""}]}
EOF
TIMEOUT_RC=0
TIMEOUT_JSON=$(MONITOR_MAX_WAIT=0 "$MONITOR" "${MON_WORK}/run2") || TIMEOUT_RC=$?
assert_eq "$(jq -r '.type' <<<"$TIMEOUT_JSON")" "failed" \
  "monitor-workers.sh: exhausting the bound with nothing detected still emits a trigger, not a hang"
assert_contains "$(jq -r '.reason' <<<"$TIMEOUT_JSON")" "timeout" \
  "monitor-workers.sh: the bound-exceeded trigger's reason says timeout"
assert_eq "$TIMEOUT_RC" 1 \
  "monitor-workers.sh: the bound-exceeded trigger is the one case that exits nonzero"

# ─── The fatal-signature regex itself is pinned so a future edit can't ────
# quietly narrow what counts as fatal without this test noticing.
MONITOR_TEXT=$(cat "$MONITOR")
assert_contains "$MONITOR_TEXT" \
  'panic|fatal|segmentation fault|killed|traceback|unhandled|command not found|permission denied' \
  "monitor-workers.sh: the fatal-signature regex is the full agreed set, not a narrowed subset"

rm -rf "$MON_WORK"

# ─── SKILL.md: Phase 2 scaffolding and Phase 4 polling loop were replaced ──
# with prepare-run.sh / monitor-workers.sh calls, and the file is under the
# 351-line ceiling — a proxy that's easy to satisfy by deleting rules
# instead of extracting scripts, so the assertions below pin the load-
# bearing RULES this project has already lost to line-count pressure once
# (see deep-plan/tests/executable_test-deep-plan.sh, "Task 6" — the two
# checks above only prove SKILL.md got shorter and mentions the new
# scripts; every other rule in the file could be deleted and they'd stay
# green). Extend THIS block, not the line-count check, if a future task
# slims this file again.

assert_eq "$([ "$(wc -l <"$SKILL_MD" | tr -d ' ')" -lt 351 ] && echo yes || echo no)" yes \
  "SKILL.md: line count is under the 351-line ceiling"
SKILL_MD_TEXT=$(cat "$SKILL_MD")
assert_contains "$SKILL_MD_TEXT" "prepare-run.sh" \
  "SKILL.md: Phase 2 points at prepare-run.sh for the fixed scaffolding"
assert_contains "$SKILL_MD_TEXT" "monitor-workers.sh" \
  "SKILL.md: Phase 4's polling loop points at monitor-workers.sh"
NOT_CONTAINS_OLD_HEREDOC="yes"
case "$SKILL_MD_TEXT" in
  *"You are a worker agent in a cmux parallel orchestration."*) NOT_CONTAINS_OLD_HEREDOC="no" ;;
esac
assert_eq "$NOT_CONTAINS_OLD_HEREDOC" "yes" \
  "SKILL.md: the system-prompt heredoc was moved to templates/system-prompt.txt, not duplicated"

assert_contains "$SKILL_MD_TEXT" "Never create sessions before the plan is approved by the user." \
  "SKILL.md: must-survive — plan approval gate"
assert_contains "$SKILL_MD_TEXT" 'ALWAYS use the `launch-workers.sh` script' \
  "SKILL.md: must-survive — always use launch-workers.sh"
assert_contains "$SKILL_MD_TEXT" 'Do NOT manually run `cmux send`' \
  "SKILL.md: must-survive — do not manually run cmux send (Phase 3)"
assert_contains "$SKILL_MD_TEXT" 'NEVER use raw `cmux send` directly' \
  "SKILL.md: must-survive — never use raw cmux send (idle worker reuse)"
assert_contains "$SKILL_MD_TEXT" "Never clean up automatically." \
  "SKILL.md: must-survive — no automatic cleanup"
assert_contains "$SKILL_MD_TEXT" "Maximum 6 concurrent workers" \
  "SKILL.md: must-survive — worker concurrency cap"
assert_contains "$SKILL_MD_TEXT" "Never parallelize dependent tasks" \
  "SKILL.md: must-survive — serialize dependent tasks"
assert_contains "$SKILL_MD_TEXT" "Workers must not exit" \
  "SKILL.md: must-survive — workers stay in interactive mode"

# ─── templates/system-prompt.txt: verbatim wording pins — this is what ────
# every worker is told; a silent edit changes every future worker's
# behavior. A full-file diff against the original heredoc is done by hand
# at commit time; these pin the opening and closing lines so an automated
# regression is caught here too.
TEMPLATE_TEXT=$(cat "$TEMPLATE")
assert_contains "$TEMPLATE_TEXT" "You are a worker agent in a cmux parallel orchestration." \
  "templates/system-prompt.txt: opening line survived the extraction verbatim"
assert_contains "$TEMPLATE_TEXT" "Handle errors explicitly at every level" \
  "templates/system-prompt.txt: closing line survived the extraction verbatim"

assert_summary
