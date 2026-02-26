#!/bin/bash
# Test: fresh chezmoi apply from a clean state
# Validates template rendering, file generation, and platform-specific ignores.
set -euo pipefail

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "=== Fresh Install Test ==="

# ---------- 1. chezmoi apply succeeds ----------
echo ""
echo "--- Running chezmoi apply ---"
APPLY_LOG=$(mktemp)
if chezmoi apply --exclude=externals,encrypted > "$APPLY_LOG" 2>&1; then
  pass "chezmoi apply exited 0"
else
  fail "chezmoi apply exited non-zero"
  cat "$APPLY_LOG"
  rm -f "$APPLY_LOG"
  echo "Aborting — cannot validate files if apply failed."
  exit 1
fi
rm -f "$APPLY_LOG"

# ---------- 2. Expected files exist ----------
echo ""
echo "--- Checking expected files ---"

EXPECTED_FILES=(
  "$HOME/.zshrc"
  "$HOME/.gitconfig"
  "$HOME/.zprofile"
  "$HOME/.gitignore_global"
  "$HOME/.config/starship.toml"
  "$HOME/.config/btop/btop.conf"
  "$HOME/.config/lazygit/config.yml"
  "$HOME/.config/lazydocker/config.yml"
  "$HOME/.config/yazi/yazi.toml"
)

for f in "${EXPECTED_FILES[@]}"; do
  if [ -f "$f" ]; then
    pass "$f exists"
  else
    fail "$f missing"
  fi
done

# ---------- 3. Template rendering works ----------
echo ""
echo "--- Checking template rendering ---"

if grep -q "ci-test-user" "$HOME/.gitconfig" 2>/dev/null; then
  pass ".gitconfig contains ci-test-user (from pre-seeded data)"
else
  fail ".gitconfig does not contain ci-test-user"
fi

if grep -q "test@ci.example.com" "$HOME/.gitconfig" 2>/dev/null; then
  pass ".gitconfig contains test@ci.example.com"
else
  fail ".gitconfig does not contain test@ci.example.com"
fi

# ---------- 4. Darwin-only paths absent on Linux ----------
echo ""
echo "--- Checking platform-specific ignores ---"

DARWIN_ONLY_PATHS=(
  "$HOME/.config/homebrew"
  "$HOME/.config/karabiner"
  "$HOME/.hammerspoon"
)

for p in "${DARWIN_ONLY_PATHS[@]}"; do
  if [ -e "$p" ]; then
    fail "$p should NOT exist on Linux"
  else
    pass "$p correctly absent on Linux"
  fi
done

# ---------- 5. Managed file count ----------
echo ""
echo "--- Checking managed file count ---"

MANAGED_COUNT=$(chezmoi managed --exclude=externals,encrypted | wc -l)
if [ "$MANAGED_COUNT" -ge 10 ]; then
  pass "Managed files: $MANAGED_COUNT (>= 10)"
else
  fail "Only $MANAGED_COUNT managed files (expected >= 10)"
fi

# ---------- Summary ----------
echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

[ "$FAIL" -eq 0 ] || exit 1
