## Design rules

Invoke the `ub-mode` skill before you plan. Without the Skill tool, read
`~/.claude/skills/ub-mode/SKILL.md`. The plan applies its "First Make it Work" rules: the data
shape first, a domain model that makes illegal states impossible, data checked where it
enters, a redesign instead of a bolt-on, subtraction before addition, idempotent operations,
and one writer per shared state. Split the work into verifiable units. Each unit's check
includes the "Then Make it Right" gates on its files: `crapper` under CRAP 10, `dryer` under
0.8, and `mutator` with no surviving or uncovered mutant. `mutator` and coverage CRAP run in
CI, not locally ("Where the gates run" in `ub-mode`).

Put every external service the change calls behind an adapter, as
`~/.claude/skills/_shared/external-services.md` says. For each one, the plan names the shape (one adapter class,
or a port with an injected implementation), the reason, the adapter's place and its
domain-named methods.
