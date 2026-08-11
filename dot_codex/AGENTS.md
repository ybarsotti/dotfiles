# Global AGENTS.md

@RTK.md

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
