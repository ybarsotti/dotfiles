<!-- gitnexus:start -->
# GitNexus MCP

This project is indexed by GitNexus as **chezmoi** (421 symbols, 530 relationships, 12 execution flows).

## Always Start Here

1. **Read `gitnexus://repo/{name}/context`** — codebase overview + check index freshness
2. **Match your task to a skill below** and **read that skill file**
3. **Follow the skill's workflow and checklist**

> If step 1 warns the index is stale, run `npx gitnexus analyze` in the terminal first.

## Skills

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->

## graphify

This project has a graphify knowledge graph at graphify-out/.

Rules:
- Before answering architecture or codebase questions, read graphify-out/GRAPH_REPORT.md for god nodes and community structure
- If graphify-out/wiki/index.md exists, navigate it instead of reading raw files
- For cross-module "how does X relate to Y" questions, prefer `graphify query "<question>"`, `graphify path "<A>" "<B>"`, or `graphify explain "<concept>"` over grep — these traverse the graph's EXTRACTED + INFERRED edges instead of scanning files
- After modifying code files in this session, run `graphify update .` to keep the graph current (AST-only, no API cost)

## Browser and Web Navigation

Three browser tools serve three targets. Pick by where the page lives.

- **`kitesurf` MCP — the public web.** Cloudflare's remote headless browser for agents. It runs on
  Cloudflare Workers, so this machine installs no browser and the request leaves from Cloudflare.
  Use it to open a public URL, read a page, fill a form, click an element, take a screenshot, or
  scrape. It reads `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` from the environment. If it
  fails to authenticate, report the missing variable and stop.
  Docs: https://developers.cloudflare.com/browser-run/kitesurf/
- **`obscura` MCP — this machine's network.** A local headless browser written in Rust, with no
  Chrome. Use it for a `localhost` dev server, a private address, or any page kitesurf cannot reach
  from Cloudflare. `obscura serve --port 9222` also exposes a CDP endpoint that Playwright and
  Puppeteer connect to. Docs: https://github.com/h4ckf0r0day/obscura
- **A real browser** — for the user's logged-in profile, an Electron application, or QA evidence
  such as screenshots and video.

Prefer `kitesurf` for a public page. It costs this machine nothing and starts fastest.
