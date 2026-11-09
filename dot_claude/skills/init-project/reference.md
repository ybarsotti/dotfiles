# init-project reference

Long procedures of the `init-project` skill. Read only the section that the skill names.

## Create the GitHub repository

1. Read the owner: `gh api user --jq .login`. When `gh` is not signed in, ask the user to run
   `gh auth login`, and skip this section.
2. Create the repository and push `main`:

   ```bash
   gh repo create <owner>/<name> --private --source . --remote origin --push   # or --public
   ```

3. Let GitHub Actions open pull requests, which release-please needs:

   ```bash
   gh api -X PUT repos/<owner>/<name>/actions/permissions/workflow \
     -F can_approve_pull_request_reviews=true -f default_workflow_permissions=write
   ```

4. Protect `main` with the one required check, `all-green`:

   ```bash
   gh api -X PUT repos/<owner>/<name>/branches/main/protection --input - <<'JSON'
   {"required_status_checks": {"strict": false, "contexts": ["all-green"]},
    "enforce_admins": false, "required_pull_request_reviews": null, "restrictions": null}
   JSON
   ```

   GitHub refuses branch protection on a private repository of a free personal account
   (HTTP 403). Report that answer and go on. Do not make the repository public to get it.
5. Say that the first Release PR appears after the first Conventional Commit on `main` that
   touches an app folder. `chore:` commits make no release.

## Apply the agent telemetry settings

Only after the user says yes to this exact change. `--yes` never applies it.

- Find the file that owns the setting. When `chezmoi source-path <file>` succeeds, chezmoi
  manages the file: edit the source file that it prints, show the diff, and tell the user to run
  `chezmoi apply <file>`. Do not run the apply.
- Otherwise copy the file to `<file>.bak-<YYYYMMDDHHMMSS>` first. Never overwrite the file with
  new content. Change only the keys of the snippet.

Claude Code (`~/.claude/settings.json`), with the snippet values of `docs/observability.md`:

```bash
f=~/.claude/settings.json
cp "$f" "$f.bak-$(date +%Y%m%d%H%M%S)"
jq --argjson add '<the "env" object of the snippet>' '.env = ((.env // {}) + $add)' "$f" > "$f.new"
jq empty "$f.new" && mv "$f.new" "$f"
```

Codex (`~/.codex/config.toml`): when the file has no `[otel]` table, copy it to a backup, then
append the table of the snippet with `>>`. When an `[otel]` table exists, show both versions and
let the user merge them.

## Audit

The audit writes one file, `docs/audit/<YYYY-MM-DD>-conformance.md`. It changes nothing else
until the user approves an adopt step.

### 1. Before you start

- Serena can rewrite `.serena/project.yml` when the session starts, before this skill runs.
  When `git status --porcelain` shows that file as modified, read `git diff` of it. When the
  diff only adds keys and changes comments, and no existing value changes, Serena made it:
  run `git restore .serena/project.yml` and say so in the report. Otherwise leave the file as
  it is and note that it was dirty before the audit.
- Record `git status --porcelain` and the list of untracked files. Step 4 compares against
  them.
- Find a template folder for the scripts. Use the local clone. When only the remote exists,
  clone the tag into a temporary folder: `git clone -q --depth 1 --branch <tag> <url> <tmp>`.
  Below, `TPL` is that folder.

### 2. Detect the apps

1. Find the stack manifests, at most three levels deep, outside `node_modules`, `.venv`,
   `vendor` and `dist`: `package.json`, `pyproject.toml`, `go.mod`, plus `Gemfile`, `Cargo.toml`,
   `pom.xml` and `build.gradle*` for other stacks. A root manifest of a workspace is not an app.
2. Find the framework of each app from its dependencies, and map it to a pack:

   | Dependencies | Pack |
   |---|---|
   | `react` and `@tanstack/react-router` | `react-tanstack` |
   | `hono` and `@trpc/server` | `hono-trpc` |
   | `django-ninja` (or `django`) | `django-ninja` (partial for plain Django) |
   | `fastapi` | `fastapi` |
   | `go.mod` | `go` |
   | anything else | no pack: the stack name |

3. Note for each app: the folder, the stack, the pack, the package manager, the test runner,
   the type checker, the linter, and whether it exports OpenTelemetry (an `opentelemetry`
   dependency).

### 3. Run the conformance report

When the apps are not under `apps/` and the project has no `project.json`, write a temporary one
and remove it in the same command:

```bash
printf '{"apps": ["frontend", "backend"]}\n' > project.json
node "$TPL/core/scripts/conformance.mjs" --root . --report <scratch>/conformance.md
rm -f project.json
```

Exit code 1 means that a required check fails. It is a result, not an error. Never leave the
temporary `project.json` behind.

### 4. Run the project's own commands

Run what the project already has, in read-only form, and record the command, the exit code, the
duration and the last relevant lines:

- install with the lockfile frozen: `pnpm install --frozen-lockfile`, `npm ci`,
  `uv sync --frozen`, `go mod download`;
- lint, type check, test and build: the scripts of `package.json`, the `justfile` or `Makefile`
  targets, else the tools of the manifest (`uv run --frozen ruff check`, `uv run --frozen
  pytest`, `go vet ./...`, `go test ./...`);
- `docker compose config --quiet`, when a compose file exists.

Never run a formatter in write mode, a `--fix` flag, a migration, a `--update-snapshots` flag
or a dependency upgrade. Give each command at most 10 minutes. End-to-end browser tests count
as optional: record a skip when the browsers are not installed.

After the commands, compare `git status --porcelain` and the untracked files with step 1. When
a command changed a tracked file that was clean before, restore that file with
`git restore -- <file>` and record that the command writes files. Delete only new untracked
files that a command created. Never touch a file that was dirty before the audit.

### 5. Write the report

`docs/audit/<YYYY-MM-DD>-conformance.md`, in this order:

1. **Summary**: the apps (folder, stack, pack), the template ref, and the required score.
2. **Score per area**: the table of the conformance report.
3. **Required misses** and **Recommended misses**, from the conformance report. Add these rows
   as `recommended` when they are missing:
   - releases: `release-please-config.json`, `.release-please-manifest.json`,
     `.github/workflows/release.yml`, one package and one version per app;
   - telemetry: an OTLP export in each server app, the `telemetry` key in each `app.json`, the
     `otel` service in the root `compose.yaml`, and the `OTEL_*` keys in `env.example`.
4. **Existing commands**: a table of command, exit code, duration and the key lines.
5. **Judgement findings** that no script checks, each with a file reference:
   - `CLAUDE.md` or `AGENTS.md` text that restates the code;
   - architecture rules that exist only as prose;
   - tests that mock the project's own modules instead of the outermost external call.
6. **Adopt plan**: the steps of section 6, each with its files and its check.

Write no secret and no value of an env file into the report.

### 6. The adopt plan

Propose small steps. Each step is reversible, has one commit, and never moves application code:

1. **Core agent files**: `CLAUDE.md` router, `AGENTS.md` links, `REVIEW.md`, `ARCHITECTURE.md`,
   `docs/adr/`, `.claude/settings.json` with the hooks, `.claude/rules/`, `.mcp.json`,
   `.serena/project.yml`. Merge with the files that the project already owns.
2. **Task-runner contract**: the root `justfile`, `project.json` when the apps stay where they
   are, and one `justfile` per app that wraps the commands of step 4.
3. **Architecture fitness**: encode the layering that the code already follows
   (import-linter, dependency-cruiser or a Go `arch_test.go`). When the rule fails on day one,
   record the current violations in a baseline file. The check then fails only on a new
   violation.
4. **Git hooks and CI**: `.pre-commit-config.yaml`, the commit-msg hook, `ci.yml`,
   `security.yml`, `renovate.json`, and one `ci/action.yml` per app.
5. **Containers**: one `Dockerfile` with `dev` and `prod` stages and one `compose.yaml` per app,
   the root `compose.yaml` with the sync-apps markers, `compose.prod.yaml`.
6. **Releases**: `release-please-config.json`, `.release-please-manifest.json` and
   `release.yml`. `just sync-apps` adds each app to both files.
7. **Observability**: the `otel` service, the `OTEL_*` keys in `env.example`, one telemetry
   module and one telemetry test per server app, `OTEL_SERVICE_NAME` in each app service.
8. **Workflow verifier**: `.workflow/` with its config, modes and scripts.

Ask which steps to apply with `AskUserQuestion` (multi-select). With `--yes`, do not ask:
print the plan and stop.

### 7. Apply an approved step

1. Render the core into a temporary folder with the project's answers:
   `COPIER --data kind=core --data project_name=<name> ... <SRC> <tmp>`.
2. Copy the files of the step that the project does not have. Merge by hand each file that the
   project already owns, and show the merge.
3. Run the green loop of the skill (`just setup`, `just conformance`, `just check`, `just up`,
   `just down`) when the step makes those recipes exist. Otherwise run the project's own
   commands of step 4.
4. Commit the step alone: `chore(adopt): <step>`.
