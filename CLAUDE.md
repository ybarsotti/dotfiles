# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a dotfiles repository managed with [chezmoi](https://github.com/twpayne/chezmoi), containing personal configuration files and development environment setup for macOS.

## Common Commands

### Core Chezmoi Workflow
- **Test changes**: `chezmoi diff` - Always run before applying to see what will change
- **Apply changes**: `chezmoi apply -v` - Sync dotfiles to home directory (use `-v` for verbose output)
- **Edit files**: `chezmoi edit [target-file]` - Edit source files safely (e.g., `chezmoi edit ~/.zshrc`)
- **Update from git**: `chezmoi update` - Pull latest changes and apply them
- **Check status**: `chezmoi status` - Show files that differ from source
- **Navigate to source**: `chezmoi cd` - Open shell in the source directory

### File Management
- **Add new files**: `chezmoi add [target-file]` - Add files from home directory to chezmoi
- **Remove management**: `chezmoi forget [target-file]` - Stop managing file (keeps in home directory)
- **Delete completely**: `chezmoi remove [target-file]` - Remove from both source and home directory

### Package Management
- **Install packages**: Packages are automatically installed via `run_onchange_*` scripts when you run `chezmoi apply`
- **Update package list**: Edit `.chezmoidata/packages.yaml` and run `chezmoi apply`
- **Manual brew bundle**: The install scripts use `brew bundle` with dynamically generated Brewfiles

## Architecture and Structure

### Key Files and Directories
- `.chezmoi.toml.tmpl` - Main configuration with GPG encryption, git settings, and data templates
- `.chezmoidata/packages.yaml` - Centralized package definitions for Homebrew (brews and casks)
- `.chezmoiexternal.toml` - External resources (git repos, archives) like nvim config, themes
- `.chezmoiignore.tmpl` - Files to ignore based on OS conditions
- `run_onchange_*` scripts - Automated package installation scripts that run when packages.yaml changes

### Template System
- Files use Go templates with conditional logic (e.g., `{{ if eq .chezmoi.os "darwin" }}`)
- Data is accessible via `.packages`, `.email`, etc. from the `[data]` section
- External resources are automatically managed and refreshed based on `refreshPeriod`
- OS-specific configurations are handled through template conditionals

### Package Management Architecture
- Packages are defined centrally in `.chezmoidata/packages.yaml`
- Two-stage installation: prerequisites first (`run_onchange_before_*`), then main packages
- `run_onchange_*` scripts automatically detect changes to package definitions
- Uses Homebrew's `brew bundle` with dynamically generated Brewfiles

### External Dependencies
- Neovim configuration: External git repo at `git@github.com:ybarsotti/nvim.git`
- Themes: Catppuccin themes for bat, btop, and delta automatically downloaded
- Tmux plugins: TPM and various plugins managed as external git repos
- All external resources have configured refresh periods (1h to 168h)

## Development Workflow

When making changes to dotfiles:
1. `chezmoi edit [file]` to edit the source
2. `chezmoi diff` to preview changes
3. `chezmoi apply -v` to apply changes
4. Commit and push from the chezmoi source directory (`chezmoi cd`)

When adding new packages:
1. Edit `.chezmoidata/packages.yaml`
2. Run `chezmoi apply` to trigger package installation
3. The `run_onchange_*` scripts will automatically install new packages
- When adding new packages, always update the @README.md file with instructions and information about the package, usage, main commands, etc
