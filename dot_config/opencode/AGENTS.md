# Global OpenCode Instructions

## Code Intelligence

Use these project-aware code-intelligence tools when they are available. Do not create or modify project instruction files such as `AGENTS.md`, `CLAUDE.md`, or `CLAUDE.local.md` unless the user explicitly asks.

### Serena
- If the project has `.serena/project.yml`, activate the current project with the Serena MCP `activate_project` tool before symbol-level exploration or edits.
- Prefer Serena for exact symbol lookup, references, and surgical symbol edits.
- If Serena is unavailable, continue with normal file reads and mention the gap only when it materially affects confidence.

### GitNexus
- If the project has a GitNexus index (`.gitnexus/`) or GitNexus MCP resources, use GitNexus for architecture discovery, execution flows, blast radius, and pre-commit scope checks.
- Before modifying a function, class, or method in an indexed project, run GitNexus impact analysis for that symbol when the tool is available. If the result is HIGH or CRITICAL risk, warn before editing.
- Before committing in an indexed project, run GitNexus change detection when available.
- If GitNexus reports a stale index, run `npx gitnexus analyze` from the project root before relying on it.

### Graphify
- If `graphify-out/GRAPH_REPORT.md` exists in the project root, read it before broad architecture/codebase questions.
- If `graphify-out/wiki/index.md` exists, prefer the wiki for navigation before raw file search.
- For cross-module or code-plus-docs questions, prefer `graphify query`, `graphify path`, or `graphify explain` when the graph exists.
- After code changes in a project with `graphify-out/graph.json`, run `graphify update .` when practical to keep the local graph fresh.

### Tool Choice
- Broad understanding: Graphify first, then GitNexus for execution flows.
- Blast radius and refactors: GitNexus first.
- Exact symbol reads/edits: Serena first.
- Project-specific `AGENTS.md` instructions override this global fallback when they are more specific.
