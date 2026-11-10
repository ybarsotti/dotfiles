---
name: init-project
description: Create, extend or audit a monorepo with the AI monorepo template. Use when invoked via /init-project, or when the user asks to start a new project from the template, to add an app (react-tanstack, django-ninja, fastapi, go, hono-trpc, or another stack) to a project made from it, or to audit an existing project against the template's app contract. New and add modes render with Copier and loop until conformance, check and the containers pass, then set up releases, telemetry, the code index and the commit. Audit mode writes a report and changes nothing else until the user accepts an adopt plan.
---

# init-project

One command, three modes. **new** creates a project in an empty folder. **add** adds apps to a
project that the template made. **audit** measures any other project against the app contract
and proposes small adopt steps. Read `reference.md` (next to this file) when a step names it.

**Arguments:**

```text
[new|add|audit] [--name x] [--apps name:kind,...] [--services postgres,redis,mailpit]
[--github private|public|none] [--yes]
```

## Rules

- **`--yes` means no questions.** Take the default of each missing value. Stop with a clear
  message only when a value has no default (add mode without `--apps`). `--yes` never approves
  the audit adopt plan and never applies the agent telemetry settings.
- Without `--yes`, ask for the missing values in one `AskUserQuestion` call. Ask nothing that
  an argument already answers.
- Never read or write `.env`. Read `env.example` for the variable names. In add and audit
  modes, the project hooks can be active: write each value out, and do not put a `$` variable
  and the word `env` in one shell command.
- Change generated files through their recipe, never by hand: lockfiles, `openapi.json`,
  `generated/` folders, `compose.prod.yaml` and the sync-apps blocks.
- Fix a failure at its root cause. Never skip a test, never add `# noqa`, `# type: ignore` or
  `eslint-disable`, never weaken a check, never commit with `--no-verify`.
- Docker: act only on this project's compose project. Never prune, and never remove a volume or
  an image that this run did not create.
- Do not push with `--force`. Create a GitHub repository only when `--github` asks for one.

## 1. Detect the mode

Ignore `.git` and `.DS_Store` when you check if the folder is empty.

| Folder | Mode |
|---|---|
| Empty | new |
| `.copier-answers.yml` with `kind: core`, and `_src_path` ends with `ai-monorepo-template` (or `ai-monorepo-template.git`) | add |
| Any other content, or the `audit` argument | audit |

When the argument names a mode that the folder does not allow, say why and use the mode of the
table. A `new` request in a folder with files becomes an audit. Report the mode and the reason
in one line.

## 2. Resolve the template

```bash
GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=5' git ls-remote --tags --refs \
  git@github.com:ybarsotti/ai-monorepo-template.git 2>/dev/null | sed 's|.*refs/tags/||' | sort -V | tail -1
```

- A tag comes back: the repository `gh:ybarsotti/ai-monorepo-template` is private, so pass it
  to Copier as `SRC=git@github.com:ybarsotti/ai-monorepo-template.git`, with `REF=<tag>`.
- Nothing comes back: use the local clone `SRC=$HOME/Developer/Pers/ai-monorepo-template` with
  `REF=HEAD`. Copier then includes uncommitted template changes and warns about them.
- Neither exists: stop and say so.

Say which source and ref you used. In add mode, use `_src_path` of the root answers file when
it is reachable, so the new app comes from the same template as the core.

Every Copier call uses `uvx copier@9.19.1 copy --trust --defaults --quiet --vcs-ref=<REF>`.
Below, `COPIER` stands for that prefix. Write it out in each command, or wrap it in a shell
function, because zsh does not split a variable into words.

## 3. Collect the answers

- **Name** (`--name`): lowercase letters, digits and dashes, starting with a letter. Default: the
  folder name in that form.
- **Apps** (`--apps name:kind,...`): the same name rule. The pack kinds are `react-tanstack`,
  `django-ninja`, `fastapi`, `go` and `hono-trpc`. Any other kind is a stack with no pack
  (section 6). Default in new mode: no app. The Copier validator rejects names that shadow a
  library or a Go standard package; propose `<name>-app` or ask.
- **Services** (`--services`): any of `postgres`, `redis`, `mailpit`. Default: none.
- **GitHub** (`--github`): `private`, `public` or `none`. Default with `--yes`: `none`. Default
  when you ask: `private`.

Derived values:

- Language of a kind: `react-tanstack` and `hono-trpc` are node, `django-ninja` and `fastapi`
  are python, `go` is go. The core needs no language answer: `sync-apps` derives the language
  lists from each `app.json`.
- A `react-tanstack` app talks to one backend. With a `hono-trpc` app, pass `api=trpc` and
  `api_app=<that app>`. Else, with a `fastapi`, `django-ninja` or `go` app, pass `api=openapi`
  and `api_app=<the first one>`. Else pass `api=none`.
- `database` (Python packs) follows the core services. Do not pass it.
- **Port.** Every app needs its own default host port. Count the ports of the apps that exist
  (`grep -ho '_PORT:-[0-9]*' apps/*/compose.yaml`). Start at 5173 for `react-tanstack` and at
  8000 for the other kinds. Take the first port that no app uses and that
  `lsof -nP -iTCP:<port> -sTCP:LISTEN` shows as free. Pass it as `--data port=<port>`.
- When the otel ports 18888, 4317 or 4318 are busy, choose free ones. Put
  `OTEL_UI_PORT=<p> OTEL_GRPC_PORT=<p> OTEL_HTTP_PORT=<p>` before each `just up` of this run, and
  tell the user to add those lines to `.env`.

## 4. New project

1. `git init -b main` when the folder is not a repository.
2. Render the core:
   `COPIER --data kind=core --data project_name=<name> --data 'services=[...]' <SRC> .`
3. Render each app with a pack. Render the backends first, because a frontend reads its
   backend's `openapi.json`:
   `mkdir -p apps/<app>`, then
   `COPIER --data kind=<kind> --data app_name=<app> --data port=<port> [--data api=... --data api_app=...] <SRC> apps/<app>`.
   The pack reads `../../.copier-answers.yml`, so the folder must exist first.
4. Build each app without a pack (section 6).
5. `just sync-apps`.
6. Run the green loop (section 7).
7. Releases (section 8), observability (section 9).
8. The first commit, then the code index (section 10).
9. GitHub (section 11), when `--github` is `private` or `public`.
10. When an app has no pack, offer to turn it into a new pack of the template. Do not do it.
11. The final report (section 13).

## 5. Add an app

1. Note whether `git status --porcelain` is empty. Read the root `.copier-answers.yml` and
   `ls apps/`. Refuse a name that already exists under `apps/`. When Serena rewrote
   `.serena/project.yml` and dropped the sync-apps markers (a core older than the full Serena
   file), restore the file with `git restore .serena/project.yml` and report it.
2. Render each new app as in section 4, step 3. When the root has no `.npmrc` (a core older
   than v0.3.0), copy `core/.npmrc` of the template to `.npmrc`.
3. Build each app without a pack (section 6).
4. `just sync-apps`, the green loop, releases and observability, as in new mode.
5. When the tree was clean at step 1, commit `feat(<app>): add the <app> app` through the
   project hooks, then run `just index`. Otherwise leave the changes uncommitted and say so.
6. The final report.

## 6. An app without a pack

1. Read `docs/app-contract.md` of the project and the official documentation of the stack (use
   Context7 when it is available). Read one pack app of the template as the example of the
   shape.
2. Write the app in `apps/<app>/` against every `required` item of the contract: the recipes,
   the two Dockerfile stages with a non-root `prod` user, the compose service with
   `healthcheck`, `develop.watch` and `OTEL_SERVICE_NAME`, `ci/action.yml`, `app.json` with
   `telemetry`, the `CLAUDE.md` files with `AGENTS.md` links, a health route, a telemetry test
   and an `arch` recipe that fails on a forbidden import. Use the port of section 3.
3. Pin every dependency version. Generate lockfiles with the package manager.
4. `just conformance` validates the result inside the green loop.

## 7. The green loop

At most 10 rounds. A round runs these steps in order, and stops at the first failure:

1. `just setup`
2. `just conformance`
3. `just check`
4. `just up`
5. `just down`

After a failure, read the full output, fix the root cause in the project, and start the next
round. When the cause is a template defect, fix it in the project and record it for the final
report. After 10 rounds, stop and report each failure that remains, with its last output lines.
Run `just down` when a round fails after `just up`.

## 8. Releases

1. Every app needs a package in `release-please-config.json` and a version in
   `.release-please-manifest.json`:
   `jq -r '.packages | keys[]' release-please-config.json` and
   `jq -r 'keys[]' .release-please-manifest.json` each list `apps/<app>` for every app.
2. `just version` prints one line per app.
3. When an app is missing, run `just sync-apps` again. When it is still missing, report it.

## 9. Observability

Run this when `env.example` has `COMPOSE_PROFILES=observability`, after the loop passes.

1. `just up`.
2. Send one request to each app whose `app.json` has a `telemetry` object. The request must
   write a log line, so the health route and `GET /api/items` do not count. In the packs,
   `POST /api/items` logs:
   `curl -fsS -X POST -H 'content-type: application/json' -d '{"name": "Lamp"}' "http://$(docker compose port <app> 8000)/api/items"`.
   For an app without a pack, use a route from its `openapi.json` that writes a log line.
3. `just otel-check`. A failure here is a loop failure: fix it and run it again, inside the
   10-round limit.
4. `just down`.
5. Print the dashboard URL (`http://localhost:18888`, or the `OTEL_UI_PORT` you chose) and where
   to look: Traces (one row per request), Structured logs (filter by `trace_id`), Metrics, and
   the GenAI button on a `chat` span.
6. Print the agent telemetry snippets of the section "Agent telemetry" of
   `docs/observability.md`, with `<project>` replaced. Do not apply them.
7. Without `--yes`, offer to apply them to the user's own Claude Code or Codex settings, as a
   separate question. Apply only on an explicit yes, with the procedure in `reference.md`
   ("Apply the agent telemetry settings").

## 10. First commit and code index

1. Confirm that `.serena/project.yml` exists and that its language list holds every language
   of the apps. When it does not, run `just sync-apps` and report the result.
2. `git add -A`, then `git commit -m "chore: initial project scaffold"`. The project hooks run.
   When a hook fails, fix the cause, stage again and commit again. Use the user's git identity
   and signing settings. When signing fails, report it and stop; do not turn signing off.
3. `just index`. It builds the GitNexus index, which needs a commit. `.gitnexus/` stays
   ignored.

## 11. GitHub

Only when `--github` is `private` or `public`. Follow `reference.md` ("Create the GitHub
repository"). It creates the repository and pushes `main`. It lets GitHub Actions open pull
requests, and it protects `main` with the required check `all-green`. Tell the user that the
first release PR appears after the first Conventional Commit on `main` that touches an app.

## 12. Audit

Follow `reference.md` ("Audit"). In short:

1. Undo a Serena rewrite of `.serena/project.yml` from the session start, then record the git
   state. Detect the apps, their stacks and the matching packs.
2. Run the conformance report from the template, with a temporary `project.json` when the apps
   are not under `apps/`. Remove the temporary file at once.
3. Run the project's own commands in read-only form, and record each result.
4. Write `docs/audit/<YYYY-MM-DD>-conformance.md`. It is the only file the audit writes.
5. Propose the adopt plan. Apply a step only after the user approves it in this conversation.
   With `--yes`, stop after the report and print the plan.
6. Confirm with `git status --porcelain` that the report is the only change.

## 13. Final report

Keep it short. Include:

- the mode, the template source and ref, and the reason for the mode;
- what the run created: the core, each app with its kind and port, the services;
- the round count of the green loop, and each failure that remains;
- the commit hash, and the GitHub URL when one exists;
- the dashboard URL and the result of `just otel-check`;
- the commands: `just dev`, `just check`, `/release`, `/release-announce`,
  `just release-notes`, `just version`, `just otel-check`;
- each template defect you worked around, and each port line the user must add to `.env`.

For an audit: the report path, the score, the top misses, and the adopt steps.
