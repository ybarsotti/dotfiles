---
name: explore-options
description: Explores many options for an open, high-stakes decision before it picks one. Use when a decision has several viable answers and the obvious answer is expensive if wrong — architecture, a public API or SDK surface, a schema, the name of a real product, a fuzzy bug with no known root cause — or when the user types /explore-options or asks to brainstorm widely. Runs isolated parallel generators under different frames, then a separate critic that scores, clusters and flags traps, then deepens the best three. Skip it for syntax, lookups, a bug with a known root cause, or a request phrased as "quick", "standard", "canonical" or "textbook".
argument-hint: "[the open decision to explore]"
---

# Explore options

The first three answers to a design question are the answers every senior engineer gives in
thirty seconds. They are correct and they are forgettable. The better options are past the
third one. This skill generates a wide set of options first, and then converges with
judgment.

The method follows UditAkhourii/adhd (MIT): parallel framed generators, then a separate critic.

## Pre-flight

A run costs about 9 agent calls and 5 to 10 times the tokens of a direct answer. Run this
gate first.

1. **Explicit request.** When the user typed `/explore-options` or asked for a wide
   exploration, go to step 0. Do not ask again.
2. **Self-check.** Otherwise answer three questions. When one answer is no, stop and answer
   the question directly.
   - **Open?** A senior engineer gives several viable answers, not one canonical answer.
   - **High stakes?** The obvious answer is expensive if it is wrong.
   - **Open phrasing?** The user did not say "quick", "standard", "canonical", "textbook",
     "just" or "one-line".

When you stop, you can add one sentence: "For a wider exploration, run `/explore-options
<problem>`."

## Step 0 — Assemble the context pack

Every generator receives the same short brief:

- **The problem**, in 1 to 3 sentences.
- **Hard constraints**: stack, scale, deadline, compliance, and what the user said is fixed.
- **Code facts**, for a code problem: file paths, key signatures and existing patterns. Read
  them with the code tools. Keep them under 300 words. Give facts, not file dumps.
- **Success criteria**, when the user stated them.

Two rules apply:

1. **Give every generator the same pack.** The inputs stay equal and only the frame changes.
2. **Put no candidate solution in the pack.** One "we could do X" makes every generator
   start from X. Give constraints and facts only.

## Phase 1 — Diverge (no critic)

1. Pick 5 frames from the table below. For a code problem, pick 4 frames tagged `code` or
   `design` and 1 tagged `wild`. Vary the picks between runs.
2. Start 5 generator agents in one message, so they run in parallel. Each agent gets the
   problem, the context pack, its frame's vantage prompt, and this instruction:

   > You generate, you do not judge. Write 6 short, distinct ideas under this frame. Each
   > idea is one phrase or one sentence. Do not evaluate, rank or hedge. The three obvious
   > answers are banned. Go past them. Return JSON: `{"frame": "...", "ideas": ["..."]}`.

3. **Keep the generators isolated.** Do not run them in sequence. Do not give one
   generator's output to another. Do not write the branches yourself in one context.
   Generators that see each other converge, and the run becomes one wide thought.

## Phase 2 — Focus (critic on)

1. **Score with a separate critic agent.** Do not score the pool yourself: you read every
   branch, so you already favour some ideas. The critic gets the problem, the pack and the
   pool, and rates each idea from 0 to 10 on:
   - **novelty**: the distance from the obvious default,
   - **viability**: the chance that it ships,
   - **fit**: how well it solves the stated problem.

   The critic flags each attractive but wrong idea as a **trap**, with a one-line reason: a
   hidden cost, a false saving, a design that does not scale, a premature abstraction.
2. **Cluster.** The same critic groups the ideas into 3 to 6 clusters by underlying angle,
   not by shared keywords.
3. **Deepen the top 3.** Rank by `0.35 × novelty + 0.40 × viability + 0.25 × fit`, drop
   the traps, and take the top 3. Start one agent per idea, in parallel. Each returns a
   sketch of 4 to 8 sentences, the main risk, the first concrete step, and 3 to 5 child
   ideas: variations, hybrids, or what the idea unlocks.

## Frames

| Frame | Vantage prompt | Tags |
|---|---|---|
| hardware engineer | You think in latency, memory layout and physical limits. Treat this as a hardware or firmware problem. What do the bus, the cache and the timing budget tell you? | code, wild |
| regulator | You audit systems for compliance and failure modes. What must be provable, traceable or refusable here? | design, general |
| 10-year-old | You are a curious child who has never seen software. Describe naive approaches that ignore convention. | general, wild |
| attacker | You want the obvious solution to fail. Find how to exploit, break or sabotage it, then invert each attack into an idea. | code, design |
| biology | Take a mechanism from biology — immune systems, neural plasticity, cell signalling, evolution — and force-fit it onto this problem. | code, wild |
| logistics | Take mechanisms from logistics — queues, batching, just-in-time, hub and spoke, returns, last mile — and apply them literally. | code, design |
| game design | Treat the user as a player. What are the loops, rewards, friction, save states and shortcuts? | design, general |
| markets | Treat the problem as a market of buyers, sellers and market makers. What does an auction, a futures contract or a clearing house look like here? | design, wild |
| inversion | Ask the opposite question. How do you guarantee the goal fails? Then negate each answer. | code, design, general |
| $0 and 1 hour | No money, no team, one hour. What is the crudest version that still does the essential thing? | code, general |
| infinite budget, 10 years | Unlimited compute, unlimited engineers, ten years. What is the maximal version? | design, wild |
| remove the fixed assumption | Name what everyone treats as fixed: the framework, the database, request and response, the network. Remove it. What becomes possible? | code, design, wild |
| speedrunner | Find the skips, the glitches and the out-of-bounds shortcuts. What is the abusive but legal path? | code, wild |
| ant colony | There is no central planner. Many simple agents follow local rules. How does the problem solve itself? | code, wild |
| on-call at 3 a.m. | The pager wakes you when this breaks. What design never pages you? | code, design |

## Output

Render the result in this order. Do not collapse it into prose.

1. **Brief.** One or two lines: the problem, and the reframe when you used one.
2. **Wide set.** The full pool grouped by cluster. Label each cluster by its angle. Show each
   idea as one phrase with its scores, for example `[N7 V8 F9]`.
3. **Converge.** A shortlist of 2 to 4 ideas, each with its reason. Mark the non-obvious but
   viable pick with ★. List the traps separately, each with its reason.
4. **Focus.** The 3 deepened ideas: sketch, main risk, first step, child ideas.
5. **Provocation.** One wild-card idea or question that opens a new direction.

## Failure modes

- **Variations of one idea.** Ten ideas that share one assumption are not breadth.
- **A pile with no decision.** Always converge, and take a position on what is promising.
  "Here are 20 ideas, you decide" is not an answer.
- **Equal-weight prose.** Cluster, label and pull out the best ones.
- **Branches written in one context.** Use a fresh agent for each branch.
- **The orchestrator as critic.** The critic is a separate agent call.
- **A solution in the context pack.** Give constraints and facts only.

## Calibration

- **Size.** Scale to the stakes. A function name needs 3 frames × 4 ideas. A product
  position needs 5 × 8. The default is 5 × 6 = 30.
- **Tone.** For serious strategy work, label the wild ideas so they do not read as jokes.
  For open play, let them run.
- **Stop.** Stop diverging when new ideas repeat the shape of earlier ones. Do not pad to
  reach a number.

## With a brainstorming flow

When `superpowers:brainstorming` reaches its "propose 2 or 3 approaches" step on a
high-stakes design, offer `/explore-options`. Approaches written in one context converge on
each other. The deepened shortlist becomes the approaches that the brainstorming flow
presents.
