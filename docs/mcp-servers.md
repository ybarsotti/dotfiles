# MCP servers

The MCP servers, and which browser tool to use for which target.

> **Where Claude Code actually reads MCP servers from.** `dot_claude/settings.json.tmpl` renders
> an `mcpServers` block, and `~/.claude/mcp_servers.json` holds the same merged set, but neither
> is what the CLI uses. Adding `kitesurf` and `obscura` to `~/.claude/settings.json` left both
> absent from `claude mcp list`; registering `obscura` with `claude mcp add --scope user` put it
> in `~/.claude.json` and it connected immediately. So `~/.claude.json` is the live registry.
>
> That file is in `.chezmoiignore.tmpl` on purpose — it is rewritten on every launch — which
> means `chezmoi apply` can never overwrite a server registered there. The tradeoff is that a
> server registered this way does not travel to a new machine. `.chezmoidata/mcp-server.yml`
> stays the written record of what each machine should have; register them on a fresh machine
> with `claude mcp add --scope user <name> -- <command> [args...]`.

The following MCP servers are configured for Claude Code:

- **context7** - Up-to-date library documentation
- **sequential-thinking** - Enhanced reasoning capabilities
- **playwright** - Browser automation for testing
- **filesystem** - Enhanced file operations in ~/Developer
- **memory** - Persistent context across sessions
- **gitnexus** - Codebase knowledge graph for AI agents
- **kitesurf** - Cloudflare Browser Run's remote headless browser for agents
- **obscura** - Local headless browser for agents (Rust, no Chrome), reaches `localhost`

## Browser navigation — which tool for which target

| Target | Tool | Why |
|--------|------|-----|
| Public web page | `kitesurf` MCP | Runs on Cloudflare. Nothing installs here, nothing runs here |
| `localhost` dev server, private IP | `obscura` MCP | Runs on this machine, so it reaches this network |
| Logged-in profile, Electron app, QA evidence | `agent-browser` skill | A real browser, and it records screenshots and video |

## Kitesurf (remote)

[Kitesurf](https://developers.cloudflare.com/browser-run/kitesurf/) is Cloudflare's stateless
headless browser. It runs on Cloudflare Workers, so **nothing installs on this machine** — there is
no Kitesurf CLI and no local Chrome to manage. The only local part is `chrome-devtools-mcp`, which
`npx` fetches on demand and which speaks CDP over a WebSocket to Cloudflare.

The server is defined in `.chezmoidata/mcp-server.yml` under `mcp_servers.shared`, so it loads on
personal and work machines. It reads two variables from the environment at launch, which keeps the
token out of this repo:

```bash
# ~/.zsh_env_vars (never committed — see .chezmoiignore.tmpl)
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
export CLOUDFLARE_API_TOKEN="your-api-token"   # needs the "Browser Rendering: Edit" permission
```

Verify the credentials without an agent:

```bash
curl -X POST "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/browser-run/screenshot?browser=kitesurf" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"url": "https://example.com"}' \
  --output screenshot.png
```

Kitesurf is **free while in beta**, behind per-account limits, and Cloudflare says it plans to open
source it. It reaches no local port, which is what Obscura below is for.

## Obscura (local)

[Obscura](https://github.com/h4ckf0r0day/obscura) is an Apache-2.0 headless browser engine in Rust
— real V8, no Chrome, no Node. Cloudflare names it as Kitesurf's original inspiration. Because it
runs here, it reaches what Kitesurf cannot: a dev server on `localhost`, a private address, a
service on the LAN.

Homebrew has no formula, so `.chezmoiexternal.toml` pins the v0.2.0 release archive **and its
SHA256** for the machine's architecture, unpacks it into `~/.local/share/obscura`, and
`dot_local/bin/symlink_obscura.tmpl` links the binary into `~/.local/bin`. Bump the version and
the checksum together — a retag upstream then cannot change what lands here. The archive carries
two binaries: `obscura` and the `obscura-worker` that `serve` and `scrape` spawn beside it. Only
`obscura` is linked, because it resolves its own real path and finds the worker there.

```bash
obscura fetch https://example.com --eval "document.title"   # fetch and evaluate
obscura fetch https://example.com -s page.png               # render and screenshot
obscura scrape url1 url2 url3 --concurrency 25 --format json
obscura serve --port 9222                                   # CDP endpoint for Playwright/Puppeteer
obscura mcp                                                 # MCP server over stdio
```

> **Security — read before using it against a real site.** The MCP entry passes
> `--allow-private-network`, which turns **off** Obscura's default block on loopback, RFC1918 and
> link-local addresses. That block is an SSRF guard. The flag is set on purpose, because reaching
> `localhost` is the whole reason this server exists, but the cost is real: a page Obscura loads
> can redirect it to an address on this network. Drop the flag in `.chezmoidata/mcp-server.yml` to
> restore the guard, and Obscura then reaches the public internet only.
>
> The release binaries are unsigned third-party builds. They are pinned by SHA256 here, so an
> upstream retag cannot swap them, but the pin only proves the bytes have not changed since they
> were checked — it is not a review of what they do.

The checksums above pin the plain render build. Its `--stealth` flag therefore only gives a
consistent browser fingerprint; the TLS impersonation and tracker blocking need the separate
`-stealth` release archive, which this does not install.

The routing rule between the three tools lives in `dot_claude/CLAUDE.md.tmpl`,
`dot_codex/AGENTS.md` and `AGENTS.md`.
