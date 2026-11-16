# Engineering principles

Rules for the design and the build of every change. Adapted from `ub-mode`
(https://github.com/unclebob/ub-mode, MIT license, Copyright Robert C. Martin), which is itself
based on parts of `poteto-mode`. The deep-review personas check the same rules.

Make it work first. Then make it right. A plan applies section 1. A build applies sections 1
and 2.

## 1. Design (the plan and the first build step)

1. **Data shape first.** Write the types and the schema before the logic. Do first the work
   that helps every later step.
2. **Make illegal states impossible.** Model the domain so that a wrong value cannot be
   written: a union or an enum, not two flags that can disagree. Use the project glossary
   (`CONTEXT.md`) for each domain term. Leave clear, local code as it is.
3. **Check data where it enters.** Parse outside data once, at the boundary. Inside, trust
   it. Keep the business rule in a pure function. Do not silence the type checker.
4. **Redesign, do not bolt on.** For a new requirement, ask what you would build if it had
   existed from the start. Plan that design, and deliver it in steps.
5. **Subtract before you add.** Remove the complexity that the change makes unnecessary
   before you add new code. Prefer the plan with less code to own.
6. **Idempotent operations.** Running an operation twice, or again after a crash halfway
   through, ends in the same state.
7. **One writer.** Give each actor its own state when they do not need to share it. When
   they must share it, allow one writer, and enforce that in the structure.
8. **Verifiable units.** Split the work into small units, each with a check that proves it.
   Aim at an end state you can check. A broken state in the middle is allowed only when the
   plan names it and the next unit removes it.
9. **Build the lever.** When the same edit repeats across many places, do one by hand, then
   build the script or codemod that does the rest and check it against the first.

## 2. Build

1. **Test first.** Write the failing test. See it fail for the reason you expect. Make the
   smallest change that passes. When an honest test is impractical, write no test, and say so.
2. **Test behavior.** Call the code the way its user does and check what that user sees. A
   test that still passes when every function returns nothing is not a test. Delete it.
3. **Fix the root cause.** Reproduce the defect first. A guard that only hides the failure is
   not a fix.
4. **Attack the premise.** When two fixes that share one premise fail the same check, stop.
   Write that premise in one sentence and test whether it is true. Start no third fix until
   you did.
5. **Refactor in three steps.** Pin the behavior with a test. Change the structure. Prove that
   the behavior did not change.
6. **Keep each function simple.** Split a function whose branches grow, or test each branch.
   Remove structural duplication. When the project has a `mutate` recipe, cover the code that
   no test reaches, kill the surviving mutants, and delete the dead code.
7. **Small ordered commits.** Each commit says why, what changed, and how you proved it.
8. **Record each departure.** Each decision that departs from the plan gets a `D-NNN` row
   under the plan's `## Deviations`, with its reason.
