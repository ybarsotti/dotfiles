# Tools and packages

Every tool that `.chezmoidata/packages.yaml` installs, by category. Update this file when you add a package.

## Code Quality & Linting
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
- **`crapper`**, **`dryer`**, **`mutator`** - Robert C. Martin's code-quality tools, used by the
  `ub-mode` skill. They are not Homebrew packages: `.chezmoiexternal.toml` pins each one to a
  commit in `~/.local/share/unclebob/`, and a wrapper in `~/.local/bin` runs it. The first run
  of each tool creates its `.venv` (Python 3.11 or later). They write `.metrics/`, which the
  global git ignore file ignores.
  - `crapper --changed --threshold 10` - CRAP score per function (complexity and coverage)
  - `dryer --changed --threshold 0.8` - structural duplication
  - `mutator --max-workers 2 src/file.py` - mutation testing (survivors and uncovered lines)
  - Bump: change the commit in the URL and its `checksum.sha256` together

## Version Managers & Runtimes
- **`mise`** - Universal runtime version manager (replaces nvm, rbenv, etc.)
  - Usage: `mise use node@lts`, `mise use python@3.12`, `mise list`
- **`pipx`** - Install Python packages in isolated environments
  - Usage: `pipx install package`, `pipx list`
- **`uv`** - Fast Python package installer and resolver
  - Usage: `uv pip install package`, `uv tool install package`
- **`luarocks`** - Lua package manager
  - Usage: `luarocks install package`

## Development Utilities
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

## System Tools & Terminal Enhancements
- **`ripgrep`** - Fast text search tool
  - Usage: `rg "pattern" file.txt`, `rg -i "case insensitive"`
- **`ast-grep`** - Structural search and rewrite over the tree-sitter AST (`sg`)
  - Usage: `ast-grep -p 'console.log($$$)' -l ts`, `ast-grep -p '$A == $B' -r '$A === $B' -U`
  - Pairs with ripgrep, does not replace it: `rg` matches text, so it also matches
    commented-out code and a name inside a string. `ast-grep` matches shape, which is what a
    codemod needs. It also ships an MCP server.
- **`ffmpeg`** - Audio and video encoder, with `ffprobe` for stream checks
  - Usage: `ffmpeg -i in.mp4 -vf scale=1280:-2 out.mp4`, `ffprobe -show_streams in.mp4`
  - The `video-demo` skill uses it to encode clips, mix the voice and verify the render
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

## Performance & Analysis Tools
- **`hyperfine`** - Command-line benchmarking tool (better than `time`)
  - Usage: `hyperfine 'command1' 'command2'`, `hyperfine --warmup 3 'npm test'`
- **`procs`** - Modern process viewer (better than `ps`)
  - Usage: `procs`, `procs firefox`, `procs --tree`
- **`dust`** - Disk usage analyzer (better than `du`)
  - Usage: `dust`, `dust -d 3` (limit depth), `dust -r` (reverse sort)
- **`tokei`** - Code statistics and line counter
  - Usage: `tokei`, `tokei --languages` (list supported languages), `tokei src/`

## API Development & Testing
- **`evans`** - Expressive gRPC client for testing gRPC services
  - Usage: `evans -r repl -p 9090`, `evans --proto api.proto`
- **`grpcurl`** - curl for gRPC services
  - Usage: `grpcurl localhost:9090 list`, `grpcurl -d '{"name":"test"}' localhost:9090 Service/Method`

## SSH Management (Personal only)
- **`sshs`** - TUI for SSH connections that reads from `~/.ssh/config`
  - Usage: `sshs` — navigate hosts with arrow keys, connect with Enter
  - Docs: https://github.com/quantumsheep/sshs
- **`mosh`** - Resilient SSH sessions that auto-reconnect on unstable connections
  - Usage: `mosh user@host` (drop-in replacement for `ssh`)
  - Works great on mobile/unstable networks, low-latency typing
  - Docs: https://mosh.org

## AI & Agent Tools
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
- **`agent-browser`** - Browser automation CLI for AI agents
  - Usage: `agent-browser open <url>`, `agent-browser screenshot out.png`, `agent-browser eval <js>`
  - Install: Via `brew install agent-browser`, then `agent-browser install` downloads its Chrome
  - The `annotated-screenshots` skill uses it to capture pages at 2x
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
- **`hermes`** - Hermes Agent CLI from Nous Research
  - Usage: `hermes`, `hermes-agent`
  - Install: `curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash` (automatic)
  - The installer builds its own uv virtual environment under `~/.hermes`
- **`openclaw`** - Multi-channel AI gateway with messaging integrations
  - Usage: `openclaw`, binary at `~/.openclaw/bin/openclaw`
  - Install: `curl -fsSL https://openclaw.ai/install.sh | bash` (automatic)
  - The installer brings a private Node runtime under `~/.openclaw/tools`
- **`orca`** - Orca app and CLI for agent worktrees, terminals, and artifacts
  - Usage: `orca worktree list`, `orca terminal send`
  - Install: `brew install --cask stablyai/orca/orca`
  - The plain `orca` cask in `homebrew/cask` is a different tool, so the token stays tap-qualified
- **Grok Bot** - xAI desktop agent that works across apps and tools
  - Install: `brew install --cask grok-bot`

## Data Engineering & Analytics

### Databases & CLI Tools
- **`duckdb`** - Fast in-process analytical database (embedded, no server required)
  - Usage: `duckdb mydata.db`, `duckdb -c "SELECT * FROM read_csv('data.csv')"`
  - Perfect for local analytics and ETL without spinning up a database server
- **ClickHouse** - OLAP database (use Docker, see Docker Compose examples)
  - Connect: `docker exec -it dev-clickhouse clickhouse-client`

### Data Format Tools
- **`xsv`** - Fast CSV command-line toolkit written in Rust
  - Usage: `xsv stats data.csv`, `xsv select column1,column3 data.csv`, `xsv search pattern data.csv`
- **`miller`** - Like awk/sed/cut for structured data (CSV, JSON, TSV, etc.)
  - Usage: `mlr --csv cut -f name,age data.csv`, `mlr --json stats1 -a sum -f price data.json`
- **`visidata`** - Interactive multitool for tabular data with TUI
  - Usage: `vd data.csv`, `vd data.json`, `vd database.db`

### Docker Infrastructure
For databases and heavy services (PostgreSQL, Kafka, Spark, etc.), use Docker Compose:
- See `~/.config/docker-compose-examples/` for ready-to-use configurations
- Available services: PostgreSQL, Kafka, Spark, ClickHouse, MLflow
- Quick start: `docker-compose -f ~/.config/docker-compose-examples/postgres.yml up -d`

## Development Editors & Language Support
- **`neovim`** - Modern Vim-based text editor
  - Usage: `nvim file.txt`
- **`cursor`** - AI-powered code editor CLI
  - Usage: `cursor .` to open current directory
  - Note: Installed via official Cursor install script
- **`tree-sitter`** - Incremental parsing system for syntax highlighting
  - Used automatically by Neovim and other editors

## Shell Enhancements
- **`zsh-autosuggestions`** - Fish-like autosuggestions for Zsh
- **`zsh-syntax-highlighting`** - Fish-like syntax highlighting for Zsh
- **`jandedobbeleer/oh-my-posh/oh-my-posh`** - Cross-platform prompt theme engine
- **`zoxide`** - Smarter cd that learns your habits (see System Tools section)
- **`atuin`** - Shell history with sync and search (see System Tools section)
- **`direnv`** - Per-directory environment variables (see Development Utilities section)

## Security & Privacy
- **`gnupg`** - GNU Privacy Guard for encryption
  - Usage: `gpg --gen-key`, `gpg --encrypt file.txt`
- **`pinentry-mac`** - macOS keychain integration for GPG
- **`age`** - Simple file encryption (modern GPG alternative)
  - Usage: `age-keygen -o key.txt`, `age -r recipient file.txt`
- **`sops`** - Encrypted secrets in Git repos
  - Usage: `sops -e secrets.yaml > secrets.enc.yaml`
- **`trivy`** - Container and IaC security scanner
  - Usage: `trivy image nginx:latest`, `trivy config .`
- **`semgrep`** - Static analysis for unsafe code patterns
  - Usage: `semgrep scan --config p/default`
- **`osv-scanner`** - Known vulnerabilities in lockfiles
  - Usage: `osv-scanner scan source -r .`
- **`gosec`** - Security linter for Go code
  - Usage: `gosec ./...`
- **`checkov`** - Misconfiguration in Dockerfiles, workflows, Kubernetes and Terraform
  - Usage: `checkov -d .`
- **`syft`** - SBOM of an image or a folder
  - Usage: `syft nginx:latest -o spdx-json=sbom.json`
- **`grype`** - Vulnerability scan of an SBOM or an image
  - Usage: `grype sbom:sbom.json --only-fixed`
- **`cosign`** - Sign and verify images and files with Sigstore
  - Usage: `cosign verify-blob --bundle file.sigstore.json file`
- **`conftest`** - Test configuration files against Rego policies
  - Usage: `conftest test --policy policy deploy.yaml`
- **`doppler`** - Secrets management
  - Usage: `doppler login`, `doppler secrets`
- **`aws-vault`** - Securely store and access AWS credentials
  - Usage: `aws-vault exec profile -- aws s3 ls`

## Package Visualization
- **`youplot`** - Command-line data plotting
  - Usage: `seq 1 10 | youplot line`

## Build Tools
- **`cmake`** - Cross-platform build system generator
  - Usage: `cmake .`, `make`
- **`make`** - Build automation tool
  - Usage: `make`, `make install`

## Containerization
- **`orbstack`** (cask) - Container and Linux VM runtime. It replaces Docker Desktop. The cask supplies the `docker`, `docker compose`, and `docker buildx` commands.
  - Usage: `docker run`, `docker build`, `docker compose up`
  - Manage the runtime: `orbctl start`, `orbctl stop`, `orb status`
  - Migrate from Docker Desktop: `orb docker migrate`

## GUI Applications (Casks)

**Browsers:** Arc, Brave, Firefox

**Development:** Apidog (API testing), Beekeeper Studio (SQL editor), Conductor (Claude Code + GitHub), OrbStack (containers and Linux VMs), Figma, Ghostty (terminal emulator), Wave Terminal (block/widget terminal with local-LLM AI panel), Visual Studio Code, P4Merge (visual merge tool), Slack CLI (create, run and deploy Slack apps: `slack login`, `slack create`, `slack run`, `slack deploy`)

**Productivity:** Alt-Tab (window switcher), Raycast (launcher), BetterDisplay, Stats (menu bar monitor), Slack, Notion

**Media:** OBS, Spotify

## Fonts

**Nerd Fonts** (with icon support): Hack, JetBrains Mono, Fira Code, Meslo LG, Sauce Code Pro, Caskaydia Cove, Iosevka, Victor Mono

**Standard Developer Fonts:** SF Pro, Fira Code, Cascadia Code, Monaspace (GitHub's superfamily)

## GitHub CLI Extensions

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

## Homebrew Tap Trust

Homebrew 6 refuses to load formulae or casks from a third-party tap until that tap is trusted, so
`run_onchange_01_homebrew_taps.sh.tmpl` runs `brew trust --tap` on each one after tapping. Trust means Homebrew will load and run that tap's Ruby formula code; it is
recorded in `~/.config/homebrew/trust.json` and reversed with `brew untrust <tap>`. The script
guards on `brew trust --help`, so it stays a no-op on Homebrew 5 and earlier.
