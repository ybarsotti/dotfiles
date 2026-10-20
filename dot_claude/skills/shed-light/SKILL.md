---
name: shed-light
description: Use when someone must decide whether an implementation is worth its upkeep — a plan that adds infrastructure, a PR that grew machinery, or a question about over-engineering, hidden work, or maintenance burden. Produces an inventory of what the change asks the team to own, ranked by complexity, with a separate maintenance estimate and the external work each piece creates.
---

# Shed Light

Produce an inventory of what the change asks the team to **own**. The reader is deciding
whether the added work is worth it, so every row names work a person must do.

This is not a review. It records no defect and no verdict. A piece of high-complexity
machinery can be the right answer; the colour states the burden, not a fault.

## Write it for the decision

Use plain words and short, complete sentences. Name the work, not the concept. Write "update
three checks whenever a filter changes", not "coordinate validation policy across coupled
boundaries". Keep the code name in the evidence link, where it belongs, and explain a term
only when the decision needs it.

## 1. Set the scope

State what the change is for, and what you are reading: a plan, a diff, or both. For a diff,
name the baseline. For a plan, separate the work it proposes from the capability that already
exists. When both are in scope, mark the additions that appeared during implementation and
were in no plan.

A file you read for context is not part of the change. Resolve an ambiguous scope before you
attribute anything to the change.

## 2. Inventory the additions

Read the source and the mechanisms it already has. List every material supporting addition or
expansion, including the machinery inside a modified file: a service, a queue, a package, an
interface, a registry, a configuration key, a permission, a storage location, a migration, a
check, a fallback, a test harness, a CI step, a monitor.

- Group the pieces that form one mechanism. Separate them when they carry different work.
- Include the additions you judge necessary, not only the questionable ones.
- Record a capability the change reuses as context, not as new ownership.
- Give each addition a short evidence link, and say what it is for in ordinary words.
- Separate the capability the change needs from the mechanism it chose. A simpler mechanism
  for the same capability is the most useful thing this report can name.

## 3. Rate the complexity, estimate the upkeep separately

Rate **incremental complexity** against the baseline you read:

| Rating | What justifies it |
|---|---|
| 🔴 High | Another process to run, failures to handle across a boundary, releases that must ship together, or many connected parts |
| 🟠 Medium | A new rule, a new setting, or several places a developer must change together |
| 🟢 Low | A small piece that follows an existing pattern and needs little work elsewhere |
| ⚪ Unknown | Not enough information. Say what is missing. |

Justify each rating with its actual moving parts. **Line count, file count, and being new are
not measures of complexity.**

Estimate **maintenance on its own**, as low, medium, high or unknown, then name the work, its
trigger or frequency, and the rough effort. Separate the one-time setup from the recurring
duty. Credit the automation and the ownership that already absorb the work. Use hours or money
only when the evidence supports it, and state the assumption. Never invent a recurring chore.

## 4. Trace the work that leaves the team

Name every obligation the change creates outside the code: an account to create, a secret to
rotate, a quota to raise, a vendor to pay, a review to pass, a runbook to write, an on-call
rotation to extend, a consumer in another repository to migrate. This is the work that surprises
people after the merge, because no line of the diff shows it.

## 5. Output

Order the rows by complexity, highest first.

| Addition | Type | Complexity | Maintenance | Evidence |
|---|---|---|---|---|
| What the team now owns | service, library, structure, settings, data, checks, test tooling, monitoring, helper | 🔴 / 🟠 / 🟢 / ⚪ with its moving parts | the work, its trigger, the effort | `path:line` |

Close with:

- **External work** — the list from section 4, or "none found".
- **The simpler mechanism** — for each 🔴 and 🟠 row, the smaller way to get the same
  capability, or the reason none exists.
- **What is uncertain** — every estimate that rests on something you could not read.

## Scope

Use the same report shape for a plan and for finished code. A plan's rows describe work the
team will own; a diff's rows describe work it already owns. Say which one you read.
