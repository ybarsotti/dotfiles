# Plan page

This file is the single definition of the plan page for `deep-plan` and `simple-plan`. Point
at this file. Do not copy its rules into another file.

The plan page is a humanized HTML view of the plan. The user reads it to approve the plan.
`plan.md` stays the source of truth. The page is generated from it, so never edit the page by
hand.

## 1. Render the page and gate on it

Do these steps for every plan.

1. Read the Plan path of the Plannotator visual explainer by path. It refuses the Skill tool:
   `~/.claude/plugins/marketplaces/plannotator/apps/skills/extra/plannotator-visual-explainer/SKILL.md`.
   When that path is missing, run
   `find ~/.claude/plugins -path '*plannotator-visual-explainer/SKILL.md'` and use the result.
   Read the two references that the Plan path names.
2. Distill `plan.md` to the human altitude: the goal, the approach, each key decision with its
   reason, the risks, and the phases in sequence. Leave out file lists, task steps and the TDD
   list.
3. Keep every contract the user approves, in full, even when it is technical. Distilling never
   drops one of these:
   - **Requirements**: the requirements matrix, one row per requirement, with its source
     (ticket, document, or the user's words), its status (solved, partly, not solved) and the
     part of the plan that solves it. List each addition beyond the ticket with its source.
   - **Flow**: the end-to-end flow across every system that the change touches. Show the
     flow of today first, then the new flow, so the reader sees what changes.
   - **Data**: each new or changed table, with its columns, types, nullability, defaults,
     keys, indexes and constraints; each removed column; the migration count; and the ER
     diagram. Show it as a table per entity, not as prose. Give each new column one line on
     why it lives on that table and not on a parent or child table.
   - **API and events**: each new or changed endpoint, payload, event or job contract.
   - **Permissions**: the role table, when access changes.
   - **UI**: the canvas link and the design images, when the plan has a UI design pass.
   - **User-facing copy**: each new text, as the user will read it.
   When the plan changes none of these, say so in one line on the page.
   Add a short glossary: each domain term and acronym that the page uses, in one line each.
4. Reuse the Mermaid diagrams of the plan. Do not draw a second version of a diagram.
5. Write the page beside the plan as `plan.html` (`$RUN_DIR/plan.html` or
   `${PLAN_PATH%.md}.html`). Follow the Plan path structure: summary strip, timeline, SVG flow,
   risks, open questions.
6. Run the gate in the background, because the user can take more than an hour to read:

   ```bash
   plannotator annotate plan.html --gate
   ```

   Start it with `run_in_background: true`, and wait for its notification. Do not run it in
   the foreground with the default timeout: a timeout loses every annotation. When the gate
   ends without a result, open it again at once and tell the user that earlier annotations
   did not arrive.

7. Map each annotation back to its section in `plan.md`. Edit `plan.md`, then render the page
   again.
8. Repeat steps 6 and 7 until the user approves with no annotations.

## 2. Decide where the page lives

The page stays local by default. Publish it as a private Artifact only when one trigger holds:

- a reader other than the user is named, such as a reviewer, a lead or a channel;
- the plan has a UI design pass;
- the plan's `## Work size` says `Size: L`.

When no trigger holds, record this line in the plan: `Plan page: local — <reason>`.

## 3. Do not publish in these cases

- The plan holds a secret, a credential or customer data. Keep the page local and record the
  reason.
- The machine is a work machine. Read the purpose with
  `chezmoi data --format json | jq -r '.machine.purpose // empty'`. When the command gives no
  answer, ask the user. On a work machine, ask once before you publish. No answer means no
  publish.

## 4. When you publish

1. Start with the `Artifact` tool, `action: "quickstart"`, `intent: "other"`. Follow its result.
2. Link the `Canvas:` and `Design system:` URLs of the UI design pass. Do not draw the screens
   again.
3. Send the page URL to the open `ui-designer` worker, with `orca terminal send` to its
   terminal, or `SendMessage` when it runs as an `Agent`. The worker adds a `Plan:` link to the
   canvas.
4. Put the page URL in the plan summary that the chat shows.
5. Before the final `plannotator annotate --gate` pass, read the page comments with `ArtifactComments`. Treat each comment as
   an annotation from step 7 of section 1.
6. After the stamp (`plan-stamp.sh approve`), publish the page again with an "Approved" banner
   and the stamp hash from `plan-stamp.sh hash`.
7. A comment that arrives after the approval is a deviation. Record it in `## Deviations`
   (`spec-evidence.md` section 3). Do not edit the approved text silently.
