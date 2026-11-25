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
- **`just test-deep-pipeline`** - Run the deep-plan / deep-execute / deep-review shell test suites (see "Deep-* Agent Pipeline" under Claude Code, below)
- **`just format`** - Format all shell scripts and YAML files
- **`just clean`** - Clean up temporary files and caches
- **`just info`** - Show system information
- **`just stats`** - Show repository statistics

Run `just` to see the full list of available commands.

## Documentation

| Document | What it covers |
|---|---|
| [docs/tools.md](docs/tools.md) | Every installed tool and package, by category, and the Homebrew tap trust |
| [docs/configuration.md](docs/configuration.md) | Cursor, Git, Zsh, Tmux, Wave Terminal, the agent group chat and pre-commit |
| [docs/agent-pipeline.md](docs/agent-pipeline.md) | Claude Code, the planning and build chain, its execution order, hooks and machine limits |
| [docs/skills-map.md](docs/skills-map.md) | The generated map of skills, commands and agents. Open `docs/skills-map.html` for the browsable site |
| [docs/mcp-servers.md](docs/mcp-servers.md) | MCP servers and the browser tools |
| [docs/git.md](docs/git.md) | P4Merge and the Git aliases |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Fixes for common problems |
| [docs/docker-compose.md](docs/docker-compose.md) | Local Docker Compose services |
