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
- **`gastown`** - Multi-agent orchestration (coordinates Claude, Codex, Gemini workers)
  - Usage: `gt install ~/gt --git`, `gt mayor attach`
  - Install: Via `brew install gastown`
- **`agent-deck`** - Terminal session manager TUI for AI coding agents
  - Usage: `agent-deck`
  - Install: Via `brew install asheshgoplani/tap/agent-deck`
- **`gitnexus`** - Codebase knowledge graph engine for AI agents
  - Usage: `npx gitnexus analyze`, `npx gitnexus setup`
  - MCP server: `claude mcp add gitnexus -- npx -y gitnexus@latest mcp`
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

**Development:** Apidog (API testing), Beekeeper Studio (SQL editor), cmux (Claude Code terminal session manager), Conductor (Claude Code + GitHub), Docker Desktop, Figma, Ghostty (terminal emulator), Visual Studio Code, P4Merge (visual merge tool)

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
- **`just install-hooks`** - Install pre-commit hooks
- **`just pre-commit`** - Run pre-commit hooks on all files
- **`just format`** - Format all shell scripts and YAML files
- **`just clean`** - Clean up temporary files and caches
- **`just info`** - Show system information
- **`just stats`** - Show repository statistics

Run `just` to see the full list of available commands.

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

### Claude Code
- **`~/.claude/settings.json`** - Claude Code settings with hooks and MCP servers
- **`~/.claude/commands/*.md`** - Custom slash commands:
  - `/test` - Run project tests
  - `/docs` - Generate documentation
  - `/refactor` - Suggest refactorings
  - `/deps` - Analyze dependencies

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
