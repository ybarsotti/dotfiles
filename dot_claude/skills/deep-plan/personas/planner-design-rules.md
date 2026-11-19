## Design rules

Invoke the `ub-mode` skill before you plan. Without the Skill tool, read
`~/.claude/skills/ub-mode/SKILL.md`. The plan applies its "First Make it Work" rules: the data
shape first, a domain model that makes illegal states impossible, data checked where it
enters, a redesign instead of a bolt-on, subtraction before addition, idempotent operations,
and one writer per shared state. Split the work into verifiable units. Each unit's check
includes the "Then Make it Right" gates on its files: `crapper` under CRAP 10, `dryer` under
0.8, and `mutator` with no surviving or uncovered mutant.
