#!/usr/bin/env bash
set -eufo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
# shellcheck source=/dev/null
. "${ROOT}/dot_claude/skills/_shared/executable_assert.sh"
SCHEMA="${ROOT}/dot_claude/skills/deep-execute/schemas/run-state.schema.json"

assert_exit 0 test -f "$SCHEMA"
# shellcheck disable=SC2016  # $schema is a literal jq key, not a shell expansion
assert_exit 0 jq -e '
  .["$schema"] == "https://json-schema.org/draft/2020-12/schema" and
  (.properties.manifest.required | index("baseline_commit")) != null and
  .properties.event.properties.type.enum == [
    "task_start", "task_done", "progress", "question", "waiting", "blocked", "done"
  ]
' "$SCHEMA"

ALLOW="${ROOT}/dot_claude/skills/deep-execute/agents.allowlist"
assert_exit 0 test -f "$ALLOW"
assert_exit 0 grep -qx 'opus high' "$ALLOW"
assert_exit 0 grep -qx 'codex gpt-5.6-terra high' "$ALLOW"

# ─── End-to-end handoff: fixture parallel plan through validate-plan.sh, ───
# init-run.sh, validate-contract.sh and validate-run-state.sh — the same
# chain a real /deep-execute run walks before any worker launches. No real
# agent may launch here: cmux/claude/codex/reviewer are stubbed on PATH and
# the stub call log is asserted empty at the end, so a future change that
# accidentally starts eagerly invoking one of them fails this test instead
# of silently starting a real agent.

VALIDATE_PLAN="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_validate-plan.sh"
INVOKE="${ROOT}/dot_claude/skills/deep-plan/scripts/executable_superpowers-invoke.sh"
INIT_RUN="${ROOT}/dot_claude/skills/deep-execute/scripts/executable_init-run.sh"
VALIDATE_CONTRACT="${ROOT}/dot_claude/skills/deep-execute/scripts/executable_validate-contract.sh"
VALIDATE_STATE="${ROOT}/dot_claude/skills/deep-execute/scripts/executable_validate-run-state.sh"
FIXTURE_PLAN="${ROOT}/dot_claude/skills/deep-plan/tests/fixtures/valid-parallel-plan.md"
CODEINTEL_FIXTURE="${ROOT}/dot_claude/skills/deep-execute/tests/fixtures/codeintel-status.json"

assert_exit 0 test -f "$VALIDATE_PLAN"
assert_exit 0 test -f "$INVOKE"
assert_exit 0 test -f "$INIT_RUN"
assert_exit 0 test -f "$VALIDATE_CONTRACT"
assert_exit 0 test -f "$VALIDATE_STATE"
assert_exit 0 test -f "$FIXTURE_PLAN"
assert_exit 0 test -f "$CODEINTEL_FIXTURE"

STUB_BIN=$(mktemp -d)
STUB_LOG="${STUB_BIN}/calls.log"
: >"$STUB_LOG"
for stub in cmux claude codex reviewer; do
  cat >"${STUB_BIN}/${stub}" <<STUBEOF
#!/usr/bin/env bash
echo "${stub} \$*" >>"${STUB_LOG}"
exit 1
STUBEOF
  chmod +x "${STUB_BIN}/${stub}"
done
PATH="${STUB_BIN}:${PATH}"
export PATH

# A real, throwaway git repo shaped exactly like the fixture plan's own
# layout: justfile/README.md/src/shared/contract.schema.json are shared and
# orchestrator-owned; src/planning|execution|review/** are each owned by one
# worker lane. The fixture's own "paths under src/ are illustrative" note
# (Global Constraints) means these must be created here — init-run.sh
# refuses to start if the contract or any shared file is missing or
# uncommitted, which the real chezmoi repo does not have on disk.
REPO=$(mktemp -d)
RUN_DIR="$(mktemp -d)/run"
PLAN_SCRATCH=$(mktemp -d)
trap 'rm -rf "$REPO" "$RUN_DIR" "$STUB_BIN" "$PLAN_SCRATCH"' EXIT

git -C "$REPO" init --quiet -b main
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "deep-execute integration test"
mkdir -p "$REPO/src/shared" "$REPO/src/planning" "$REPO/src/execution" "$REPO/src/review"
printf 'test:\n\t@echo ok\n' >"$REPO/justfile"
printf '# readme\n' >"$REPO/README.md"
printf '{"type":"object"}\n' >"$REPO/src/shared/contract.schema.json"
printf '#!/usr/bin/env bash\n' >"$REPO/src/planning/parser.sh"
printf '#!/usr/bin/env bash\n' >"$REPO/src/execution/runner.sh"
printf '#!/usr/bin/env bash\n' >"$REPO/src/review/checklist.sh"
git -C "$REPO" add -A
git -C "$REPO" commit --quiet -m init

# ─── Step 1a: build a genuinely --root-complete plan from the fixture ──────
# valid-parallel-plan.md's own Goal states it exists to "exercise a 4-lane
# parallel execution shape and API contract for plan-to-json.sh and the lane
# validators" — it was never written to satisfy validate-plan.sh's full
# document-completeness checklist (mermaid diagram, TDD/edge-case lists,
# decision log, subplans, rationale, docs/QA flags, code-intel marker,
# receipted superpowers ticks), and init-run.sh calls validate-plan.sh
# --root unconditionally and refuses to start on ANY failing item — not just
# the lane/contract subset. So this test grows a real, throwaway copy of the
# fixture into a fully-passing plan (never touching the checked-in fixture
# file itself) — the same shape a genuinely approved plan reaching
# /deep-execute would have.
PLAN="${PLAN_SCRATCH}/plan.md"
cp "$FIXTURE_PLAN" "$PLAN"
cp "$CODEINTEL_FIXTURE" "${PLAN_SCRATCH}/codeintel-status.json"
mkdir -p "${PLAN_SCRATCH}/subplans"
cat >"${PLAN_SCRATCH}/subplans/planning.md" <<'SUBPLANEOF'
# Planning lane subplan

```mermaid
sequenceDiagram
  participant Orchestrator
  participant Planning
  Orchestrator->>Planning: assign task
  Planning-->>Orchestrator: progress
  Planning-->>Orchestrator: done
```

## TDD test list

- `parser normalizes rows` — real parser, no mocks beyond the CLI boundary.
SUBPLANEOF

cat >>"$PLAN" <<'PLANEOF'

## Flow

```mermaid
sequenceDiagram
  participant Orchestrator
  participant Worker
  Orchestrator->>Worker: assign task
  Worker-->>Orchestrator: progress
  Worker-->>Orchestrator: done
```

## Clarifying questions

_no ambiguity_

## Abstractions decision log

| decision | rationale |
|---|---|
| Use jq for contract validation | Already a required dependency; no new tooling. |

## Rationale & key decisions

Fixture plan exercising the deep-execute integration handoff end-to-end; no additional architecturally significant decisions beyond the lane/contract shape already declared above.

## Documentation impact

none — this is a throwaway test fixture with no user-facing documentation to update.

## QA / test-execution

No — shell-only pipeline fixture, no user-facing flows or screens.

## TDD test list

Mocking policy: mock only the outermost boundaries (network, third-party APIs, external CLIs); inner services and repository logic run real code against the throwaway git repo built for this test.

- `contract schema validates` — `jq -e '.type'` passes against the committed schema.
- `each lane owns its declared path prefix` — the ownership check accepts a well-formed write.
- `an out-of-ownership write fails the round gate` — boundary enforcement holds for real.

## Edge cases & failure modes

- Missing contract file at the declared path.
- An uncommitted contract or shared file at run-init time.
- A lane agent not present in the allowlist.
- A cyclic depends_on graph among lanes.

## Subplans

- [planning](subplans/planning.md)
PLANEOF

# superpowers-invoke.sh (and, below, validate-plan.sh) resolve the repo a
# receipt's SHA must be an ancestor of by preferring the plan's own git repo,
# falling back to the calling process's CWD. plan.md's own directory
# ($PLAN_SCRATCH) is not a git repo, and init-run.sh validates the plan with
# CWD cd'd to $REPO (see its Step 1) — so receipts must be anchored to
# $REPO's HEAD, not this test script's own ambient repo, or init-run.sh's
# internal re-validation would reject them as pointing at an unrelated
# commit.
# shellcheck disable=SC2016  # $1/$2/$3 are the bash -c child's own positional params
assert_exit 0 bash -c 'cd "$1" && "$2" "$3" grill-with-docs' _ "$REPO" "$INVOKE" "$PLAN_SCRATCH"
# shellcheck disable=SC2016
assert_exit 0 bash -c 'cd "$1" && "$2" "$3" brainstorming' _ "$REPO" "$INVOKE" "$PLAN_SCRATCH"
# shellcheck disable=SC2016
assert_exit 0 bash -c 'cd "$1" && "$2" "$3" writing-plans' _ "$REPO" "$INVOKE" "$PLAN_SCRATCH"
assert_contains "$(cat "$PLAN")" "- [x] grill-with-docs" "superpowers-invoke.sh ticked grill-with-docs with a receipt"
assert_eq "$(wc -l <"${PLAN_SCRATCH}/superpowers-receipts.log" | tr -d ' ')" 3 \
  "three superpowers-invoke.sh calls append three chain-linked receipt lines"
assert_contains "$(cat "${PLAN_SCRATCH}/superpowers-receipts.log")" "$(git -C "$REPO" rev-parse HEAD)" \
  "receipts are anchored to the throwaway repo's HEAD, the repo init-run.sh will re-validate against"

# ─── Step 1b: the grown plan validates cleanly, in full, from the same CWD ─
# init-run.sh itself validates FROM CWD (its own header comment: "matching
# how a human would run validate-plan.sh from the project root") — mirror
# that here so this check and init-run.sh's internal one agree.

PLAN_JSON=$(cd "$REPO" && "$VALIDATE_PLAN" "$PLAN" --root --json) || true
# shellcheck disable=SC2016
assert_exit 0 bash -c 'cd "$1" && "$2" "$3" --root --json' _ "$REPO" "$VALIDATE_PLAN" "$PLAN"
assert_eq "$(jq '[.[] | select(.status=="fail")] | length' <<<"$PLAN_JSON")" 0 \
  "fully-grown parallel plan: zero failing validate-plan.sh --root items"
assert_eq "$(jq -r '.[] | select(.item=="exec-mode-valid") | .status' <<<"$PLAN_JSON")" pass \
  "fixture plan: exec-mode-valid passes (mode=parallel)"
assert_eq "$(jq -r '.[] | select(.item=="superpowers-ticks-have-receipts") | .status' <<<"$PLAN_JSON")" pass \
  "every ticked skill has a chain-valid, ancestor-verified receipt"

# ─── Step 1c: init-run.sh scaffolds a real run against the throwaway repo ──

assert_exit 0 "$INIT_RUN" "$PLAN" "$RUN_DIR" "$REPO" "surface:test"
assert_exit 0 test -f "${RUN_DIR}/manifest.json"
assert_eq "$(jq -c '[.workers[].lane] | sort' "${RUN_DIR}/manifest.json")" '["execution","planning","review"]' \
  "manifest workers == the fixture's three non-orchestrator lanes"
assert_eq "$(jq -r '.contract.path' "${RUN_DIR}/manifest.json")" "src/shared/contract.schema.json" \
  "manifest carries the fixture's contract path"
assert_eq "$(jq -r '.baseline_commit' "${RUN_DIR}/manifest.json")" "$(git -C "$REPO" rev-parse HEAD)" \
  "manifest baseline_commit == the throwaway repo's HEAD at init time"
assert_exit 0 test -f "${RUN_DIR}/cmux/worker-planning.prompt.md"

# ─── Step 1d: the contract validates against what init-run.sh wrote ───────

CONTRACT_JSON=$("$VALIDATE_CONTRACT" "$RUN_DIR" --json) || true
assert_exit 0 "$VALIDATE_CONTRACT" "$RUN_DIR" --json
assert_exit 0 jq -e 'all(.[]; .status == "pass")' <<<"$CONTRACT_JSON"
assert_eq "$(jq -r '.[] | select(.item=="contract-sha256-matches") | .status' <<<"$CONTRACT_JSON")" pass \
  "contract sha256 recorded at init time matches the file on disk"
assert_eq "$(jq -r '.[] | select(.item=="contract-lint") | .status' <<<"$CONTRACT_JSON")" pass \
  "contract-lint: the fixture's own validation_command (jq -e '.type' ...) passes"

# ─── Step 1e: run-state validates clean on a freshly-scaffolded run ───────

STATE_JSON=$("$VALIDATE_STATE" "$RUN_DIR" --json) || true
assert_exit 0 "$VALIDATE_STATE" "$RUN_DIR" --json
assert_exit 0 jq -e 'all(.[]; .status == "pass")' <<<"$STATE_JSON"
assert_eq "$(jq -r '.[] | select(.item=="manifest-schema-valid") | .status' <<<"$STATE_JSON")" pass \
  "the manifest init-run.sh wrote satisfies run-state.schema.json"
assert_eq "$(jq -r '.[] | select(.item=="changed-files-within-union") | .status' <<<"$STATE_JSON")" pass \
  "a fresh run has no baseline-diff changes yet"

# ─── Step 1f: no real agent binary was ever invoked ────────────────────────

assert_eq "$(wc -l <"$STUB_LOG" | tr -d ' ')" 0 \
  "cmux/claude/codex/reviewer were never invoked by plan validation, init-run, or contract/state validation"

assert_summary
