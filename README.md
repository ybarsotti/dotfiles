# ~/. 📂 My dotfiles
managed with [`chezmoi`](https://github.com/twpayne/chezmoi).

## Installation

### Optional: Set hostname for automatic machine detection

For work machines, set a hostname containing "work", "corp", or "company" to automatically configure work-specific settings:

```console
# For work machines
$ sudo scutil --set HostName "yuri-work-macbook"
$ sudo scutil --set LocalHostName "yuri-work-macbook" 
$ sudo scutil --set ComputerName "Yuri Work MacBook"

# For personal machines (optional, will prompt if not set)
$ sudo scutil --set HostName "yuri-personal-macbook"
$ sudo scutil --set LocalHostName "yuri-personal-macbook"
$ sudo scutil --set ComputerName "Yuri Personal MacBook"
```

### Install dotfiles

```console
$ sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply ybarsotti
```

If you didn't set a work hostname, chezmoi will prompt you to choose machine purpose and configure appropriate email/git settings.


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
- **`pre-commit`** - Git hooks framework for running checks before commits
  - Setup: `pre-commit install`
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

### Development Utilities
- **`sst/tap/opencode`** - OpenCode CLI tool for development workflows
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
- **`go`** - Go programming language
  - Usage: `go run main.go`, `go build`, `go mod init`
- **`node`** + **`nvm`** - Node.js runtime and version manager
  - Usage: `nvm use 20`, `npm install`, `node script.js`
- **`python3`** + **`pipx`** - Python runtime and isolated package installer
  - Usage: `python3 script.py`, `pipx install package`
- **`lua`**, **`lua@5.1`**, **`luajit`**, **`luarocks`** - Lua runtime (multiple versions) and package manager
  - Usage: `lua script.lua`, `luarocks install package`
- **`zig`** - Zig programming language
  - Usage: `zig run main.zig`, `zig build`
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
- **`btop`** - Resource monitor with better interface than htop
  - Usage: `btop`
- **`fastfetch`** - System information display
  - Usage: `fastfetch`
- **`jq`** - JSON processor
  - Usage: `echo '{"key":"value"}' | jq .key`
- **`httpie`** - User-friendly HTTP client
  - Usage: `http GET httpbin.org/json`
- **`oha`** - HTTP load testing tool
  - Usage: `oha -n 100 -c 10 https://example.com`
- **`nmap`** - Network discovery and security auditing
  - Usage: `nmap -sP 192.168.1.0/24`
- **`pngpaste`** - PNG image clipboard utility for macOS
  - Usage: `pngpaste output.png` (paste clipboard image to file)
  - Required for Neovim img-clip.nvim plugin
- **`yazi`** - Terminal file manager
  - Usage: `yazi`
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
- **`evans`** - More expressive gRPC client for testing gRPC services
  - Usage: `evans -r repl -p 9090`, `evans --proto api.proto`

### AI/ML Development
- **`ollama`** - Run large language models locally
  - Usage: `ollama run llama3.2`, `ollama list`, `ollama pull mistral`
  - Start server: `ollama serve`

### Development Editors & Language Support
- **`neovim`** - Modern Vim-based text editor
  - Usage: `nvim file.txt`
- **`tree-sitter`** - Incremental parsing system for syntax highlighting
  - Used automatically by Neovim and other editors

### Shell Enhancements
- **`zsh-autosuggestions`** - Fish-like autosuggestions for Zsh
- **`zsh-syntax-highlighting`** - Fish-like syntax highlighting for Zsh
- **`jandedobbeleer/oh-my-posh/oh-my-posh`** - Cross-platform prompt theme engine

### Security & System Tools
- **`gnupg`** - GNU Privacy Guard for encryption
  - Usage: `gpg --gen-key`, `gpg --encrypt file.txt`
- **`borders`** - Window border customization for macOS
- **`doppler`** - Secrets management
  - Usage: `doppler login`, `doppler secrets`
- **`gibo`** - .gitignore boilerplate generator
  - Usage: `gibo dump Python > .gitignore`
- **`bfg`** - Git repository cleaner
  - Usage: `bfg --delete-files '*.jar' repo.git`
- **`zizmor`** - GitHub Actions security scanner
  - Usage: `zizmor .github/workflows/`

### Package Visualization
- **`youplot`** - Command-line data plotting
  - Usage: `seq 1 10 | youplot line`

### Build Tools
- **`cmake`** - Cross-platform build system generator
  - Usage: `cmake .`, `make`
- **`make`** - Build automation tool
  - Usage: `make`, `make install`

### Containerization
- **`docker`** - Container platform
  - Usage: `docker run`, `docker build`, `docker-compose up`
