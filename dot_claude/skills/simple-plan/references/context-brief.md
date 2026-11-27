# Phase 0 steps

This file belongs to `simple-plan`. `SKILL.md` names the step that needs it.

1. Find the affected directories from the task description.
2. Read the root `CLAUDE.md`, and every `CLAUDE.md` inside an affected directory.
3. Read every rule source that exists: `.claude/rules/`, `AGENTS.md`, `docs/business-rules/`,
   `docs/technical-rules/` and `docs/adr/`. Read every rule file that applies.
4. Read two or three existing files of the same kind as the files the change touches.
   Record the naming convention, the error style, the dependency-injection style, and the
   test layout.
5. Read the dependency manifest. List the libraries that the change will use.
6. Read the documentation of each of those libraries for the parts the change touches. Use
   the Context7 MCP server when it is available. Record the idiom the library expects.
7. Find the code with the code-intelligence tools first, and use grep only where they have
   no answer. Run `~/.claude/skills/deep-plan/scripts/bootstrap-codeintel.sh "$RUN_DIR"` to
   refresh the indexes. Serena serves the working directory and needs no activation.
   - Serena: `find_symbol`, `find_referencing_symbols` and `get_symbols_overview` for the
     symbols the change touches.
   - GitNexus: `query` and `context` for the flows, and `impact` for the blast radius.
   - Graphify: read `graphify-out/GRAPH_REPORT.md` when it exists.
8. When the task names a ticket, or the branch name holds a ticket key, read the ticket. Copy
   each acceptance criterion and each stated requirement into the brief, word for word. For a
   Jira key, run `~/.claude/skills/_shared/ticket-start.md` once.
9. Find the in-flight work. For each repository that the change touches, list the open and
   draft pull requests, the branches of the last 30 days, and the open tickets that touch the
   same endpoint, model or integration. Read each match and record its decisions in the
   brief. The plan builds on that work, not beside it.
