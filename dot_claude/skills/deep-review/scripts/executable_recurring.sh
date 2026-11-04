#!/usr/bin/env bash
# recurring.sh — finds the findings of one review that earlier reviews already reported.
#
# Usage: recurring.sh <persisted-run-dir> [runs-root]
#
# A finding recurs when its title shares enough words with a finding in at least
# MIN_RUNS earlier runs of the same repository (same `- remote:` in context.md;
# runs recorded before that field existed count as the same repository). Such a
# finding is a candidate for a standing rule plus an automated check.
#
# Writes a markdown section to stdout, or nothing when no finding recurs.
# Matching is by word overlap, so the orchestrator confirms each match by reading
# the earlier titles before it proposes a rule.

set -euo pipefail

RUN="${1:?usage: recurring.sh <persisted-run-dir> [runs-root]}"
ROOT="${2:-${HOME}/.claude/deep-review-runs}"

python3 -I - "$RUN" "$ROOT" "${MIN_RUNS:-2}" "${MIN_SIMILARITY:-0.25}" <<'PY'
import json, os, re, sys

run, root, min_runs, min_sim = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4])
STOP = set("the a an of in on to for and or is are not no with without from by at as be its it this that "
           "when than into per only still can has have does via but".split())


def remote(run_dir):
    try:
        with open(os.path.join(run_dir, "context.md")) as f:
            for line in f:
                if line.startswith("- remote:"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return None


def findings(run_dir):
    """(title, severity) per finding: findings.jsonl first, else the report table."""
    path = os.path.join(run_dir, "findings.jsonl")
    if os.path.exists(path) and os.path.getsize(path):
        with open(path) as f:
            return [(r["title"], r.get("severity", "")) for r in map(json.loads, filter(str.strip, f))]
    rows = []
    try:
        with open(os.path.join(run_dir, "report.md")) as f:
            for line in f:
                cells = [c.strip() for c in line.split("|")]
                if len(cells) > 5 and re.fullmatch(r"\d+", cells[1]) and cells[2] in (
                        "CRITICAL", "HIGH", "MEDIUM", "LOW", "QUESTION"):
                    rows.append((cells[4], cells[2]))
    except OSError:
        pass
    return rows


def words(title):
    return {w for w in re.findall(r"[a-z0-9_]{3,}", title.lower()) if w not in STOP}


here = remote(run)
current = findings(run)
history = []
for name in sorted(os.listdir(root)):
    other = os.path.join(root, name)
    if os.path.realpath(other) == os.path.realpath(run) or not os.path.isdir(other):
        continue
    theirs = remote(other)
    if here and here != "none" and theirs and theirs != here:
        continue
    history += [(name, t, words(t)) for t, _ in findings(other)]

rows = []
for title, severity in current:
    mine = words(title)
    if len(mine) < 2:
        continue
    hits = {}
    for name, past, theirs in history:
        sim = len(mine & theirs) / len(mine | theirs)
        if sim >= min_sim and sim > hits.get(name, ("", 0))[1]:
            hits[name] = (past, sim)
    if len(hits) >= min_runs:
        best = sorted(hits.items(), key=lambda kv: -kv[1][1])[:3]
        rows.append((len(hits), severity, title, "; ".join(f"{t} ({n[-4:]})" for n, (t, _) in best)))

if rows:
    print("## Recurring findings\n")
    print("Earlier reviews of this repository reported these too. Each one is a candidate for a")
    print("standing rule plus an automated check. Confirm the match before you propose the rule.\n")
    print("| earlier runs | severity | finding | earlier titles |")
    print("|---|---|---|---|")
    for n, sev, title, past in sorted(rows, key=lambda r: -r[0]):
        print(f"| {n} | {sev} | {title} | {past.replace('|', '/')} |")
PY
