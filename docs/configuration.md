# Configuration files

The configuration that chezmoi manages for editors, Git, the shell and terminals.

## Cursor IDE
- **`~/.config/cursor/settings.json`** - Cursor settings with Sonnet 4.5 AI model
- **`~/.config/cursor/keybindings.json`** - Custom keybindings for AI features
- **`~/.cursorrules`** - AI coding guidelines and best practices

### Data Science Extensions (Auto-installed)
- **Jupyter** (`ms-toolsai.jupyter`) - Full Jupyter notebook support in Cursor
- **Jupyter PowerToys** (`ms-toolsai.vscode-jupyter-powertoys`) - Enhanced Jupyter features
- **Data Wrangler** (`ms-toolsai.datawrangler`) - Interactive data viewing and cleaning
- **Python Environment Manager** (`donjayamanne.python-environment-manager`) - Manage Python environments
- **DVC** (`iterative.dvc`) - Data Version Control integration
- **Rainbow CSV** (`mechatroner.rainbow-csv`) - CSV syntax highlighting with column alignment
- **Excel Viewer** (`GrapeCity.gc-excelviewer`) - View Excel and CSV files
- **Data Preview** (`RandomFractalsInc.vscode-data-preview`) - Preview CSV/JSON/Arrow/Parquet files

## Git
- **`~/.gitconfig`** - Enhanced git configuration with 40+ useful aliases
- **`~/.gitignore_global`** - Comprehensive global gitignore
- Git aliases include shortcuts like `git s` (status), `git lg` (pretty log), `git co` (checkout), etc.
- **P4Merge** configured as default merge/diff tool for visual conflict resolution

## Shell (Zsh)
- **`~/.zshrc`** - Main shell configuration with:
  - zoxide integration (smarter cd)
  - direnv hooks (per-directory environments)
  - atuin (enhanced shell history)
  - fzf integration (fuzzy finding)
  - Git aliases and shortcuts
- **`~/.zprofile`** - Environment variables and PATH setup

## Tmux
- **`~/.config/tmux/tmux.conf`** - Full tmux configuration with:
  - Vi mode keybindings
  - Catppuccin theme
  - Plugin management (TPM)
  - Sensible defaults

## Wave Terminal

Config lives in `~/.config/waveterm/` (flat JSON, `:` as level separator). Docs: https://docs.waveterm.dev/config

- **`~/.config/waveterm/settings.json`** - Global settings:
  - Terminal: keeps Wave's stock look on purpose — **Hack 12px** (`--fixed-font`, bundled with the app)
    and the **`default-dark`** theme at `term:transparency` 0.5. Neither `term:fontfamily`,
    `term:fontsize`, `term:theme` nor `term:transparency` is set, so the defaults apply.
  - Terminal behaviour: 10k scrollback, copy-on-select,
    `term:shiftenternewline` (Shift+Enter inserts a newline for Claude Code / AI CLIs),
    `term:macoptionismeta` (matches the Ghostty `macos-option-as-alt` setting)
  - AI: `waveai:defaultmode` points at a local Ollama mode, cloud modes hidden, telemetry off
  - Editor/preview/web/window tweaks (no minimap, word wrap, hidden files, external links)

  To try a different look without editing the file, right-click a terminal header → Themes / Font Size,
  or set it globally:
  ```bash
  wsh setconfig term:theme=catppuccin-mocha
  wsh setconfig term:fontfamily="JetBrainsMono Nerd Font"
  wsh setconfig term:fontsize=14
  wsh setconfig term:transparency=0     # opaque background
  ```
  Revert to the stock look by deleting those keys from `settings.json`.
- **`~/.config/waveterm/waveai.json`** - Wave AI modes (Local Models / BYOK). Configured for **Ollama**,
  no API key needed:
  - `ollama-qwen14b` — `qwen2.5:14b` (default mode)
  - `ollama-qwen-coder` — `qwen2.5-coder:3b`
  - Both hit `http://localhost:11434/v1/chat/completions` with `ai:capabilities: ["tools"]`
- **`~/.config/waveterm/termthemes.json`** - Catppuccin Mocha / Macchiato / Latte, available as **options**
  in the terminal header right-click → Themes menu. Not applied by default.
- **`~/.config/waveterm/backgrounds.json`** - Six **semantic** tab backgrounds, on top of Wave's 13
  decorative built-ins: `bg@work` (blue), `bg@personal` (green), `bg@agent` (mauve), `bg@review`
  (peach), `bg@prod` (red, with diagonal hazard stripes) and `bg@scratch` (grey). The point is
  telling parallel sessions apart at a glance — each also sets `bg:activebordercolor`, so the
  focused block's border carries the same colour. Right-click a tab → Backgrounds to apply, or:
  ```bash
  wsh setbg bg@prod                    # current tab
  wsh setconfig tab:background=bg@work # default for every new tab
  wsh setbg --print "#ff0000"          # generate the JSON for a custom one
  ```
  No global default is set, so new tabs stay unstyled unless you ask.
- **`~/.config/waveterm/widgets.json`** - Custom sidebar widgets, grouped by kind: AI agents
  (claude, codex, opencode, agent-deck) → git/GitHub (`gh dash`, `gh notify`, lazygit) → files
  (yazi) → containers (lazydocker) → system (sysinfo, processes, btop, `dust`).
  Wave's `defwidget@sysinfo` and `defwidget@processviewer` are redefined purely to move them out of
  the built-in block at the top and into the system group. None open magnified — press
  <kbd>Cmd+M</kbd> to magnify a block. Wave's own defaults (terminal, files, web, sysinfo, processes) stay —
  set a `defwidget@*` key to `null` to drop one, or redefine it to change its behaviour.
  `defwidget@sysinfo` is redefined here to plot `CPU + Mem` over a 180s window instead of CPU only over 100s.

  Notes for adding your own:
  - **Every command is wrapped in `/bin/zsh -lc '<cmd>'`** with `cmd:shell: true`. This is not
    cosmetic: a widget block does not inherit the shell's environment, and Wave overwrites `PATH`
    after applying `cmd:env` (it injects its own `wsh` directory). Without the login shell,
    `~/.zprofile` never runs, `PATH` has no `/opt/homebrew/bin`, and anything with a
    `#!/usr/bin/env node` shebang dies with `env: node: No such file or directory` — codex does
    exactly this. The wrapper makes the block behave like a real terminal.
    Use `-lc`, not `-lic`: login sources `~/.zprofile` (which sets `PATH`) without paying for the
    interactive plugin load in `~/.zshrc`.
  - `cmd:cwd` is **static** — a widget cannot ask where to start. `~/.local/bin/wave-widget` fills
    that gap: it finds every repo under `~/Developer`, expands each one with `git worktree list`,
    and shows the lot in `fzf` with a `git log` preview before `cd`-ing and `exec`-ing the real
    command. claude, codex, opencode, lazygit and yazi use it; Esc closes the block.
    Currently 30 repos + 155 worktrees, ~1.5s to build.

    Why `git worktree list` and not a path scan: worktrees here live in at least four layouts
    (`.claude/worktrees/` — where Claude Code puts them, `.worktrees/`, `.zorch/worktrees/`, and
    plain siblings), and a linked worktree's `.git` is a **file**, not a directory, so `fd` alone
    both misses them and double-counts repo roots. Rows are grouped as `● repo` followed by its
    `↳ worktree`s, with the branch name alongside.

    | Env | Effect |
    |-----|--------|
    | `WAVE_WIDGET_ROOT` | search root (default `~/Developer`) |
    | `WAVE_WIDGET_ALL=1` | also list worktrees parked outside the root (throwaway `/tmp` review checkouts are hidden by default) |

    Widgets that are not repo-scoped (gh dash, gh notify, lazydocker, agent-deck, btop)
    keep a plain command and start in `$HOME`; `dust` starts in `~/Developer`.

    Two zsh traps this script had to work around, worth remembering: **never declare `local path`**
    (it is tied to the `$PATH` array — shadowing it blanks `PATH` for every command the function
    calls), and `print -r` does **not** expand `\t`, so building tab-separated rows needs `printf`.
  - `controller: "cmd"` also adds a refresh button to the block header, which is what makes one-shot
    commands like `dust` useful as widgets. Use `controller: "shell"` for a real session.
  - Non-terminal widgets need no controller: `view: "preview"` + `file:` for a file browser,
    `view: "web"` + `url:`/`pinnedurl:`, `view: "sysinfo"` + `sysinfo:type:`
    (`CPU`, `Mem`, `CPU + Mem`, `All CPU`), `view: "processviewer"`.
  - The sysinfo widget only ever plots CPU and memory. Its collector
    (`pkg/wshrpc/wshremote/sysinfo.go`) samples gopsutil's `cpu` and `mem` once a second and nothing
    else — there is no disk, network, swap or temperature series to configure. Use btop for those.
  - Icons are [Font Awesome](https://fontawesome.com/search) names without `fa-`; brand icons need the
    `brands@` prefix (e.g. `brands@docker`).
  - The notifications widget runs `gh notify -w -e ci_activity`: it hides CI notifications, and
    `-w` opens the preview pane. Plain `gh notify` in any terminal shows everything.
  - That widget prepends `~/.local/libexec/gh-nocolor` to `PATH`. The shim sets `NO_COLOR=1` for
    `gh` only, so `gh` sends no terminal queries whose replies would land in the fzf query box.

### The agent group chat — `llmessage`

[llmessage](https://github.com/ybarsotti/llmessage) is a per-project chat that agents and you
share. It lives in its own repo at `~/Developer/llmessage`; this repo carries only the widget.

A `/deep-execute` run already writes `events.jsonl` and `lanes/<lane>/replies/`, but that
conversation is one-way, machine-shaped, and dies with the run — `RUN_DIR` ends when the PR
opens, so CI failures and review rounds land nowhere. llmessage reads those files **from the
outside** and projects them into a session that lives until the PR closes. **No line of
deep-execute changes**, which is deliberate: its scripts carry 820 assertions.

```bash
llmessage daemon              # mirror runs into their sessions, every 5s
llmessage daemon --once       # a single pass
llmessage tui                 # session list + live conversation
llmessage post --body "..."   # post to the current repo's session
llmessage sessions            # every session, newest first
```

- The **`chat` widget** runs one `--once` sync and then the TUI, so it is useful even when no
  daemon is running.
- The chat sits **beside** the run, never on its critical path. The numbered replies stay the
  wake channel `worker-loop.sh` waits on, so a broken chat cannot strand a lane.
- A human message reaches a lane through the **orchestrator**, which reads the chat and routes
  it via `reply.sh` — the same single door that already owns commits and replies.
- Install today is `cargo install --path ~/Developer/llmessage`. There is no pinned
  `.chezmoiexternal.toml` entry yet, because there is no published release to pin a SHA256
  against; that follows the obscura pattern once the repo has one.

**Useful commands:**
```bash
wsh editconfig                 # open settings.json in Wave's editor
wsh editconfig waveai.json     # edit AI modes
wsh setconfig term:fontsize=15 # change a single setting
wsh secret set NAME=value      # store API keys in the OS keychain (not needed for Ollama)
wsh ai main.go -m "find bugs"  # send files/prompts to the AI panel from the CLI
wsh setbg "#1e1e2e"            # set the tab background
wsh badge check --color '#58c142'  # set a tab badge (used by Claude Code hooks)
```

> **Note:** Wave rewrites `settings.json` when you change settings through its GUI, which makes the file
> drift from chezmoi. After tweaking things in the UI, run `chezmoi add ~/.config/waveterm/settings.json`
> to pull the change back into the repo.

**Adding a cloud model (BYOK):** add a mode to `waveai.json` with `ai:provider` (`openai`, `openrouter`,
`groq`, `google`, `nanogpt`, `azure`) and store the key with `wsh secret set OPENAI_KEY=...` — the
provider resolves the endpoint and secret name automatically.

## Pre-commit
- **`.pre-commit-config.yaml`** - Pre-commit hooks for:
  - Shell script linting (shellcheck, shfmt)
  - YAML linting (yamllint)
  - Markdown linting (markdownlint)
  - Python formatting (black, isort, ruff)
  - Secrets detection (gitleaks)
  - Spell checking (codespell)
