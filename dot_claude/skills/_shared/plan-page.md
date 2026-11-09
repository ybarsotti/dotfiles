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
3. Reuse the Mermaid diagrams of the plan. Do not draw a second version of a diagram.
4. Write the page beside the plan as `plan.html` (`$RUN_DIR/plan.html` or
   `${PLAN_PATH%.md}.html`). Follow the Plan path structure: summary strip, timeline, SVG flow,
   risks, open questions.
5. Run the gate:

   ```bash
   plannotator annotate plan.html --gate
   ```

6. Map each annotation back to its section in `plan.md`. Edit `plan.md`, then render the page
   again.
7. Repeat steps 5 and 6 until the user approves with no annotations.

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
4. Put the page URL in the `ExitPlanMode` summary.
5. Before `ExitPlanMode`, read the page comments with `ArtifactComments`. Treat each comment as
   an annotation from step 6 of section 1.
6. After the stamp (`plan-stamp.sh approve`), publish the page again with an "Approved" banner
   and the stamp hash from `plan-stamp.sh hash`.
7. A comment that arrives after the approval is a deviation. Record it in `## Deviations`
   (`spec-evidence.md` section 3). Do not edit the approved text silently.
