#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/qa_artifacts.py"
if [ ! -f "$SCRIPT" ]; then
  SCRIPT="$ROOT/scripts/executable_qa_artifacts.py"
fi
FIXTURES="$ROOT/tests/fixtures"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/evidence"
cp "$FIXTURES/qa-plan.yaml" "$TEST_DIR/qa-plan.yaml"
cp "$FIXTURES/results.json" "$TEST_DIR/results.json"
cp "$FIXTURES/evidence/checkout.png" "$TEST_DIR/evidence/checkout.png"
cp "$FIXTURES/evidence/checkout.webm" "$TEST_DIR/evidence/checkout.webm"

uv run "$SCRIPT" validate-plan "$TEST_DIR/qa-plan.yaml"
uv run "$SCRIPT" render-plan "$TEST_DIR/qa-plan.yaml" "$TEST_DIR/qa-plan.md"
grep -q "QA-CHECKOUT-001" "$TEST_DIR/qa-plan.md"

uv run "$SCRIPT" validate-results "$TEST_DIR/qa-plan.yaml" "$TEST_DIR/results.json"
uv run "$SCRIPT" render-report \
  "$TEST_DIR/qa-plan.yaml" \
  "$TEST_DIR/results.json" \
  "$TEST_DIR/index.html"

grep -q "Checkout confirmation" "$TEST_DIR/index.html"
grep -q "Requirements coverage" "$TEST_DIR/index.html"
grep -q "QA-CHECKOUT-001-01" "$TEST_DIR/evidence/QA-CHECKOUT-001.vtt"
test -s "$TEST_DIR/evidence/checkout-annotated.png"

if uv run "$SCRIPT" validate-plan "$FIXTURES/invalid-qa-plan.yaml" >/dev/null 2>&1; then
  echo "expected invalid plan to fail" >&2
  exit 1
fi

echo "qa artifacts integration: pass"
