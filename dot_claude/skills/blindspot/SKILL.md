---
name: blindspot
description: Use before declaring a plan, review, report or PR body done — classifies every claim in the artifact as READ or INFERRED, then opens the surface behind each INFERRED claim or rewrites the claim to what was actually observed. Use after self-review, a roast or a review panel has already come back clean, because those passes share the author's reading history.
---

# Blindspot

Self-review checks what you wrote against what you **read**. A blindspot lives in what you
**never read**. A review loop can run to convergence and still carry a false claim, because
the reviewer and the author share one reading history: they have the same files unopened.

**The rule: classify every claim as READ or INFERRED. An INFERRED claim is unverified however
many review passes it survived.**

READ means you opened that file, or ran that command, **in this session**, and saw the output.
INFERRED means you extrapolated it, remembered it, or assumed it. A `file:line` citation of a
file you never opened is INFERRED. Citing is not reading.

## When to use this

- A plan, report, review or PR body is clean after self-review and you are about to ship it.
- Before you execute a plan, open a PR, or tell the user the work is done.
- Any claim shaped "X, therefore Y", where Y is a different system from X.

Do not use it to find defects in what you wrote. That is ordinary review. Blindspot asks one
question: **what did I never look at?**

## Procedure

1. **List the claims.** Write out every factual assertion the artifact makes. Include the
   causal ones ("the script skips it, so CI skips it"), the citations, and every statement
   about a system the work does not touch.
2. **Label each claim READ or INFERRED.** Use the definition above. Be strict with yourself:
   a claim you are confident about is still INFERRED when you did not open the surface.
3. **For each INFERRED claim, open the surface or downgrade the claim.** Verification is
   usually one or two tool calls. When you cannot verify it, rewrite the claim to state only
   what you observed, and say what remains unchecked.
4. **Sweep the surfaces below**, even when no claim names them. The worst blindspots are the
   interactions the artifact never mentions.
5. **Report what changed.** List the claims you verified, the claims you rewrote, and the
   claims that stay unverified with the reason.

## Surfaces that go unread

| Surface | The trap |
|---|---|
| CI configuration against local scripts | "the local script skips it, so CI skips it". CI often calls the tool with different arguments. |
| A derived value against a run | an expected value worked out by hand from the code, and never executed. |
| A schema file against the live database | the column exists in the model and the migration never ran, or the reverse. |
| Consumers outside this repository | a dashboard, a warehouse model, or another service that reads the field you rename. |
| Hooks, generated files and tool configuration | a pre-push hook, a test-runner project filter, a code generator's output. |
| Side effects the artifact does not assert | an output the change also produces, which no check covers. |
| A document or a memory note | true when it was written, never re-checked against the code as it is now. |
| The failure path of a command you ran | the happy output was read, the error branch was not. |

## What makes the pass necessary, not optional

- "Two review passes found nothing." Those passes inherit your reading history.
- "That claim is obviously true." An obvious inference is the one nobody checks.
- "The citation gives a `file:line`." Citing is not reading.
- "Checking it is one more tool call." Then make the call.

## Scope

This pass reads the artifact, not the diff. It applies to a plan, a design note, a review
report, a PR body, a status update, and a message to another person. In a review panel, the
mechanical half of this pass is already automatic: `deep-review` resolves every cited
`file:line` and lists the citations that do not resolve. This skill covers the half a script
cannot do, which is the claim whose words go further than the evidence behind them.
