# Manual Test Plan — <feature>

> **Manual** test plan: the steps a human runs on-screen. Every step names a screen, where to
> click, what to type, and the expected result. This is **not** automated test code.

## Scope & change summary

- **Ticket / plan:** <KEY-123 or plan path, if any>
- **What changed:** <1–3 sentences describing the user-facing change>
- **App URL:** <base URL of the running app under test>
- **Affected screens:** <list the screens/routes this touches>

## Preconditions / test data

- <accounts, seed data, feature flags, env the tester needs before starting>
- <e.g. a standard user `qa+user@example.com`, an admin `qa+admin@example.com`>
- <e.g. a product in the catalog with stock > 0>

## Personas / roles under test

- **<role A>** — <who they are, what they can do>
- **<role B>** — <who they are, what they can do>

---

## Scenario 1: <name>

**Role:** <which persona runs this scenario>
**Precondition:** <exact state before step 1 — logged in as X, on screen Y, cart empty, etc.>

**Steps:**

1. Screen: <screen/route> • Action: <where to click / which control> • Input: <what to type, or —> • Expected: <what the tester should see>
2. Screen: <…> • Action: <…> • Input: <…> • Expected: <…>
3. Screen: <…> • Action: <…> • Input: <…> • Expected: <…>

**Edge cases:**

- <invalid input / empty state / permission denied / back or refresh mid-flow / boundary value / error response> → Expected: <result>
- <…> → Expected: <…>

**Acceptance rules:**

- <objective, checkable pass/fail criterion — e.g. "order confirmation shows the correct total incl. tax">
- <…>

---

## Scenario 2: <name>

**Role:** <persona>
**Precondition:** <state before step 1>

**Steps:**

1. Screen: <…> • Action: <…> • Input: <…> • Expected: <…>
2. Screen: <…> • Action: <…> • Input: <…> • Expected: <…>

**Edge cases:**

- <…> → Expected: <…>

**Acceptance rules:**

- <…>

---

<!-- Repeat "## Scenario N" blocks for every distinct flow + role combination. -->

## Artifacts

<!-- Filled by the browser executor. -->

- **Video:** ./tmp/<slug>.webm
- **Screenshots:** ./tmp/<slug>-<scenario>-<state>.png (one or more)
- **Auth state (if used):** ./tmp/<slug>-auth.json

## Execution report

<!-- Filled by the browser executor after the run. Mirror of <slug>-qa-report.md. -->

| Scenario | Result | Notes |
|----------|--------|-------|
| Scenario 1: <name> | PASS / FAIL | <failing step + why, if any> |
| Scenario 2: <name> | PASS / FAIL | <…> |

**Overall verdict:** <e.g. 4/5 scenarios pass, 1 fail>
