---
name: release-watch
description: Use when a feature flag was just turned on in production, a risky deploy shipped (auth, checkout, payment, data), or the user asks to monitor logs, Sentry or a release after it shipped. Watches every 10 minutes in the first hour, then hourly, triages each new error against the release time, and ends with a go or no-go report. Not for an incident already in progress.
---

# release-watch

Most regressions of a release show in the first hour. Others grow with adoption during the
day. This skill watches at that pace: every 10 minutes while the risk is high, then every
hour. Each window ends with one report. Each finding goes from "an alert fired" to a proven
root cause, a fix, and a verified drop of the error in production.

## Inputs

Get these first. Ask only for what you cannot find yourself:

- **what shipped**: the flag, the PR or the deploy;
- **when**: the exact time. Every triage decision compares against it;
- **which apps** the change can break;
- **how long** to watch. The default is 1 hour every 10 minutes, then hourly until the end
  of the day.

When `/release` cut the release, read its release review. Its watch plan names the apps,
the signals and the thresholds.

## Run it in its own session

Each check rereads the whole context of the session that runs it. Start the watch in a new
session, or as an Orca worker on Sonnet, with only this skill and the inputs above. Do not
run it in the long session that built the change.

## Phase 0 — Surfaces and baseline

1. List every place where the apps report errors. Sentry alone is not enough: a service
   without a Sentry project fails silently. For each app, find its error tracker project and
   its log groups (CloudWatch, Datadog, Logfire or the platform logs). The project
   `CLAUDE.md` or the project memory often lists them.
2. Take a baseline: query the errors of the 1 to 2 hours before the release. Mark each error
   that already fired as pre-existing. Note it and do not chase it.
3. Tell the user what was already broken, what you will watch, and the threshold of each
   watched item.

## Cadence

| Phase | Tool | Cadence | Ends with |
|---|---|---|---|
| Hot window (1 to 2 h after the release) | `CronCreate`, recurring | every 10 min, off the hour (`2,12,22,...`) | window report, then `CronDelete` |
| Stable (rest of the day) | `CronCreate`, recurring | hourly, off the hour (`41 * * * *`) | day report, then `CronDelete` |

- **The cron prompt is self-contained.** It names the release time, the end of the window,
  the baseline to compare against, and the instruction to write the final report and run
  `CronDelete` when the window ends.
- **Each check reports only what changed**: new issues since the last check, rate changes
  on watched items, and crossed thresholds. When nothing changed, say so in one sentence.
- **One job per cadence.** To change the cadence, delete the old job and create a new one.
- **A recurring mitigation is a step of the same cron prompt**, not a second job.
- **Never schedule on `:00` or `:30`.** Every scheduled job on the fleet fires then.

## Triage of each finding

1. **Compare the timeline first.** An error whose first event is before the release and
   whose rate is stable is pre-existing. An error that is new or that speeds up after the
   release needs investigation now.
2. **Find the root cause in the code, not on the dashboard.** Read the failing path end to
   end, across services. A root cause is proven when you can:
   1. name the exact line or mechanism;
   2. reproduce it (a 10-line simulation counts);
   3. match it to the production evidence (status codes, log bodies, timestamps).
3. **Set a number when you first report a finding**, for example "escalate above 12 per
   hour" or "2× the baseline". Hold to it in later checks.
4. **Read the evidence before you raise an alarm.** A fixed bug that "comes back" can be
   another failure with the same title. Read the new response bodies and status codes.

| Signal | Priority |
|---|---|
| Blocks login, checkout or revenue | Discuss a rollback now |
| A user sees a failure, and the rate grows with adoption | P1, fix today |
| A customer cannot recover an account | P1, and a manual mitigation now |
| A failure that a try/catch hides, with no user impact yet | P2. Count it: silent is not harmless |
| Pre-existing at a stable rate | Note it in the report, separate ticket |
| Browser noise, third-party errors outside the change | Discard with one line of evidence |

**Mitigate, then fix.** When customers are stuck:

1. Ship a mitigation first: a manual action, or a script that keeps a list of the targets it
   handled. Never run a mitigation twice against the same target.
2. Ship the code fix: a draft PR with a test, through `/ship-it`.
3. Verify the fix in production: the error rate must drop to zero after the deploy. A merged
   PR is not a verified fix.

## Reports

Each report starts with the verdict.

- **Check**: only what changed. "All clean" is one sentence.
- **Window**: the verdict ("the flag can stay on"), then each bug with its root cause, fix
  and verification, the mitigations, and the open items with their owners.
- **Day**: a table of bugs found and fixed, customers helped and PRs; the timeline; the
  open items for the next day. Publish it as an HTML artifact. Save each lasting finding
  (log group locations, links between bugs, open decisions) to the project memory.

## Common mistakes

| Mistake | Correction |
|---|---|
| Watching only Sentry | Check the logs of every app the change can break |
| A cron prompt that says only "check for errors" | Each run carries the release time, the window end, the baseline and the delete instruction |
| Repeating the baseline in each check | Report only what changed |
| Calling a fix verified because the PR merged | Verified means the error rate dropped in production after the deploy |
| Chasing a pre-existing bug as a regression | The first event time against the release time decides |
| Leaving the cron jobs running | Each window ends with a report and `CronDelete` |
