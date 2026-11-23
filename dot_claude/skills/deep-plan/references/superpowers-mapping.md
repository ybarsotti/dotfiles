## Superpowers workflow mapping

This pipeline implements the **planning half** of the canonical
[obra/superpowers](https://github.com/obra/superpowers) workflow, then hands off the
execution half. Invoke each planning-phase skill via the Skill tool at its mapped phase —
**mandatory workflows, not suggestions.**

| # | superpowers / skill | deep-plan phase | run by |
|---|---------------------|----------------|--------|
| 0 | `grilling` + `domain-modeling` | Phase 0.7 | deep-plan |
| 1 | `brainstorming` | Phase 1 | deep-plan |
| 2 | `_shared/plan-format.md` (replaces `writing-plans`) | Phase 1.5 | deep-plan |
| 2b| `/qa-plan` | Phase 2.4 when user flows/screens change | deep-plan |
| 3 | `_shared/plan-page.md` (plan page) | Phase 3 (present) | deep-plan |
| 4 | `plannotator annotate --gate` | Phase 3 (annotate) | deep-plan |
| — | — | **handoff** ↓ | **`/deep-execute` or `implement`** |
| 4 | `using-git-worktrees` | execution | executor |
| 5 | Orca workers with the predefined agents (`_shared/orca-workers.md`); the `Agent` tool outside Orca | execution | executor |
| 6 | `test-driven-development` | execution (per task) | executor |
| 6b| `systematic-debugging` | execution (bug/regression tasks) | executor |
| 6c| `dispatching-parallel-agents` | execution (fallback for parallel slices) | executor |
| 7 | `/deep-review` + `receiving-code-review` + `qa-ui`/`qa-business` agents | execution | after-approval |
| 8 | `/pr` with its watch (never `finishing-a-development-branch`, which stops to ask) | execution | after-approval |

Plus deep-plan adds: multi-model planner/reviewer fan-out, the `ticket-matcher` reviewer,
code-intel bootstrap, and the machine-validated checklist gate.
