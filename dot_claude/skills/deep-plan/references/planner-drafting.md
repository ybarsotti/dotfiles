# Planner drafting details

## Phase 1.5 — Two-track planner drafting (plan format)

`~/.claude/skills/_shared/plan-format.md` is the **single source of truth** for the plan's shape — the
document header, the File Structure step, task right-sizing, the `### Task N:` blocks with
their bite-sized checkbox steps, and the no-placeholder rules. deep-plan never restates or
paraphrases those rules: it **reads the file** and follows it, on every run. Never invoke
`superpowers:writing-plans`.
`templates/plan.md` only adds deep-plan's extra sections (requirements, journey, data model,
design handoff, context links, clarifying Qs, flow, rationale, QA flag, checklist) around it.

**Step 1 — invoke the skill via the Skill tool:**
```
Read ~/.claude/skills/_shared/plan-format.md
```

**Step 2 — record the invocation:**
```
~/.claude/skills/deep-plan/scripts/superpowers-invoke.sh "$RUN_DIR" writing-plans
```

**Step 3 — start the designer, when the change touches an interface.** Start the
`ui-designer` agent as an Orca worker with `--keep-open` (`_shared/after-approval.md`, "Parallel
agents run in Orca"). Give it the ticket, the task, the app URL or run command, and
`$RUN_DIR/design/`. It reads and screenshots the screens it changes before it draws, while the
planners draft. Put its `Canvas:` and `Design system:` URLs in the UI design pass before Phase 3.

**Step 4 — dispatch:**
```
~/.claude/skills/deep-plan/scripts/dispatch-planners.sh "$RUN_DIR" "$TASK_DESC"
```

The dispatcher spawns in parallel. The planners and the plan reviewers run headless
(`claude -p`, `codex exec`), not in Orca: each one writes one file and exits, and the scripts
read the verdicts. Orca workers start after the approval, in the build chain.
- `claude -p` (Opus) loaded with `personas/planner-opus.md`
- `codex exec` (latest) loaded with `personas/planner-codex.md` *(skipped if `--no-codex`)*

Both are told to **read `plan-format.md` themselves** before drafting — the dispatcher passes
a pointer, never a copy of the skill body. Both receive the task description +
`templates/plan.md` as their skeleton. Each writes its draft to `$RUN_DIR/draft-opus.md` and `$RUN_DIR/draft-codex.md`.

When both return, synthesize **one** merged candidate plan into `$RUN_DIR/plan.md` using the template. Prefer the Opus draft's architecture framing, the Codex draft's codebase-grounded specifics. Resolve disagreements by keeping the stricter requirement.

**TDD & mocking policy the plan MUST encode** (into `## TDD test list`): the build follows strict red-green-refactor, and mocks **only the outermost boundaries** (network, 3rd-party APIs, clock/random). Inner services, repositories, and domain logic run **real** code in tests — do not mock every service.
