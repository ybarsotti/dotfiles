---
description: Lean plan — least code that works, project patterns, strict typing, edge-case decision table, TDD list, Plannotator
---

# /simple-plan

Plan a small or medium change and stop at an approved plan. `/simple-plan` does not build,
review code, or open a pull request.

It is the short counterpart of `/deep-plan`: one drafter, two reviewers, at most two review
rounds. When the task needs a requirements matrix, a user journey, or parallel lanes, the
skill says so and stops. Run `/deep-plan` yourself in that case.

**Arguments:** `$ARGUMENTS`

```
/simple-plan <task description>
```

## Phases

0. **Context brief** — read the affected `CLAUDE.md` files, `.claude/rules/`, neighbor files
   of the same kind, the dependency manifest, and the docs of the libraries the change uses.
   Every claim cites a path.
1. **Brainstorm** — `superpowers:brainstorming`, only when the task is unclear, and with at
   most 3 questions.
2. **Draft** — `superpowers:writing-plans` defines the format. The plan states the problem,
   the non-goals, the approach, the project fit, the concrete types, the affected files, an
   edge-case decision table, the TDD test list, and the validation steps.
3. **Review** — `ponytail:ponytail-review` for over-engineering and the deep-plan
   `project-developer` persona for project fit, in parallel, for at most 2 rounds.
4. **QA plan** — `/qa-plan`, only when a user-facing flow or screen changes.
5. **Present** — `plannotator annotate --gate`, then `ExitPlanMode`.

## What you must do

Invoke the `simple-plan` skill. Do not plan inline. The skill lives at
`~/.claude/skills/simple-plan/SKILL.md`. Follow its phases exactly.

## Rules the plan enforces

The full list lives at `~/.claude/skills/simple-plan/references/constraints.md`. The short
form:

- Write the least code that solves the problem. Reuse what the codebase already has. Prefer
  the standard library, the platform, and an installed dependency over new code.
- Follow this project's conventions, and each framework's own idiom.
- Type everything. No `dict[str, str]`, no `Any`, no cast that only silences the checker. The
  plan shows the real type declarations, because a passing type checker does not prove good
  typing.
- Validate API input with the framework's validator, at the boundary only.
- No `# noqa` or `# type: ignore` unless the plan names the line and the reason.
- Comment only what the code cannot show.
- Edge cases go in a table with a decision: cover now, fail loudly, or out of scope. Only
  `Cover now` rows reach the implementation.

## Examples

```bash
/simple-plan "add a resend button to the invoice detail page"
/simple-plan "cache the tax lookup for 5 minutes"
/simple-plan "return 422 instead of 500 when the webhook payload is malformed"
```
