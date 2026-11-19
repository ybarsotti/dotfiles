# Implementer rules

These rules apply to every agent that writes production code in the build chain: a
`/deep-execute` lane worker, an `implement` worker and a fixer. The review panel of
`/deep-review` checks the same points later. Each rule here prevents a finding that the panel
raised often in past reviews. Follow them while you write, so the review finds less.

Read the **Core** section, then the section of your work: **Backend**, **UI**, or both.

## Precedence

- The rules of your lane or your spec win: never run `git`, and stay inside the files you own.
  They override the commit and push steps of `ub-mode`.
- The `ub-mode` gates (`crapper`, `dryer`, `mutator`) set how many tests you write. One test
  per handled case is the floor, not the ceiling.
- Open a pull request only through `/pr` (the `pr-description` skill). Never run
  `gh pr create` or open one by hand. A worker never opens one: the orchestrator does.
- When a better design needs files outside your scope, do not edit them. Report it as a
  `question` or `blocked` event, or in your final report.

## Core

### Before you write

1. Read the task, the project instruction files near each file you change (`CLAUDE.md`,
   `AGENTS.md`, `.claude/rules/`), and two neighbour files of the same kind.
2. Trace the real flow from end to end. Find every caller before you change a function.
3. Search for an existing helper, type, constant or component before you write one. Then use
   the standard library, the platform, and an installed dependency, in that order. Do not add
   a dependency for what a few lines can do.

### Scope and design

4. Write the smallest change that solves the task. Do not add an interface with one
   implementation, a speculative parameter, a configuration key or scaffolding.
5. Change only the code of the task. Do not refactor, rename or reformat code next to it.
6. Get the data shape right first. Model the data so that an illegal state cannot exist.
7. Fix a bug at its root cause, in the shared function that all callers use.
8. Finish each removal: the exports, tests, flags, configuration, docs and callers.
9. Write a comment only to say why. A comment never describes unfinished work in scope.

### Types and input

10. Type every contract. Do not use `any`, `Any`, `object`, a bare `dict` or `as never`.
11. Use an enum or a literal type for a fixed set, a named type for an id, and a decimal type
    for money.
12. Validate outside data once, at the boundary, with the framework validator. Then trust it.
13. Check type, shape, range and size: `null`, a wrong type, a large number, deep nesting.
    Bad input returns a 4xx error, never a 500.
14. Put a limit on every request body, list, queue, cache, query and stored record.

### State, concurrency and failure

15. Guard each read-then-write and check-then-act: use a row lock, a conditional update or a
    database constraint. Do not hold a lock across a network call.
16. Expect messages, retries and responses to arrive late, twice or out of order. An older
    value never overwrites a newer one. Use a monotonic clock for durations.
17. Make each write safe to repeat: a retried request or webhook creates no duplicate.
18. Make a write of several steps atomic. Update memory only after the commit succeeds.
19. Fail closed. Never return an empty or a success result after a failure. Log the error with
    its context, and do not show internal details to the caller.
20. Set a timeout on every call to an outside service.

### Security

21. Check authentication and permission on every new route, handler and job.
22. Filter every query, cache and fallback by the account of the caller.
23. Keep secrets and personal data out of code, logs, URLs and telemetry.
24. Use parameterised queries. Escape HTML, file paths and shell arguments.

### Placement

25. Before you create a file, find the domain module that owns the concept, for example
    `apps/orders` or `features/assistant`. Write the code there. Domain logic never goes to a
    `utils` or `shared` module, or to the module of a consumer.
26. A view, a router, an endpoint and a screen component hold no business rule. They call the
    domain.
27. One concept has one home. Do not spread its loader, its rules and its dispatch over
    several modules.
28. Files that share a prefix become a package. A function that only uses one object becomes a
    method of that object. A helper that one class uses lives in that class.
29. When the owning domain is not clear, ask (a `question` event, or your final report). Do not
    pick one at random.

### Structure

30. Dependencies point one way, with no import cycle.
31. Use the names and the layout of the neighbour files. Keep a file under about 500 lines.
32. Keep each function under cyclomatic complexity 10. Nest 2 levels at most. Do not nest a
    ternary. Use an early return.

### Tests

33. Write the failing test first. See it fail for the expected reason.
34. Write one test for each case you handle, and one for the success path.
35. Make sure each test can fail: break the line it covers and see it fail.
36. Mock only the outermost external call: HTTP, a broker, an SDK or the clock. Run the code
    of the project for real.
37. Freeze the clock. Wait on a condition, never on a fixed sleep.
38. Never weaken a check to make it pass: no lower limit, no skipped test, no `noqa`, no cast,
    no suppression without a reason on the same line.

### Before you report done

39. Update the docs, the plan and the specs that your change makes wrong.
40. Leave no generated output, scratch file or absolute home path in the change.

## Backend

41. Avoid N+1 queries. Add an index for each new filter and sort. Bound each result set.
42. Use the column type that fits: `timestamptz`, `decimal`. Add `NOT NULL`, foreign key,
    unique and check constraints. Put a queried field in a column, not in JSON.
43. Write one reversible migration per change. Old code still runs during the deploy, so
    expand first and remove later.
44. Make no call to an outside service inside a transaction.

## UI

45. Before the code, open the design and read `~/.claude/skills/_shared/ui-quality.md`.
46. Reuse the components and tokens of the project. Do not hardcode a colour, a spacing or a
    radius.
47. Build each state: loading, empty, error, pending, success and no permission.
48. Use native elements. Move focus into a dialog and back out. Announce changes in a live
    region. Give each control a unique accessible name. Colour never carries meaning alone.
49. At 390 px, the page has no horizontal scroll and each touch target is 44 px or more.
50. A refetch never overwrites what the user typed. A late response never wins over a newer
    request.
51. Take screenshots of each state at desktop width and at 390 px. Fix what is weak. This is
    your own check: only the `qa-ui` agent proves that the screen matches the canvas.

## When in doubt

Read the source of the rule before you guess. Read only the part you need.

| Doubt | Read |
|---|---|
| Where a file, a name or a function goes | `~/.claude/skills/simple-plan/references/constraints.md`, section 11, and `~/.claude/skills/deep-review/personas/project-fit.md` |
| Layering, module boundaries, types, a design pattern | `~/.claude/skills/deep-review/personas/architecture.md` |
| A simpler way, reuse, dead code | `~/.claude/skills/deep-review/personas/simplicity.md` |
| Edge cases, races, retries | `~/.claude/skills/deep-review/personas/correctness.md` |
| Queries, migrations, transactions, logging | `~/.claude/skills/deep-review/personas/senior-backend.md` |
| Authentication, permission, input, secrets | `~/.claude/skills/deep-review/personas/security.md` |
| Test design, mocks, flaky tests | `~/.claude/skills/deep-review/personas/test-quality.md` |
| A screen, a state, accessibility | `~/.claude/skills/_shared/ui-quality.md` and `~/.claude/skills/deep-review/personas/senior-frontend.md` |
| The rules of the project | the `CLAUDE.md`, `AGENTS.md`, `.claude/rules/` and `docs/*rules*` of the repository |

When the file does not settle it, ask the orchestrator: a `question` event in a lane, or your
final report as a worker. Do not start another agent for an opinion.
