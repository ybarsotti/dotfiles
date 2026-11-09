---
description: Create a monorepo from the AI monorepo template, add an app to one, or audit any project against its app contract — renders with Copier and loops until conformance, check and the containers pass
argument-hint: [new|add|audit] [--name x] [--apps name:kind,...] [--services postgres,redis,mailpit] [--github private|public|none] [--yes]
---

# /init-project

Create, extend or audit a project with the AI monorepo template.

**Arguments:** `$ARGUMENTS`

```text
/init-project [new|add|audit] [--name x] [--apps name:kind,...]
              [--services postgres,redis,mailpit] [--github private|public|none] [--yes]
```

- **new**: an empty folder. It renders the core and one app per `--apps` entry.
- **add**: a project that the template made (`.copier-answers.yml`). It adds the apps.
- **audit**: any other project, or the `audit` argument. It writes
  `docs/audit/<date>-conformance.md` and changes nothing else until you accept the adopt plan.

With no mode, the folder decides. The pack kinds are `react-tanstack`, `django-ninja`,
`fastapi`, `go` and `hono-trpc`. Any other kind is built against `docs/app-contract.md`.
`--yes` takes the defaults and asks nothing. Without it, the command asks for each missing
value.

## What you must do

Invoke the `init-project` skill. The skill lives at `~/.claude/skills/init-project/SKILL.md`,
with the long procedures in `reference.md` next to it. Follow its sections exactly. In Codex,
read that `SKILL.md` by path and follow it; ask each question in the chat instead of
`AskUserQuestion`.

## Examples

```bash
/init-project new --name demo --apps api:fastapi,web:react-tanstack --services postgres --github none --yes
/init-project add --apps worker:go --yes
/init-project audit
```
