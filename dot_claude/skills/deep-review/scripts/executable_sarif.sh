#!/usr/bin/env bash
# sarif.sh — converts recorded findings to SARIF 2.1.0 for GitHub code scanning.
#
# Usage: sarif.sh <run-dir>
#
# Reads <run-dir>/findings.jsonl, writes SARIF to stdout.
#
# GitHub builds a stable alert fingerprint from ruleId plus file path, so ruleId is the
# finding category, which is a closed set, and never the free-text title.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$1"
FINDINGS="${RUN_DIR}/findings.jsonl"

[ -f "$FINDINGS" ] || { printf 'sarif: ERROR: missing %s\n' "$FINDINGS" >&2; exit 1; }

# Merge first, with the same rule the report uses. Without it GitHub raises one alert per
# reviewer on the same line.
jq -s -f "${SCRIPT_DIR}/merge.jq" "$FINDINGS" | jq '
  def level: {"CRITICAL":"error","HIGH":"error","MEDIUM":"warning","LOW":"note"}[.] // "warning";

  . as $findings
  | {
      "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
      version: "2.1.0",
      runs: [{
        tool: {
          driver: {
            name: "deep-review",
            informationUri: "https://github.com/ybarsotti/dotfiles",
            rules: (
              $findings
              | map(.category) | unique
              | map({
                  id: .,
                  name: .,
                  shortDescription: { text: "deep-review \(.) reviewer" }
                })
            )
          }
        },
        results: (
          $findings | map({
            ruleId: .category,
            level: (.severity | level),
            message: {
              text: "[\(.severity)] \(.title) — \(.description // "") (evidence: \(.evidence)) [reported by \(.personas | join(", "))]"
            },
            locations: [{
              physicalLocation: {
                artifactLocation: { uri: (if .file == "-" then "." else .file end) },
                region: { startLine: (if .line > 0 then .line else 1 end) }
              }
            }]
          })
        )
      }]
    }
'
