# Troubleshooting

Fixes for common problems.

## Pre-commit hooks not running
```bash
just install-hooks
# or
pre-commit install
```

## Packages not installing
```bash
chezmoi apply -v
# or
just apply
```

## Cursor extensions failing
Some extensions may not be compatible with your Cursor version. Check the output and install manually if needed.

## Shell changes not taking effect
```bash
source ~/.zshrc
# or restart your terminal
```

## Git diff not using delta
```bash
git config --get core.pager
# Should show "delta"
# If not, run: chezmoi apply -v
```
