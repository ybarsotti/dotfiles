# ~/. 📂 My dotfiles
managed with [`chezmoi`](https://github.com/twpayne/chezmoi).

## Installation

### Interactive Setup

During installation, you'll be prompted to configure machine-specific settings:
- **Machine purpose**: Choose "personal" or "work"
- **Work credentials**: If you choose "work", you'll be prompted for work email and git username

### Install dotfiles

```console
$ sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply ybarsotti
```

During the first run, you'll be prompted to configure machine-specific settings for the appropriate email/git configuration.


## Common Chezmoi Commands

A quick reference for the most frequently used `chezmoi` commands for day-to-day operations.

### Core Workflow

This is the most common cycle for making changes to your dotfiles.

- **`chezmoi edit [target-file]`**
  - **Purpose**: The safest way to edit a managed dotfile. It opens the *source file* in your editor, not the destination file in your home directory.
  - **Example**: `chezmoi edit ~/.zshrc`

- **`chezmoi diff`**
  - **Purpose**: Shows a diff of the changes that would be made by `chezmoi apply`. It's highly recommended to run this before applying to see what will change.
  - **Example**: `chezmoi diff`

- **`chezmoi apply`**
  - **Purpose**: Applies the changes from your source directory to your home directory, making it match the desired state. This is the main command to sync your dotfiles. Use the `-v` (verbose) flag to see what it's doing.
  - **Example**: `chezmoi apply -v`

### Managing Files

Commands for adding, removing, or changing which files are managed by `chezmoi`.

- **`chezmoi add [target-file]`**
  - **Purpose**: Adds a new file from your home directory to `chezmoi`'s source state.
  - **Example**: `chezmoi add ~/.config/alacritty/alacritty.yml`

- **`chezmoi forget [target-file]`**
  - **Purpose**: Removes a file from `chezmoi`'s management. The file is removed from the source directory but is **left untouched** in your home directory.
  - **Example**: `chezmoi forget ~/.bashrc`

- **`chezmoi remove [target-file]`**
  - **Purpose**: The more destructive version of `forget`. It removes the file from the source directory **and also deletes it** from your home directory.
  - **Example**: `chezmoi remove ~/.old_config_file`

### Syncing & Status

Commands for keeping multiple machines in sync and checking the current state.

- **`chezmoi update`**
  - **Purpose**: Pulls the latest changes from your dotfiles git repository and then runs `chezmoi apply`. This is the primary command for syncing changes *to* a machine.
  - **Example**: `chezmoi update`

- **`chezmoi status`**
  - **Purpose**: Shows a summary of files that have been modified in your home directory and differ from what's in the source directory.
  - **Example**: `chezmoi status`

- **`chezmoi cd`**
  - **Purpose**: A handy shortcut to open a new shell session directly in the source directory (`~/.local/share/chezmoi`).
  - **Example**: `chezmoi cd`

### Destructive Operations

> **Warning**: Use the following commands with caution as they can delete files.

- **`chezmoi purge`**
  - **Purpose**: Removes everything managed by `chezmoi` from your home directory. This effectively uninstalls your managed dotfiles, leaving your system clean.
  - **Example**: `chezmoi purge`

## Development Tools

This dotfiles setup includes several development tools that are automatically installed through the packages.yaml configuration:

### Code Quality & Linting
- **`shellcheck`** - Shell script static analysis tool for finding bugs and improving code quality
  - Usage: `shellcheck script.sh`
- **`yamllint`** - YAML linter for configuration files
  - Usage: `yamllint config.yaml`
- **`hadolint`** - Dockerfile linter
  - Usage: `hadolint Dockerfile`
- **`actionlint`** - GitHub Actions workflow linter
  - Usage: `actionlint .github/workflows/*.yml`
- **`markdownlint-cli`** - Markdown linter
  - Usage: `markdownlint '**/*.md'`
- **`vale`** - Prose linter for documentation
  - Usage: `vale README.md`
- **`typos-cli`** - Fast source code spell checker
  - Usage: `typos`, `typos --write-changes`
- **`codespell`** - Find and fix common misspellings
  - Usage: `codespell`, `codespell -w` (fix)
- **`ruff`** - Extremely fast Python linter (replaces flake8, pylint)
  - Usage: `ruff check .`, `ruff format .`
- **`pre-commit`** - Git hooks framework for running checks before commits
  - Setup: `pre-commit install` or `just install-hooks`
  - Usage: `pre-commit run --all-files`
- **`prettier`** - Code formatter for consistent styling
  - Usage: `prettier --write file.js`
- **`shfmt`** - Shell script formatter
  - Usage: `shfmt -w script.sh`
- **`black`** - Python code formatter with opinionated style
  - Usage: `black script.py`, `black --check .`
- **`isort`** - Python import sorter and organizer
  - Usage: `isort script.py`, `isort --check-only .`
- **`autopep8`** - Python PEP8 code formatter
  - Usage: `autopep8 --in-place script.py`
- **`clang-format`** - C/C++ code formatter
  - Usage: `clang-format -i file.cpp`, `clang-format --style=Google file.c`

### Version Managers & Runtimes
- **`mise`** - Universal runtime version manager (replaces nvm, rbenv, etc.)
  - Usage: `mise use node@lts`, `mise use python@3.12`, `mise list`
- **`pipx`** - Install Python packages in isolated environments
  - Usage: `pipx install package`, `pipx list`
- **`uv`** - Fast Python package installer and resolver
  - Usage: `uv pip install package`, `uv tool install package`
- **`luarocks`** - Lua package manager
  - Usage: `luarocks install package`

### Development Utilities
- **`opencode`** - OpenCode CLI tool for development workflows
  - Usage: `opencode .` to open current directory
- **`commitizen`** - Tool for creating standardized commit messages
  - Usage: `git cz` or `cz commit`
- **`gh`** - GitHub CLI for repository management
  - Usage: `gh repo clone`, `gh pr create`, `gh issue list`
- **`lazygit`** - Terminal UI for git commands
  - Usage: `lazygit`
- **`lazydocker`** - Terminal UI for Docker
  - Usage: `lazydocker`
- **`git-flow`** - Git branching model extensions
  - Usage: `git flow init`, `git flow feature start`
- **`git-delta`** - Enhanced git diff viewer with syntax highlighting
  - Usage: Automatically used by git (configured in .gitconfig)
- **`gitleaks`** - Detect and prevent secrets in git repos
  - Usage: `gitleaks detect`, `gitleaks protect`
- **`git-sizer`** - Compute size metrics for git repos
  - Usage: `git-sizer --verbose`
- **`direnv`** - Load/unload environment variables per directory
  - Usage: Create `.envrc` files, automatically loads on `cd`
- **`just`** - Modern command runner (better than Make)
  - Usage: `just`, `just --list`, `just check`
- **`watchexec`** - Execute commands when files change
  - Usage: `watchexec -e js npm test`
- **`entr`** - Run commands when files change
  - Usage: `ls *.py | entr pytest`
- **`act`** - Run GitHub Actions locally for testing CI workflows
  - Usage: `act`, `act -l` (list workflows), `act push` (simulate push event)
- **`terraform`** - Infrastructure as Code tool
  - Usage: `terraform init`, `terraform plan`, `terraform apply`

### System Tools & Terminal Enhancements
- **`ripgrep`** - Fast text search tool
  - Usage: `rg "pattern" file.txt`, `rg -i "case insensitive"`
- **`fd`** - Modern find replacement with better performance
  - Usage: `fd filename`, `fd -e js` (find JS files)
- **`bat`** - Enhanced cat with syntax highlighting and Git integration
  - Usage: `bat file.txt`, `bat --style=numbers file.py`
- **`eza`** - Modern ls replacement with better formatting and colors
  - Usage: `eza -la`, `eza --tree`, `eza --git`
- **`fzf`** - Fuzzy finder for command-line
  - Usage: `**<TAB>` (fuzzy complete), `Ctrl+R` (history search)
- **`tree`** - Directory tree viewer
  - Usage: `tree`, `tree -L 2` (limit depth)
- **`zoxide`** - Smarter cd command that learns your habits
  - Usage: `z dirname` (jumps to most frecent match), `zi` (interactive)
- **`atuin`** - Shell history with sync and powerful search
  - Usage: `Ctrl+R` (enhanced history search), `atuin search`
- **`btop`** - Resource monitor with better interface than htop
  - Usage: `btop`
- **`bottom`** - System monitor (alternative to btop)
  - Usage: `btm`
- **`fastfetch`** - System information display
  - Usage: `fastfetch`
- **`jq`** - JSON processor
  - Usage: `echo '{"key":"value"}' | jq .key`
- **`tldr`** - Simplified man pages with practical examples
  - Usage: `tldr tar`, `tldr git-commit`
- **`duf`** - Better disk usage/free utility
  - Usage: `duf`
- **`httpie`** - User-friendly HTTP client
  - Usage: `http GET httpbin.org/json`
- **`oha`** - HTTP load testing tool
  - Usage: `oha -n 100 -c 10 https://example.com`
- **`grpcurl`** - curl for gRPC services
  - Usage: `grpcurl localhost:9090 list`
- **`gnu-sed`** - GNU version of sed (macOS ships BSD sed)
  - Usage: `gsed 's/old/new/g' file`
- **`weathr`** - CLI weather forecast tool
  - Usage: `weathr`
- **`gping`** - Ping with a graph
  - Usage: `gping google.com`
- **`bandwhich`** - Network utilization by process
  - Usage: `sudo bandwhich`
- **`nmap`** - Network discovery and security auditing
  - Usage: `nmap -sP 192.168.1.0/24`
- **`pngpaste`** - PNG image clipboard utility for macOS
  - Usage: `pngpaste output.png` (paste clipboard image to file)
  - Required for Neovim img-clip.nvim plugin
- **`yazi`** - Terminal file manager
  - Usage: `yazi` or `y` (with cd integration)
- **`tmux`** - Terminal multiplexer
  - Usage: `tmux new-session`, `tmux attach`
- **`zellij`** - Terminal workspace with built-in multiplexer
  - Usage: `zellij`
- **`thefuck`** - Command correction tool
  - Usage: Type command, get error, type `fuck` to get corrected version

### Performance & Analysis Tools
- **`hyperfine`** - Command-line benchmarking tool (better than `time`)
  - Usage: `hyperfine 'command1' 'command2'`, `hyperfine --warmup 3 'npm test'`
- **`procs`** - Modern process viewer (better than `ps`)
  - Usage: `procs`, `procs firefox`, `procs --tree`
- **`dust`** - Disk usage analyzer (better than `du`)
  - Usage: `dust`, `dust -d 3` (limit depth), `dust -r` (reverse sort)
- **`tokei`** - Code statistics and line counter
  - Usage: `tokei`, `tokei --languages` (list supported languages), `tokei src/`

### API Development & Testing
- **`evans`** - Expressive gRPC client for testing gRPC services
  - Usage: `evans -r repl -p 9090`, `evans --proto api.proto`
- **`grpcurl`** - curl for gRPC services
  - Usage: `grpcurl localhost:9090 list`, `grpcurl -d '{"name":"test"}' localhost:9090 Service/Method`

### SSH Management (Personal only)
- **`sshs`** - TUI for SSH connections that reads from `~/.ssh/config`
  - Usage: `sshs` — navigate hosts with arrow keys, connect with Enter
  - Docs: https://github.com/quantumsheep/sshs
- **`mosh`** - Resilient SSH sessions that auto-reconnect on unstable connections
  - Usage: `mosh user@host` (drop-in replacement for `ssh`)
  - Works great on mobile/unstable networks, low-latency typing
  - Docs: https://mosh.org

### AI & Agent Tools
- **`ollama`** - Run large language models locally (personal machines only)
  - Usage: `ollama run llama3.2`, `ollama list`, `ollama pull mistral`
  - Start server: `ollama serve`
- **`claude-code`** - Anthropic's Claude Code CLI agent
  - Usage: `claude`, installed via `npm install -g @anthropic-ai/claude-code`
- **`codex`** - OpenAI Codex CLI agent
  - Usage: `codex`, installed via `npm install -g @openai/codex`
- **`openspec`** - Spec-driven planning layer for coding agents
  - Usage: `openspec init`, `openspec propose`, `openspec status`
- **`specify`** (GitHub Spec Kit) - Toolkit for Spec-Driven Development with AI coding agents
  - Usage: `specify init <project>`, `specify plan`, `specify build`
  - Install: Via `uv tool install` (automatic)
- **`gemini-cli`** - Google Gemini CLI agent
  - Usage: `gemini`, installed via `brew install gemini-cli`
- **`gastown`** - Multi-agent orchestration (coordinates Claude, Codex, Gemini workers)
  - Usage: `gt install ~/gt --git`, `gt mayor attach`
  - Install: Via `brew install gastown`
- **`agent-deck`** - Terminal session manager TUI for AI coding agents
  - Usage: `agent-deck`
  - Install: Via `brew install asheshgoplani/tap/agent-deck`
- **`gitnexus`** - Codebase knowledge graph engine for AI agents
  - Usage: `npx gitnexus analyze`, `npx gitnexus setup`
  - MCP server: `claude mcp add gitnexus -- npx -y gitnexus@latest mcp`
- **`graphifyy`** (CLI: `graphify`) - Multi-modal knowledge graph for AI coding assistants
  - Usage: `graphify .` (build graph), `/graphify query "..."`, `graphify hook install`
  - Install (auto via chezmoi): `pipx install graphifyy && graphify install && graphify claude install`
  - Outputs `graphify-out/GRAPH_REPORT.md` — Claude Code skill auto-reads it
- **`bmad-method`** - AI-driven agile development framework with 34+ workflows
  - Usage: `npx bmad-method install` (per-project)

### Data Engineering & Analytics

#### Databases & CLI Tools
- **`duckdb`** - Fast in-process analytical database (embedded, no server required)
  - Usage: `duckdb mydata.db`, `duckdb -c "SELECT * FROM read_csv('data.csv')"`
  - Perfect for local analytics and ETL without spinning up a database server
- **ClickHouse** - OLAP database (use Docker, see Docker Compose examples)
  - Connect: `docker exec -it dev-clickhouse clickhouse-client`

#### Data Format Tools
- **`xsv`** - Fast CSV command-line toolkit written in Rust
  - Usage: `xsv stats data.csv`, `xsv select column1,column3 data.csv`, `xsv search pattern data.csv`
- **`miller`** - Like awk/sed/cut for structured data (CSV, JSON, TSV, etc.)
  - Usage: `mlr --csv cut -f name,age data.csv`, `mlr --json stats1 -a sum -f price data.json`
- **`visidata`** - Interactive multitool for tabular data with TUI
  - Usage: `vd data.csv`, `vd data.json`, `vd database.db`

#### Docker Infrastructure
For databases and heavy services (PostgreSQL, Kafka, Spark, etc.), use Docker Compose:
- See `~/.config/docker-compose-examples/` for ready-to-use configurations
- Available services: PostgreSQL, Kafka, Spark, ClickHouse, MLflow
- Quick start: `docker-compose -f ~/.config/docker-compose-examples/postgres.yml up -d`

### Development Editors & Language Support
- **`neovim`** - Modern Vim-based text editor
  - Usage: `nvim file.txt`
- **`cursor`** - AI-powered code editor CLI
  - Usage: `cursor .` to open current directory
  - Note: Installed via official Cursor install script
- **`tree-sitter`** - Incremental parsing system for syntax highlighting
  - Used automatically by Neovim and other editors

### Shell Enhancements
- **`zsh-autosuggestions`** - Fish-like autosuggestions for Zsh
- **`zsh-syntax-highlighting`** - Fish-like syntax highlighting for Zsh
- **`jandedobbeleer/oh-my-posh/oh-my-posh`** - Cross-platform prompt theme engine
- **`zoxide`** - Smarter cd that learns your habits (see System Tools section)
- **`atuin`** - Shell history with sync and search (see System Tools section)
- **`direnv`** - Per-directory environment variables (see Development Utilities section)

### Security & Privacy
- **`gnupg`** - GNU Privacy Guard for encryption
  - Usage: `gpg --gen-key`, `gpg --encrypt file.txt`
- **`pinentry-mac`** - macOS keychain integration for GPG
- **`age`** - Simple file encryption (modern GPG alternative)
  - Usage: `age-keygen -o key.txt`, `age -r recipient file.txt`
- **`sops`** - Encrypted secrets in Git repos
  - Usage: `sops -e secrets.yaml > secrets.enc.yaml`
- **`trivy`** - Container and IaC security scanner
  - Usage: `trivy image nginx:latest`, `trivy config .`
- **`doppler`** - Secrets management
  - Usage: `doppler login`, `doppler secrets`
- **`aws-vault`** - Securely store and access AWS credentials
  - Usage: `aws-vault exec profile -- aws s3 ls`

### Package Visualization
- **`youplot`** - Command-line data plotting
  - Usage: `seq 1 10 | youplot line`

### Build Tools
- **`cmake`** - Cross-platform build system generator
  - Usage: `cmake .`, `make`
- **`make`** - Build automation tool
  - Usage: `make`, `make install`

### Containerization
- **`docker`** (Docker Desktop cask) - Container platform with Docker Engine, CLI, and Compose
  - Usage: `docker run`, `docker build`, `docker compose up`

### GUI Applications (Casks)

**Browsers:** Arc, Brave, Firefox

**Development:** Apidog (API testing), Beekeeper Studio (SQL editor), cmux (Claude Code terminal session manager), Conductor (Claude Code + GitHub), Docker Desktop, Figma, Ghostty (terminal emulator), Wave Terminal (block/widget terminal with local-LLM AI panel), Visual Studio Code, P4Merge (visual merge tool)

**Productivity:** Alt-Tab (window switcher), Raycast (launcher), BetterDisplay, Stats (menu bar monitor), Slack, Notion

**Media:** OBS, Spotify

### Fonts

**Nerd Fonts** (with icon support): Hack, JetBrains Mono, Fira Code, Meslo LG, Sauce Code Pro, Caskaydia Cove, Iosevka, Victor Mono

**Standard Developer Fonts:** SF Pro, Fira Code, Cascadia Code, Monaspace (GitHub's superfamily)

### GitHub CLI Extensions

15 extensions auto-installed via `gh extension install`:
- **`gh-branch`** - Branch management
- **`gh-bump`** - Version bumping
- **`gh-clean-branches`** - Delete merged branches
- **`gh-clone-org`** - Clone all repos in an org
- **`gh-dash`** - Dashboard TUI for PRs and issues
- **`gh-download`** - Download release assets
- **`gh-eco`** - Explore repos in an ecosystem
- **`gh-install`** - Install tools from GitHub releases
- **`gh-milestone`** - Milestone management
- **`gh-notify`** - GitHub notifications in terminal
- **`gh-poi`** - Delete merged local branches
- **`gh-repo-stats`** - Repository statistics
- **`gh-skyline`** - 3D contribution graph
- **`gh-task`** - Task management
- **`gh-log`** - View commit logs

## Justfile Commands

This repository includes a `Justfile` with convenient commands for common tasks. Run `just` or `just --list` to see all available commands.

### Common Commands

- **`just check`** - Run all validations (shellcheck, yamllint, gitleaks)
- **`just diff`** - Show what changes chezmoi would make
- **`just apply`** - Apply dotfiles to home directory
- **`just update`** - Update from git and apply
- **`just status`** - Check status of managed files
- **`just update-gh-extensions`** - Upgrade all `gh` CLI extensions (the installer is `run_once_`, so
  extensions otherwise stay pinned at their setup-time version — `gh dash` sat on v4.22.0, which
  panics on startup under Wave). Also runs as part of `just full-update`.
- **`just install-hooks`** - Install pre-commit hooks
- **`just pre-commit`** - Run pre-commit hooks on all files
- **`just test-deep-pipeline`** - Run the deep-plan / deep-execute / deep-review / cmux-orchestrator shell test suites (see "Deep-* Agent Pipeline" under Claude Code, below)
- **`just format`** - Format all shell scripts and YAML files
- **`just clean`** - Clean up temporary files and caches
- **`just info`** - Show system information
- **`just stats`** - Show repository statistics

Run `just` to see the full list of available commands.

## Homebrew Tap Trust

Homebrew 6 refuses to load formulae or casks from a third-party tap until that tap is trusted, so
`run_onchange_01_homebrew_taps.sh.tmpl` runs `brew trust --tap` on each one after tapping. Without
it a fresh install taps everything and then fails on `agent-deck`, `peon-ping`, `oh-my-posh`,
`borders` and `cmux`. Trust means Homebrew will load and run that tap's Ruby formula code; it is
recorded in `~/.config/homebrew/trust.json` and reversed with `brew untrust <tap>`. The script
guards on `brew trust --help`, so it stays a no-op on Homebrew 5 and earlier.

`sst/tap` used to be in that list and was removed: SST renamed itself to Anomaly, so the name now
only resolves through a GitHub 301 to `anomalyco/homebrew-tap`. Because the tap name no longer
matched its remote, `brew trust` recorded the raw clone URL rather than a tap name — and
`brew untrust` could not undo it, since the URL resolves back to the *name* `anomalyco/tap`, which
was never in the list. The stale entry had to be edited out of `trust.json` by hand. Nothing here
installs from that tap anyway; `opencode` ships in `homebrew/core` now.

## Configuration Files

### Cursor IDE
- **`~/.config/cursor/settings.json`** - Cursor settings with Sonnet 4.5 AI model
- **`~/.config/cursor/keybindings.json`** - Custom keybindings for AI features
- **`~/.cursorrules`** - AI coding guidelines and best practices

#### Data Science Extensions (Auto-installed)
- **Jupyter** (`ms-toolsai.jupyter`) - Full Jupyter notebook support in Cursor
- **Jupyter PowerToys** (`ms-toolsai.vscode-jupyter-powertoys`) - Enhanced Jupyter features
- **Data Wrangler** (`ms-toolsai.datawrangler`) - Interactive data viewing and cleaning
- **Python Environment Manager** (`donjayamanne.python-environment-manager`) - Manage Python environments
- **DVC** (`iterative.dvc`) - Data Version Control integration
- **Rainbow CSV** (`mechatroner.rainbow-csv`) - CSV syntax highlighting with column alignment
- **Excel Viewer** (`GrapeCity.gc-excelviewer`) - View Excel and CSV files
- **Data Preview** (`RandomFractalsInc.vscode-data-preview`) - Preview CSV/JSON/Arrow/Parquet files

### Git
- **`~/.gitconfig`** - Enhanced git configuration with 40+ useful aliases
- **`~/.gitignore_global`** - Comprehensive global gitignore
- Git aliases include shortcuts like `git s` (status), `git lg` (pretty log), `git co` (checkout), etc.
- **P4Merge** configured as default merge/diff tool for visual conflict resolution

### Shell (Zsh)
- **`~/.zshrc`** - Main shell configuration with:
  - zoxide integration (smarter cd)
  - direnv hooks (per-directory environments)
  - atuin (enhanced shell history)
  - fzf integration (fuzzy finding)
  - Git aliases and shortcuts
- **`~/.zprofile`** - Environment variables and PATH setup

### Tmux
- **`~/.config/tmux/tmux.conf`** - Full tmux configuration with:
  - Vi mode keybindings
  - Catppuccin theme
  - Plugin management (TPM)
  - Sensible defaults

### Wave Terminal

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
  (Redacted browser, yazi) → containers (lazydocker) → system (sysinfo, processes, btop, `dust`).
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
  - The notifications widget runs `gh notify -w -e ci_activity`. Without the exclusion it is unusable
    here: 34 of 36 unread notifications were `ci_activity` (workflow-run-failed), burying the two
    that were an actual PR comment and state change. `-w` opens the preview pane; plain
    `gh notify` in any terminal still shows everything including CI.
  - That widget also prepends `~/.local/libexec/gh-nocolor` to `PATH`. **`gh` writes
    `\033]11;?` (OSC 11, background colour) and `\033[6n` (cursor position) on every single
    invocation** — verified with `script -q /dev/null gh api user`. Wave answers both, and when gh
    runs underneath a live TUI (gh-notify shells out to `gh api` while fzf is on screen) the
    replies land in that TUI's stdin: `11;rgb:0000/0000/0000` typed into the fzf query box, and
    previously a crash in gh-dash, which dereferenced a not-yet-loaded config on the resulting
    phantom keypress. `NO_COLOR=1` makes gh skip the queries; the shim scopes it to gh alone,
    because fzf honours `NO_COLOR` too and would go monochrome. gh-notify's own colours are
    emitted by the script, so they are unaffected.

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

### Claude Code
- **`~/.claude/settings.json`** - Claude Code settings with hooks and MCP servers
- **`~/.claude/commands/*.md`** - Custom slash commands:
  - `/test` - Run project tests
  - `/docs` - Generate documentation
  - `/refactor` - Suggest refactorings
  - `/deps` - Analyze dependencies
  - `/deep-plan` - Multi-agent planning pipeline (see below)
  - `/deep-execute` - Runs an approved deep-plan parallel plan as lane workers (see below)
  - `/deep-review` - Multi-persona peer review of a diff
  - `/pr-description` - Conventional-commit PR title/body with requirements matrix, Mermaid,
    decisions and **UI evidence** (flow GIF/recording + before/after screenshots), then opens
    the PR assigned to you

#### Deep-* Agent Pipeline

Three slash commands chain together for planning and parallel execution of non-trivial work:

- **`/deep-plan`** - Multi-agent planning pipeline (Opus + Codex draft, a 5-persona review
  loop, a Plannotator approval gate). Plan captures ticket/Slack sources, requirements
  coverage, applicable user journey, data-column population, and substantial-UI design
  handoff. Stops at an **approved plan** — it never builds or reviews code itself. Its last
  phase is an **execution recommendation** (below).
- **`/deep-execute <plan.md>`** - Runs an approved parallel plan as lane workers sharing ONE
  git worktree, in parallel cmux panes (via `cmux-orchestrator`). Coordinates fan-out, an
  event/reply protocol (`event.sh` / `board.sh` / `monitor-events.sh` / `reply.sh`),
  contract-drift handling, per-round gating (`round-gate.sh`: lane tests → contract →
  run-state → one light review, in that order), a 3-round cap with escalation, then the
  unattended tail: `/deep-review default --reviewers 6 --ratio 3:3` + fixes → record what was
  built and what review changed → a **QA agent** running `/qa-testing` through `agent-browser`
  → a **different** agent fixing the gaps it found → frozen SHA → `/pr-description` with
  evidence → the **run report** (below). The orchestrator is the sole `git` committer between
  rounds; lane workers never run `git` themselves.
- **`/deep-review`** - Multi-persona peer review of a diff (Claude + Codex headless
  reviewers), invoked once per `/deep-execute` run and usable standalone.

##### Execution recommendation (how the plan gets built)

The approved plan says *what* to build; how it gets built is a separate call, and it is yours.
deep-plan's last phase reads the plan's `## Execution shape`, recommends one of four modes and
asks you to confirm via `AskUserQuestion`, writing the choice to
`$RUN_DIR/execution-recommendation.md`:

| | Option | Fits when |
|---|---|---|
| **A** | `/deep-execute` — parallel lane workers, one shared worktree | `Mode: parallel`, ≥ 2 disjoint lanes, a real contract |
| **B** | Sequential in the planning session (`superpowers:executing-plans`) | serial plan, one lane, or lanes too coupled for a contract |
| **C** | Claude `Workflow` — deterministic script fan-out | many uniform mechanical slices (migration, codemod, sweep) |
| **D** | Codex-only implementer, Claude orchestrates and reviews | one coherent slice for a second model to write |

**The planning session orchestrates; it does not implement.** It directs workers, answers their
questions, gates rounds, routes review and QA findings back to the owning agent, and commits.
**Option B is the only opt-out**, and only when *you* pick it — never because the session judged
the change small enough to just do itself.

Whichever mode runs, the tail is the same and runs **end to end without checking in** — it
halts only on a blocker no agent can settle alone. The run is wrapped in **`/goal`** (built
into Claude Code and Codex) with the objective stated as the finished state — reviewed,
QA-green, PR open — which is what keeps it driving there instead of stopping at the first
natural pause; `/deep-execute` opens its own in Phase 0, and under B, C and D the planning
session opens it. The self-contained HTML run report is a `/deep-execute` artifact — under
B, C and D you get the QA evidence report and the PR body instead.

QA adapts to the machine: `qa-testing` in EXECUTE mode when that skill is installed, the plan's
`qa-plan.yaml` through `/qa-test-plan` when it names one, and a plain `agent-browser` agent
otherwise. A missing skill downgrades the evidence; it never cancels the QA step.

##### Run report (what was built, and why)

The approved plan records the decisions taken *before* code was written. Decisions taken
*during* the run — which of two viable implementations a lane picked, what it assumed about a
lane it doesn't own, where it worked around something the plan missed — otherwise die with the
worker's session. `decision.sh` is the channel that outlives the pane:

```bash
decision.sh RUN_DIR LANE TASK --title "Materialized view for the totals" \
  --rationale "The plan left the aggregation strategy open; a view keeps reads to one query." \
  --alternative "Compute in the API layer — N+1 across three tables" \
  --tradeoff "Up to 60s of refresh lag on the totals"
```

It writes `lanes/<lane>/decisions/NNN.json` and emits a `decision` event carrying only the
headline — an `events.jsonl` line must stay single-line and under `PIPE_BUF` for concurrent
appends to be atomic, and rationale is prose. `decision` events are deliberately not monitor
triggers; they are for the report, not an interruption mid-round.

After the final review, the frozen SHA, QA and the opened PR, `build-run-report.sh RUN_DIR
[--final-sha SHA] [--review report.md] [--qa index.html] [--pr URL]` renders
`RUN_DIR/report/index.html`: what was built (git diffstat, baseline → frozen SHA), the lane
table with `owns`/`depends_on`, every recorded decision with its rejected alternatives and
accepted tradeoffs, the plan's own pre-implementation rationale, drift (contract version moved,
extra rounds, blocked lanes), the final board plus full event timeline, the review/QA evidence
(screenshots and recordings live in the linked QA report), and the pull request. Self-contained
HTML, light and dark, no external assets.

Every claim on that page comes from a file in the run directory — it is never written or padded
from a model's memory of the run. So a decision no lane recorded is simply absent, and the page
says so rather than implying none were made.

An approved plan for `/deep-execute` extends deep-plan's normal plan format with an
**Execution shape** (`Mode: parallel`, exactly one `orchestrator` lane, a lane table of
`owns` path globs / `test_command` / `agent` / `depends_on`) and an **API contract** (a
single materialized, versioned file every lane treats as read-only after fanout).
`validate-plan.sh --root` enforces this shape before `/deep-execute` will accept the plan.
The lane boundary itself is enforced by `changed-files-within-union` — a git-only diff
against the round's baseline commit; per-lane attribution (`worker-<lane>.files.txt`) is
self-declared and unauthenticated, so treat it as a diagnostic, never as proof of who wrote
what.

Run `just test-deep-pipeline` to exercise the whole pipeline's shell test suites (700+
assertions across plan validation, lane/ownership boundaries, the event/reply protocol,
round gating, and an end-to-end integration test walking a real plan through
`validate-plan.sh` → `init-run.sh` → `validate-contract.sh` → `validate-run-state.sh`).

### Pre-commit
- **`.pre-commit-config.yaml`** - Pre-commit hooks for:
  - Shell script linting (shellcheck, shfmt)
  - YAML linting (yamllint)
  - Markdown linting (markdownlint)
  - Python formatting (black, isort, ruff)
  - Secrets detection (gitleaks)
  - Spell checking (codespell)

## MCP Servers

The following MCP servers are configured for Claude Code:

- **context7** - Up-to-date library documentation
- **sequential-thinking** - Enhanced reasoning capabilities
- **playwright** - Browser automation for testing
- **filesystem** - Enhanced file operations in ~/Developer
- **memory** - Persistent context across sessions
- **gitnexus** - Codebase knowledge graph for AI agents

## Git Workflow Enhancements

### P4Merge - Visual Merge Tool

P4Merge (Perforce Visual Merge Tool) is configured as the default merge and diff tool for handling merge conflicts visually.

**Usage:**
```bash
# Resolve merge conflicts visually
git mergetool

# Compare files visually
git difftool <file>

# Switch back to nvim for quick merges (optional)
git config merge.tool nvimdiff
```

**Features:**
- 3-way merge view (BASE, LOCAL, REMOTE)
- Visual conflict highlighting
- Side-by-side diff comparison
- Better for complex conflicts than terminal-based tools

### Git Aliases
Over 40 useful git aliases are configured in `.gitconfig`:

**Status & Info:**
- `git s` - Short status
- `git st` - Full status

**Branches:**
- `git br` - List branches
- `git bra` - List all branches (including remotes)

**Log:**
- `git l` - Oneline log with graph
- `git lg` - Pretty log with colors
- `git last` - Show last commit with stats

**Common Operations:**
- `git co` - Checkout
- `git cm` - Commit with message
- `git ps` - Push
- `git p` - Pull
- `git d` - Diff
- `git ds` - Diff staged

**Utilities:**
- `git unstage` - Unstage files
- `git undo` - Undo last commit (soft reset)
- `git clean-branches` - Delete merged branches

Run `git config --get-regexp alias` to see all configured aliases.

## Troubleshooting

### Pre-commit hooks not running
```bash
just install-hooks
# or
pre-commit install
```

### Packages not installing
```bash
chezmoi apply -v
# or
just apply
```

### Cursor extensions failing
Some extensions may not be compatible with your Cursor version. Check the output and install manually if needed.

### Shell changes not taking effect
```bash
source ~/.zshrc
# or restart your terminal
```

### Git diff not using delta
```bash
git config --get core.pager
# Should show "delta"
# If not, run: chezmoi apply -v
```

## Docker Compose Examples

Pre-configured Docker Compose files for common data engineering and ML infrastructure are available in `~/.config/docker-compose-examples/`.

### Available Services

| Service | File | Ports | Usage |
|---------|------|-------|-------|
| PostgreSQL | `postgres.yml` | 5432 | `docker-compose -f ~/.config/docker-compose-examples/postgres.yml up -d` |
| Kafka + UI | `kafka.yml` | 9092, 8080 | `docker-compose -f ~/.config/docker-compose-examples/kafka.yml up -d` |
| Spark Cluster | `spark.yml` | 8080, 7077 | `docker-compose -f ~/.config/docker-compose-examples/spark.yml up -d` |
| ClickHouse | `clickhouse.yml` | 8123, 9000 | `docker-compose -f ~/.config/docker-compose-examples/clickhouse.yml up -d` |
| MLflow Server | `mlflow.yml` | 5000 | `docker-compose -f ~/.config/docker-compose-examples/mlflow.yml up -d` |

### Quick Start

```bash
# Navigate to examples directory
cd ~/.config/docker-compose-examples

# Start PostgreSQL
docker-compose -f postgres.yml up -d

# View logs
docker-compose -f postgres.yml logs -f

# Stop service
docker-compose -f postgres.yml down

# Stop and remove volumes (clean slate)
docker-compose -f postgres.yml down -v
```

See `~/.config/docker-compose-examples/README.md` for detailed usage instructions, connection examples, and troubleshooting tips.
