#!/bin/bash
# Test: chezmoi apply idempotency — running apply twice should be a no-op.
# Catches scripts that fail when tools are already installed (e.g., npm global conflicts).
set -euo pipefail

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

CHEZMOI_FLAGS=("--exclude=externals,encrypted")
CHECKSUM_DIR=$(mktemp -d)

echo "=== Idempotency Test ==="

# ---------- 1. First apply ----------
echo ""
echo "--- First apply ---"
APPLY_LOG=$(mktemp)
if chezmoi apply "${CHEZMOI_FLAGS[@]}" > "$APPLY_LOG" 2>&1; then
  pass "First apply exited 0"
else
  fail "First apply exited non-zero"
  cat "$APPLY_LOG"
  rm -f "$APPLY_LOG"
  echo "Aborting — cannot test idempotency if first apply fails."
  exit 1
fi
rm -f "$APPLY_LOG"

# ---------- 2. Snapshot checksums ----------
echo ""
echo "--- Snapshotting file checksums ---"

TRACKED_FILES=(
  "$HOME/.zshrc"
  "$HOME/.gitconfig"
  "$HOME/.zprofile"
  "$HOME/.gitignore_global"
  "$HOME/.config/starship.toml"
  "$HOME/.config/btop/btop.conf"
)

for f in "${TRACKED_FILES[@]}"; do
  if [ -f "$f" ]; then
    sha256sum "$f" >> "$CHECKSUM_DIR/before.txt"
  fi
done

# ---------- 3. Second apply ----------
echo ""
echo "--- Second apply ---"
APPLY_LOG=$(mktemp)
if chezmoi apply "${CHEZMOI_FLAGS[@]}" > "$APPLY_LOG" 2>&1; then
  pass "Second apply exited 0"
else
  fail "Second apply exited non-zero"
  cat "$APPLY_LOG"
  rm -f "$APPLY_LOG"
  echo "Aborting — cannot validate checksums if second apply failed."
  exit 1
fi
rm -f "$APPLY_LOG"

# ---------- 4. Verify checksums match ----------
echo ""
echo "--- Verifying file checksums ---"

for f in "${TRACKED_FILES[@]}"; do
  if [ -f "$f" ]; then
    sha256sum "$f" >> "$CHECKSUM_DIR/after.txt"
  fi
done

if diff -q "$CHECKSUM_DIR/before.txt" "$CHECKSUM_DIR/after.txt" > /dev/null 2>&1; then
  pass "All file checksums match after second apply"
else
  fail "File checksums changed after second apply:"
  diff "$CHECKSUM_DIR/before.txt" "$CHECKSUM_DIR/after.txt" || true
fi

# ---------- 5. Verify chezmoi diff is empty ----------
echo ""
echo "--- Verifying chezmoi diff is clean ---"

DIFF_OUTPUT=$(chezmoi diff "${CHEZMOI_FLAGS[@]}" 2>/dev/null || true)
if [ -z "$DIFF_OUTPUT" ]; then
  pass "chezmoi diff is empty (desired state matches actual)"
else
  fail "chezmoi diff is not empty after second apply:"
  echo "$DIFF_OUTPUT" | head -30
fi

# ---------- Cleanup ----------
rm -rf "$CHECKSUM_DIR"

# ---------- Summary ----------
echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

[ "$FAIL" -eq 0 ] || exit 1
