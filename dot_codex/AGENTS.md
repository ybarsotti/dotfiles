# Global AGENTS.md

@RTK.md

# Code Intelligence

Use the code-intelligence MCP servers in `~/.codex/config.toml` when they are available.

## Serena
- The `serena` MCP server starts with `--context codex --project-from-cwd`, so it activates the project of the current folder.
- Use Serena for exact symbol lookup, references and surgical symbol edits. Prefer it to raw `grep` and whole-file reads.
- If Serena is unavailable, continue with normal file reads. Mention the gap only when it lowers your confidence.

## GitNexus
- If the project has a `.gitnexus/` index, use the `gitnexus` MCP server for architecture, execution flows and blast radius.
- Before you change a function, class or method in an indexed project, run GitNexus impact analysis on it. Warn before you edit when the risk is HIGH or CRITICAL.
- If GitNexus reports a stale index, run `gitnexus analyze --index-only` from the project root first.

## Graphify
- If `graphify-out/GRAPH_REPORT.md` exists, read it before broad architecture questions.
- After code changes in a project with `graphify-out/graph.json`, run `graphify update .` when practical.

## Other MCP servers
- Use the configured MCP servers before a workaround: `context7` for library docs, `obscura` for local pages, `atlassian` for Jira and Confluence, `slack`, `logfire`, `ai-memory` and `memory`.
- Project instructions override this section when they are more specific.

# Building Code

- When you write production code as a worker of the build chain, read
  `~/.claude/skills/_shared/implementer-rules.md` as your brief says.
- Before you write UI code, read `~/.claude/skills/_shared/ui-quality.md`.
- Never draw a mockup or layout of a screen from memory. Start from the real screens: read
  their code and components, and screenshot them when the app runs.
- Write code, identifiers, comments, docs and commit messages in English.
- Leave full suites, end-to-end runs and whole-project checks to CI. Push the branch and read
  the result with `gh pr checks`. Run a full suite locally only when the user asks for it.
- On this Mac, run focused tests through `~/.local/bin/test-local` with pytest, jest, vitest, or playwright from the package directory.
  The command runs serially in one of two slots that all local sessions share. When both slots are busy, it waits in a queue for up to 9 minutes. Give the Bash call a timeout of 600000 ms, or run it in the background. Do not write a retry loop: exit 75 means the queue stayed full, so do other work and try once more later.
  Do not bypass it with direct commands, containers, package scripts, or delegated workers.
  Do not use watch or UI mode.
- Implementation, fixes, QA and code review run on `gpt-6.1-terra`. `gpt-6.1-sol` is for plans,
  designs and brainstorming. When you start another Codex agent for code, pass
  `-m gpt-6.1-terra`.
- Open a pull request only with the `pr-description` skill (`/ship-it`). Never run `gh pr create`
  by hand.

# graphify

- **graphify** (`~/.Codex/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
- When user types `/graphify`, invoke Skill tool with `skill: "graphify"` before anything else.

# Browser and Web Navigation

Three browser tools serve three targets. Pick by where the page lives.

- **`kitesurf` MCP — the public web.** Cloudflare's remote headless browser for agents. It runs
  on Cloudflare Workers, so this machine installs no browser and the request leaves from
  Cloudflare. Use it to open a public URL, read a page, fill a form, click an element, take a
  screenshot, or scrape. It reads `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` from the
  environment. If it fails to authenticate, report the missing variable and stop.
  Docs: https://developers.cloudflare.com/browser-run/kitesurf/
- **`obscura` MCP — this machine's network.** A local headless browser written in Rust, with no
  Chrome. Use it for a `localhost` dev server, a private address, or any page kitesurf cannot
  reach from Cloudflare. `obscura serve --port 9222` also exposes a CDP endpoint that Playwright
  and Puppeteer connect to. Docs: https://github.com/h4ckf0r0day/obscura
- **A real browser** — for the user's logged-in profile, an Electron application, or QA evidence
  such as screenshots and video.

Prefer `kitesurf` for a public page. It costs this machine nothing and starts fastest.

# caveman

- Activate `caveman` skill in full mode by default every session.
- `/caveman lite|full|ultra` overrides current level.
- `stop caveman` or `normal mode` disables it for current session.

# Writing Style — Simplified Technical English

Anything you write that outlives the conversation follows **ASD-STE100** (Simplified
Technical English): docs, code comments, commit messages, PR and issue text, plans,
reports, and memory files. Write complete sentences with articles. This prose is not chat.

## Rules
- One instruction per sentence. Procedural sentences hold 20 words or fewer, descriptive ones 25.
- Paragraphs hold 6 sentences or fewer, and cover one topic each.
- Use the active voice and the present tense. Write "the script reads the manifest", not "the manifest is read".
- One word carries one meaning. Choose a term and reuse it. A lane stays a lane; never rename it for variety.
- Keep noun clusters to 3 words. Write "the script that validates run state", not "the run state validation script".
- State technical facts plainly. Do not use idiom, metaphor, or slang for them.
- Write sequential actions as separate sentences or numbered steps. Do not chain them into one sentence.
- Say what to do. Prefer the positive instruction when it carries the same rule as the negative one.

## Length
- Give the answer first. Add the support after it. Do not write a preamble and do not restate the question.
- Do not summarise work that the diff or the tool output already shows.
- Delete a sentence that only signals effort, such as "I carefully reviewed every file".

## Precedence
- **Chat replies**: `caveman` wins while it is active. Fragments and dropped articles are its purpose. STE governs the persisted artifacts that caveman already exempts.
- **Code**: `ponytail` decides what gets built. STE shapes only the prose around it.
- **Never compress away** a negation, a number, a unit, an exact error string, or a safety warning. Brevity never outranks accuracy.

# Cloudflare

When interacting with Cloudflare, use the cf CLI unless the project has a Wrangler configuration file.

## User Instructions and Reports

- When the user limits the scope, or names a tool, a name or an approach, append their exact
  words to `constraints.md` in the run folder (`$RUN_DIR`), or to the scratchpad when no run
  exists. Read the file again before each phase. Put its full text in every agent or worker
  brief. A constraint holds until the user changes it.
- Run every step of a skill. Skip a planning or review step (grill, plan review, a review
  round, blindspot, Plannotator, code review, QA) only when the user's message names that
  step. Quote that message in the skip reason.
- When you summarize a handoff, a ticket or a document, list each item you drop or defer,
  with the reason.
- Mark each fact about an external system as READ, with its source, or INFERRED. Never state
  an INFERRED fact as a fact.
