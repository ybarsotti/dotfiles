# Proofs (Phase 0.5)

2. **Run each proof at HEAD.** Take the plan's `## Evidence map`. Without one, build the rows
   from the requirements matrix, the `## Rules` table and the `Cover now`/`Fail loudly` edge
   cases, and find the test that proves each one in the diff. Run every `test` and `command`
   proof. Link every `qa` proof to the `--evidence` artifact. Write one line per row to
   `$RUN_DIR/evidence.tsv`: id, claim, proof, result (`pass`, `fail`, `not run: <reason>`),
   and the short SHA of HEAD.
3. **A failed or missing proof blocks the PR.** Fix it, or ask the user to defer the row with a
   reason. Never write `pass` for a proof that did not run.
4. **Deviations.** Copy the plan's `## Deviations` rows, or `None`.
