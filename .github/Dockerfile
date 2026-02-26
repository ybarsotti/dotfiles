# Test container for chezmoi dotfiles — validates template rendering,
# config file generation, and script idempotency on Linux.
#
# macOS-only features (Homebrew, casks, defaults) are skipped via
# {{ if eq .chezmoi.os "darwin" }} guards in the templates.

FROM ubuntu:24.04

# Avoid interactive prompts during apt installs
ENV DEBIAN_FRONTEND=noninteractive

# Trick system_info template into setting machineType = "virtual"
# instead of calling hostnamectl (unavailable in containers)
ENV CODESPACES=true

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    gpg \
    util-linux \
    && rm -rf /var/lib/apt/lists/*

# Install chezmoi
RUN sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin

# Create non-root test user
RUN useradd -m -s /bin/bash testuser
USER testuser
WORKDIR /home/testuser

# Pre-seed chezmoi config to bypass interactive prompts, GPG encryption,
# and Doppler secrets (none of which are available in CI)
RUN mkdir -p /home/testuser/.config/chezmoi
COPY --chown=testuser:testuser <<'EOF' /home/testuser/.config/chezmoi/chezmoi.toml
[data.machine]
  purpose = "personal"
  email = "test@ci.example.com"
  gitUser = "ci-test-user"

[data]
  email = "test@ci.example.com"
  dopplerProjectJson = ""

[git]
  autoAdd = true
  autoCommit = false

format = "yaml"
EOF

# Copy dotfiles source into chezmoi source directory
COPY --chown=testuser:testuser . /home/testuser/.local/share/chezmoi

ENTRYPOINT ["/bin/bash"]
