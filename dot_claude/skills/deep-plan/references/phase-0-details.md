# Phase 0 details

## Phase 0.2 — Bootstrap code intelligence (mandatory)

Refresh local code-intel indexes so planners + reviewers use semantic tools instead of grepping raw files.

1. Run:
   ```
   ~/.claude/skills/deep-plan/scripts/bootstrap-codeintel.sh "$RUN_DIR"
   ```
   This re-runs `gitnexus analyze` if `.gitnexus/` exists, `graphify update .` if `graphify-out/graph.json` exists, and writes `$RUN_DIR/codeintel-status.json`.

2. Serena needs no activation call. Its MCP server starts with `--project-from-cwd`, so it
   serves the repository at the session's working directory. Start the session at the repo root.

3. If `graphify-out/GRAPH_REPORT.md` exists, read it for the "god nodes" + community summary before drafting — saves a planner pass.

4. Surface index status to the user in one line, e.g. `code-intel: gitnexus=fresh graphify=fresh serena=activated`.

The persona prompts (planner-opus, planner-codex, architect, project-developer, qa, ticket-matcher) all prefer these tools over raw `grep`/`find`:
- `mcp__serena__find_symbol`, `find_referencing_symbols`, `replace_symbol_body`
- `gitnexus_query`, `gitnexus_context`, `gitnexus_impact`, `gitnexus_rename`, `gitnexus_detect_changes`
- `graphify path/explain` for cross-symbol reasoning

## Phase 0.5 — Clarifying questions (mandatory)

Before any grill or draft, surface every ambiguity in the task description to the user. Use `AskUserQuestion` with focused options (no open-ended prose questions when a multiple-choice will do).

Examples of things to clarify: scope boundaries, personas/targets, trade-off preferences (speed vs correctness, minimal-diff vs refactor), acceptance criteria.

Record every Q/A pair in `## Clarifying questions` using `### Q:` / `### A:` headers. The validator requires ≥1 matched pair.

If — and only if — the task is genuinely unambiguous after a careful re-read, write exactly `_no ambiguity_` in the section and skip questions. This must be rare; the default is to ask.

## Phase 0.7 — Grill-with-docs deep interview (mandatory unless `--skip-grill`)

After the multiple-choice clarifications resolve the obvious gaps, drill harder and capture the reasoning as docs.

**Step 1 — run its two halves:** `Skill(skill="mattpocock-skills:grilling")`, then
`Skill(skill="mattpocock-skills:domain-modeling")`. Not `grill-with-docs` — it is
`disable-model-invocation` and the Skill tool refuses it; these two are the halves it composes,
both model-invokable by their author's own frontmatter. Offer the user
`/mattpocock-skills:grill-with-docs` when they would rather drive it. Phase 0.5 was the
multiple-choice sweep; this is the open-ended stress test feeding `## Rationale & key decisions`.

**Step 2 — record the transcript** in the plan under `## Grill-with-docs transcript` using `### Q:` / `### A:` headers (same format as clarifying questions, so the validator counts them too). Fold the resolved decisions into `## Rationale & key decisions`.

**Step 3 — mark invocation:**
```
~/.claude/skills/deep-plan/scripts/superpowers-invoke.sh "$RUN_DIR" grill-with-docs
```

If the user passes `--skip-grill`, still record `grill-with-docs` in the Superpowers section as `[ ]` so the checklist surfaces the skip.

## Phase 0.4 — Is this the right pipeline? (full text)

The code intelligence from Phase 0.2 says how large the change really is. When it meets the
lean criteria of `~/.claude/skills/_shared/plan-routing.md`, recommend `/simple-plan` instead
and follow the question rules there. Continue or stop on the user's answer.

When it is large but splits into working slices that ship in one PR, recommend stages
(`_shared/stages.md`) in the same question. Say nothing here when the change is genuinely large
and has no such slices. `deep-plan` is the default for this command, and a recommendation that
always fires teaches the user to skip it.

## Phase 0.1 — Plan mode rationale

deep-plan reads, indexes, interviews and writes plan artifacts under `$RUN_DIR`, and touches no
project file. Plan mode makes the Plannotator `ExitPlanMode` hook fire at Phase 3, so the user
approves the plan in the Plannotator UI instead of a terminal wall of text.
