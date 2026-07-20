#!/usr/bin/env bash
# Tests for launch-workers.sh's `name:runner:model@effort` worker-spec
# grammar: backward compatibility with bare names, the claude/codex runner
# dispatch, and the "fail loudly on malformed input" contract.
set -eufo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
# shellcheck source=/dev/null
. "${ROOT}/dot_claude/skills/_shared/executable_assert.sh"
LAUNCHER="${ROOT}/dot_claude/skills/cmux-orchestrator/scripts/executable_launch-workers.sh"

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

assert_summary
