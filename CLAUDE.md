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
- `.chezmoi.toml.tmpl` - Main configuration with GPG encryption, git settings, and unified system detection
- `.chezmoidata/packages.yaml` - Centralized package definitions organized by logical categories
- `.chezmoiexternal.toml` - External resources (git repos, archives) with standardized refresh periods
- `.chezmoiignore.tmpl` - Files to ignore based on OS conditions
- `run_onchange_*` scripts (root) - Package installation scripts that run when packages.yaml changes
- `.chezmoiscripts/run_once_*` scripts - One-time setup scripts with logical execution order

### Script Organization and Execution Order
Scripts are organized with clear, descriptive names and logical execution order:

**Phase 1 - Prerequisites (run_before_):**
- `run_before_01_install_homebrew.sh.tmpl` - Install Homebrew first (critical dependency)

**Phase 2 - Package Management (run_onchange_):**
- `run_onchange_01_homebrew_taps.sh.tmpl` - Install required Homebrew taps
- `run_onchange_02_homebrew_packages.sh.tmpl` - Install all packages from categorized packages.yaml

**Phase 3 - Development Environment (run_once_ in .chezmoiscripts):**
- `run_once_01_install_language_runtimes.sh.tmpl` - Install Rust, mise, and language runtimes
- `run_once_02_setup_github_ssh.sh.tmpl` - Generate and configure GitHub SSH keys
- `run_once_03_install_development_tools.sh.tmpl` - Install development tools and extensions
- `run_once_04_setup_gpg_signing.sh.tmpl` - Generate GPG keys and configure git signing
- `run_once_05_configure_doppler.sh.tmpl` - Configure Doppler secrets management

**Phase 4 - Final Configuration (run_after_):**
- `run_after_01_apply_macos_defaults.sh.tmpl` - Apply macOS system defaults last

### Template System
- Files use Go templates with conditional logic (e.g., `{{ if eq .chezmoi.os "darwin" }}`)
- **Unified system detection**: `system_info` template provides `data.system.*` with CPU, machine type, and environment info
- **Shared templates**: `homebrew_path_setup` for consistent PATH setup, `error_handling` for robust error handling
- **Data structure**: Organized under `data.system.cpu.*`, `data.system.machine_type`, `data.system.environment.*`
- External resources are automatically managed and refreshed weekly (`refreshPeriod = "168h"`)

### Package Management Architecture
- **Categorized packages**: `.chezmoidata/packages.yaml` organized by function (development, code_quality, terminal, etc.)
- **Nested structure**: Packages grouped logically (e.g., `development.version_managers`, `terminal.file_tools`)
- **Two-stage installation**: Prerequisites (Homebrew, taps) then main packages with nested category support
- **Dynamic Brewfile generation**: Scripts recursively process categorized package structure
- **Consistent error handling**: All scripts use standardized `set -eufo pipefail`

### External Dependencies
- **Neovim configuration**: External git repo at `git@github.com:ybarsotti/nvim.git`
- **Themes**: Catppuccin themes for bat, btop, and delta automatically downloaded
- **Terminal multiplexers**: Both tmux and zellij supported with tmux plugins managed via external git repos
- **Standardized refresh periods**: All external resources refresh weekly (`refreshPeriod = "168h"`)
- **Consistent external resource management**: Git repos, archives, and individual files managed uniformly

## Development Workflow

When making changes to dotfiles:
1. `chezmoi edit [file]` to edit the source
2. `chezmoi diff` to preview changes
3. `chezmoi apply -v` to apply changes
4. Commit and push from the chezmoi source directory (`chezmoi cd`)

When adding new packages:
1. Edit `.chezmoidata/packages.yaml` and add packages to the appropriate category:
   - `development.*` for development tools, version managers, git tools, etc.
   - `code_quality.*` for linters, formatters, and code quality tools
   - `terminal.*` for terminal enhancement tools and utilities
   - `security.*` for security and privacy tools
   - Choose the most specific subcategory (e.g., `development.version_managers` for mise, nvm)
2. Run `chezmoi apply` to trigger automatic package installation
3. The `run_onchange_02_homebrew_packages.sh.tmpl` script will recursively process all categories
4. Always update the @README.md file with package information, usage, and main commands

### Package Categories Reference:
- `packages.darwin.brews.development.*` - Development tools and runtimes
- `packages.darwin.brews.code_quality.*` - Linters, formatters, hooks
- `packages.darwin.brews.terminal.*` - File tools, monitoring, shell enhancements
- `packages.darwin.brews.security.*` - Security and privacy tools
- `packages.darwin.casks.*` - GUI applications organized by purpose

** IMPORTANT **
After updating any script step, apply the changes with chezmoi
