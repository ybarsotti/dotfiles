# Justfile for dotfiles management
# Just is a handy way to save and run project-specific commands
# Install just: brew install just

# Default recipe (shows available commands)
default:
    @just --list

# Run all validations (shellcheck, yamllint, etc.)
check:
    @echo "Running validations..."
    @echo "Checking shell scripts..."
    @find . -name "*.sh" -type f -not -path "*/\.*" -exec shellcheck {} \;
    @echo "✅ Shell scripts validated"
    @echo "Checking YAML files..."
    @yamllint .
    @echo "✅ YAML files validated"
    @echo "Checking for secrets..."
    @gitleaks detect --no-git
    @echo "✅ No secrets detected"

# Show what changes chezmoi would make
diff:
    chezmoi diff

# Preview changes in a pager
preview:
    chezmoi diff | bat --language=diff

# Apply dotfiles to home directory
apply:
    @echo "Applying dotfiles..."
    chezmoi apply -v

# Update dotfiles from git and apply
update:
    @echo "Updating dotfiles from git..."
    chezmoi update -v

# Check status of managed files
status:
    chezmoi status

# Open a shell in the chezmoi source directory
cd:
    @cd $(chezmoi source-path) && $SHELL

# Edit a specific file with chezmoi
edit FILE:
    chezmoi edit {{FILE}}

# Add a file to chezmoi management
add FILE:
    chezmoi add {{FILE}}

# Forget (stop managing) a file
forget FILE:
    chezmoi forget {{FILE}}

# Run pre-commit hooks on all files
pre-commit:
    @echo "Running pre-commit hooks..."
    pre-commit run --all-files

# Install pre-commit hooks
install-hooks:
    @echo "Installing pre-commit hooks..."
    pre-commit install
    pre-commit install --hook-type commit-msg
    @echo "✅ Pre-commit hooks installed"

# Update pre-commit hook versions
update-hooks:
    @echo "Updating pre-commit hooks..."
    pre-commit autoupdate

# Clean up and optimize git repository
optimize-git:
    @echo "Optimizing git repository..."
    @cd $(chezmoi source-path) && git gc --aggressive && git prune
    @echo "✅ Git repository optimized"

# Install all packages from packages.yaml
install-packages:
    @echo "Installing packages from packages.yaml..."
    chezmoi apply -v

# Update Homebrew and all packages
update-brew:
    @echo "Updating Homebrew..."
    brew update
    brew upgrade
    brew cleanup
    @echo "✅ Homebrew updated"

# Check for outdated Homebrew packages
outdated:
    @echo "Checking for outdated packages..."
    brew outdated

# Run security audit on npm packages (if package.json exists)
audit-npm:
    @echo "Running npm security audit..."
    @if [ -f package.json ]; then npm audit; else echo "No package.json found"; fi

# Run security audit on pip packages (if requirements.txt exists)
audit-pip:
    @echo "Running pip security audit..."
    @if [ -f requirements.txt ]; then pip-audit; else echo "No requirements.txt found"; fi

# Format all shell scripts
format-sh:
    @echo "Formatting shell scripts..."
    @find . -name "*.sh" -type f -not -path "*/\.*" -exec shfmt -w -i 2 {} \;
    @echo "✅ Shell scripts formatted"

# Format all YAML files
format-yaml:
    @echo "Formatting YAML files..."
    @prettier --write "**/*.{yml,yaml}"
    @echo "✅ YAML files formatted"

# Format all code
format: format-sh format-yaml
    @echo "✅ All files formatted"

# Create a backup of current dotfiles
backup:
    @echo "Creating backup..."
    @tar -czf ~/dotfiles-backup-$(date +%Y%m%d-%H%M%S).tar.gz ~/.config ~/.zshrc ~/.gitconfig ~/.tmux.conf 2>/dev/null || true
    @echo "✅ Backup created"

# Test dotfiles installation in a clean environment (requires Docker)
test-install:
    @echo "Testing dotfiles installation..."
    docker run --rm -it -v $(chezmoi source-path):/dotfiles ubuntu:latest bash -c "apt-get update && apt-get install -y git && cd /dotfiles && ./install.sh"

# Show system information
info:
    @echo "System Information:"
    @echo "=================="
    @echo "OS: $(uname -s)"
    @echo "Architecture: $(uname -m)"
    @echo "Shell: $SHELL"
    @echo "Chezmoi version: $(chezmoi --version)"
    @echo "Git version: $(git --version)"
    @which brew > /dev/null && echo "Homebrew version: $(brew --version | head -1)" || echo "Homebrew: not installed"

# Analyze repository statistics
stats:
    @echo "Repository Statistics:"
    @echo "====================="
    @echo "Total files managed: $(chezmoi managed | wc -l)"
    @echo "Total commits: $(cd $(chezmoi source-path) && git rev-list --count HEAD)"
    @echo "Repository size: $(cd $(chezmoi source-path) && du -sh . | cut -f1)"
    @echo "Last commit: $(cd $(chezmoi source-path) && git log -1 --format=%cd --date=short)"

# Clean up temporary files and caches
clean:
    @echo "Cleaning up..."
    @rm -rf ~/.cache/chezmoi 2>/dev/null || true
    @brew cleanup 2>/dev/null || true
    @echo "✅ Cleanup complete"

# Full update (git, brew, packages, apply)
full-update: update-brew update
    @echo "✅ Full update complete"
