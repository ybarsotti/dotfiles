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

## Machine Purpose (Personal vs Work)

This repo supports two machine types via `machine.purpose` (set during `chezmoi init`):
- **personal** — Uses `yuribarsotti@gmail.com` / `ybarsotti`, includes tools like qmd, Linear, ollama
- **work** — Uses work email / git username, may exclude personal-only tools

To make a template conditional per machine, use:
```
{{ if eq .machine.purpose "personal" }}
  ...personal-only...
{{ else if eq .machine.purpose "work" }}
  ...work-only...
{{ end }}
```

The value is stored in `.chezmoi.toml` under `[data.machine]` and accessed as `.machine.purpose` in templates.
Files that differ per machine should use `.tmpl` extension with these conditionals.

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

## Testing & CI

### Local Validation (before pushing)
- **`just validate`** — Full validation pipeline: lint + pre-commit + Docker tests
- **`just lint`** — Run shellcheck (`.sh` + `.sh.tmpl`), yamllint, gitleaks
- **`just validate-hooks`** — Run pre-commit hooks on all files
- **`just validate-ci`** — Run GitHub Actions locally with `act`
- **`just test-fresh`** — Docker test: fresh `chezmoi apply` from clean state
- **`just test-idempotency`** — Docker test: verify `chezmoi apply` twice is safe
- **`just test-all`** — Run both Docker tests

### CI Pipeline (GitHub Actions)
Three jobs run on push/PR to `main`:
1. **Lint** — shellcheck, yamllint, gitleaks
2. **Fresh Install** — Docker-based `chezmoi apply` on Ubuntu 24.04
3. **Idempotency** — Verifies running apply twice produces no changes

### Docker Test Architecture
- `.github/Dockerfile` — Ubuntu 24.04 container with pre-seeded `chezmoi.toml` (bypasses GPG, Doppler, interactive prompts)
- `CODESPACES=true` env tricks `system_info` template to avoid `hostnamectl`
- `--exclude=externals,encrypted` skips SSH-requiring git repos and GPG-encrypted files
- All macOS-only scripts are no-ops on Linux via `{{ if eq .chezmoi.os "darwin" }}` guards

### Pre-commit Hooks
The repo has `.pre-commit-config.yaml` with: trailing-whitespace, shellcheck, yamllint, gitleaks, detect-private-key.
Install with `just install-hooks` or `pre-commit install`.

## Claude Code Configuration

### MCP Servers
MCP servers are split by account type in `.chezmoidata/mcp-server.yml`:
- `mcp_servers.shared` — loaded on all machines
- `mcp_servers.personal` — loaded only on `machine.purpose = "personal"`
- `mcp_servers.work` — loaded only on `machine.purpose = "work"`

The template `dot_claude/mcp_servers.json.tmpl` merges `shared` + the typed section automatically.

### Asking About Account Type
**IMPORTANT**: When the user asks to install, configure, or add anything related to Claude Code
(MCP servers, plugins, hooks, settings, commands, etc.), **always ask first**:
> "Isso é para a máquina pessoal, de trabalho, ou ambas?"
This prevents configurations from landing in the wrong account context.

** IMPORTANT **
After updating any script step, apply the changes with chezmoi

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **chezmoi** (112 symbols, 92 relationships, 0 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## When Debugging

1. `gitnexus_query({query: "<error or symptom>"})` — find execution flows related to the issue
2. `gitnexus_context({name: "<suspect function>"})` — see all callers, callees, and process participation
3. `READ gitnexus://repo/chezmoi/process/{processName}` — trace the full execution flow step by step
4. For regressions: `gitnexus_detect_changes({scope: "compare", base_ref: "main"})` — see what your branch changed

## When Refactoring

- **Renaming**: MUST use `gitnexus_rename({symbol_name: "old", new_name: "new", dry_run: true})` first. Review the preview — graph edits are safe, text_search edits need manual review. Then run with `dry_run: false`.
- **Extracting/Splitting**: MUST run `gitnexus_context({name: "target"})` to see all incoming/outgoing refs, then `gitnexus_impact({target: "target", direction: "upstream"})` to find all external callers before moving code.
- After any refactor: run `gitnexus_detect_changes({scope: "all"})` to verify only expected files changed.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

## Tools Quick Reference

| Tool | When to use | Command |
|------|-------------|---------|
| `query` | Find code by concept | `gitnexus_query({query: "auth validation"})` |
| `context` | 360-degree view of one symbol | `gitnexus_context({name: "validateUser"})` |
| `impact` | Blast radius before editing | `gitnexus_impact({target: "X", direction: "upstream"})` |
| `detect_changes` | Pre-commit scope check | `gitnexus_detect_changes({scope: "staged"})` |
| `rename` | Safe multi-file rename | `gitnexus_rename({symbol_name: "old", new_name: "new", dry_run: true})` |
| `cypher` | Custom graph queries | `gitnexus_cypher({query: "MATCH ..."})` |

## Impact Risk Levels

| Depth | Meaning | Action |
|-------|---------|--------|
| d=1 | WILL BREAK — direct callers/importers | MUST update these |
| d=2 | LIKELY AFFECTED — indirect deps | Should test |
| d=3 | MAY NEED TESTING — transitive | Test if critical path |

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/chezmoi/context` | Codebase overview, check index freshness |
| `gitnexus://repo/chezmoi/clusters` | All functional areas |
| `gitnexus://repo/chezmoi/processes` | All execution flows |
| `gitnexus://repo/chezmoi/process/{name}` | Step-by-step execution trace |

## Self-Check Before Finishing

Before completing any code modification task, verify:
1. `gitnexus_impact` was run for all modified symbols
2. No HIGH/CRITICAL risk warnings were ignored
3. `gitnexus_detect_changes()` confirms changes match expected scope
4. All d=1 (WILL BREAK) dependents were updated

## CLI

- Re-index: `npx gitnexus analyze`
- Check freshness: `npx gitnexus status`
- Generate docs: `npx gitnexus wiki`

<!-- gitnexus:end -->
