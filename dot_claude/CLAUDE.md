# Global CLAUDE.md

## Project Management

We track our tickets and projects in Linear (https://linear.app), a project management tool.
We use the `lineark` CLI tool for communicating with Linear. Use your Bash tool to call the
`lineark` executable. Run `lineark usage` to see usage information.

## Personal Knowledge Base (qmd)

We use `qmd` as a local search engine for our Obsidian knowledge base. When the user asks about
topics they've studied, personal notes, technical concepts, or references from their knowledge base,
use the `qmd` CLI via Bash to search for relevant information before answering.

### Collections available:
- **technical-studies-db** — PostgreSQL internals (heap pages, MVCC, indexing, query optimization, WAL, locks)
- **technical-studies-courses** — Software architecture MBA (DevOps, SRE, Cloud, microservices, SOLID, CI/CD)
- **resources** — AI/ML, code snippets (React, Python), data engineering, database design, DevOps, security, Rust
- **career** — Interview prep, career development, management skills
- **career-archive** — Archived project PRDs and architecture docs

### How to search:
```bash
# Best results — hybrid search with reranking (recommended)
qmd query "your search terms"

# Filter by collection
qmd query "MVCC postgres" -c technical-studies-db

# Fast keyword search (no LLM)
qmd search "B-Tree index"

# Semantic similarity search
qmd vsearch "how to optimize database queries"

# Get full document content
qmd get <docid>

# JSON output for structured parsing
qmd query "topic" --json
```

### When to use qmd:
- User asks about something they previously studied or noted
- User references their Obsidian vault, notes, or knowledge base
- Looking up technical concepts the user has documented (especially PostgreSQL, architecture, DevOps)
- Finding code snippets or patterns from the user's collection
- Retrieving career/interview preparation notes

### Notes:
- Content is primarily in Portuguese (PT-BR) with English technical terms
- Search queries work in both Portuguese and English
- Run `qmd --help` for full CLI reference
