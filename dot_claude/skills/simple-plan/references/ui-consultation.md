# UI/UX consultation

This file belongs to `simple-plan`. `SKILL.md` names the step that needs it.

Before drafting, when the task adds or changes a user-facing screen, component, page or
layout, consult the design intelligence and dispatch one UI/UX agent:

0. Read `~/.claude/skills/_shared/ui-quality.md`. It is the quality bar the plan, the
   implementer and the reviewers share.
1. `Skill(skill="ui-ux-pro-max:ui-ux-pro-max")` for this project's stack — styles, palettes,
   font pairings, UX guidelines, motion presets and component guidance.
2. One `Agent` with the reviewer persona at
   `~/.claude/skills/deep-review/personas/ui-ux.md`, pointed at the **existing** UI rather
   than at a diff. Give it `$RUN_DIR/context.md`, `~/.claude/skills/simple-plan/references/constraints.md` and the task description, and ask for: the
   components and design tokens this change should reuse, with `path:line`; the screen the new
   one should follow as a pattern; the states it must design for; where the component
   boundaries fall and where the logic goes; the feedback the user needs for each action; the
   breakpoints this project supports and how the layout reflows at the narrowest one; and the
   accessibility this screen owes — keyboard path, focus handling on anything that opens, the
   accessible name of every icon-only control, and how errors get announced.

The plan states the breakpoints and the keyboard path as acceptance criteria, not as good
intentions. A screen whose plan is silent about them gets built without them.

3. Start the `ui-designer` agent as an Orca worker with `--keep-open`
   (`~/.claude/skills/_shared/after-approval.md`, "Parallel agents run in Orca"). Give it the
   app URL or run command. It maps the project's design system from the code, reads and
   screenshots the screens it changes, then draws them on a Design canvas while you draft. The user can iterate on the canvas in parallel. Record its `Canvas:`, its `Design images:` folder and
   `Design system:` URLs in the UI design pass.

Fold the answer into the plan's `UI design pass` section, and into `Project fit`, `Affected
files` and `Edge cases`. The plan names the existing component it reuses instead of leaving
the implementer to invent one.
`Skill(skill="frontend-design:frontend-design")` applies when the change needs visual direction rather than
pattern-matching.

Skip this when the change touches no interface, and record that you skipped it.
