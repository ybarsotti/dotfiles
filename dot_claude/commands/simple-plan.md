---
description: Lean plan — least code that works, project patterns, strict typing, edge-case decision table, TDD list, Plannotator
---

# /simple-plan

Plan a small or medium change. When you approve the plan, the same session builds it,
reviews it, runs QA, opens the PR and delivers an HTML report, without waiting for you
(`~/.claude/skills/_shared/after-approval.md`). Say "only plan" to stop at the approved plan.

It plans **one task**. When the work is bigger than that, the skill splits it into
deliverable tasks ordered from the foundation up and plans the one you pick — it does not
hand the problem to another command.

**Arguments:** `$ARGUMENTS`

```
/simple-plan <task description>
```

## Phases

0. **Context brief** — read the affected `CLAUDE.md` files, `.claude/rules/`, neighbor files
   of the same kind, the dependency manifest, and the docs of the libraries the change uses.
   Every claim cites a path.
0.5 **Recommend the pipeline** — recommend `simple-plan` or `/deep-plan` with the criteria
   of `~/.claude/skills/_shared/plan-routing.md`, then wait. The decision and the user's words
   go in the plan's front matter.
1. **Grill** — `mattpocock-skills:grilling` on every task, without a question cap. Say
   "skip grill" to skip it. Resolved decisions go into the plan.
1.2 **Brainstorm** — `superpowers:brainstorming`, only when the grill left the design open,
   and with at most 3 questions.
1.5 **Split** — when the work holds more than one shippable outcome, an agent turns it into
   2-6 deliverable tasks ordered from the foundation up. You pick one; this run plans that one.
2. **Draft** — when the change touches an interface, first consult
   `ui-ux-pro-max:ui-ux-pro-max` and one UI/UX agent against the existing UI, so the plan
   names the components and tokens to reuse instead of inventing them.
   `~/.claude/skills/_shared/plan-format.md` defines the format. The plan states the problem,
   the non-goals, the approach, the project fit, the concrete types, the affected files, an
   edge-case decision table, the TDD test list, and the validation steps.
3. **Review** — the `plan-reviewer` agent, one per side that the plan changes (backend,
   frontend), in parallel, for at most 3 rounds. It checks scope drift, the plan format,
   types, project patterns, clean and reusable code, callers and flows the plan missed,
   external systems, architecture, edge cases, tests, and the data or UI of its lens.
3.5 **Blindspot** — `blindspot`, over the plan itself. The Phase 3 reviewers share the
   author's reading history. This pass labels every claim READ or INFERRED, then opens the
   surface behind each INFERRED claim or rewrites the claim to what was observed.
4. **Present** — when the plan adds machinery, `shed-light` first, so the approval covers
   the upkeep and not only the design. Then `plannotator annotate --gate` in a loop. The
   pass with no annotations is the approval.
5. **Build to PR** — `/qa-plan` first when a flow or screen changes, then
   `~/.claude/skills/_shared/after-approval.md` end to end, then the next task from the
   breakdown.

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
- No `# noqa` or `# type: ignore` unless the plan names the line, the rule it silences, and
  why the real fix is impossible. "It was failing CI" is not a reason.
- Put code where it belongs: a shared filename prefix becomes a directory, names follow the
  neighbours, a small thing gets a small file, and a function that belongs to a class is a
  method. No dependency stays in the manifest with no importer.
- Comment only what the code cannot show.
- One migration per change. Two migration files are one schema change in installments — merge
  them unless one already ran, an operation cannot share their transaction, or a long backfill
  must sit between two steps.
- Tests mock only the outermost call to an external service: the HTTP request, the broker
  enqueue, the SDK call, or the clock. This project's services, repositories, dispatchers,
  and clients run for real. Mock `httpx.AsyncClient.post`, not the `VendorClient`; mock
  `task.delay`, not the dispatcher; mock `stripe.Refund.create`, not the model's refund method.
- Edge cases go in a table with a decision: cover now, fail loudly, or out of scope. Only
  `Cover now` rows reach the implementation.
- Touch only the code the task needs. No drive-by refactor, rename, or reformat. When nearby
  logic looks complex or defective, ask the user before you change it.

## Examples

```bash
/simple-plan "add a resend button to the invoice detail page"
/simple-plan "cache the tax lookup for 5 minutes"
/simple-plan "return 422 instead of 500 when the webhook payload is malformed"
```
