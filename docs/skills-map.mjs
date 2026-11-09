#!/usr/bin/env node
// Generates docs/skills-map.md and docs/skills-map.html from the skills, commands and agents in
// this chezmoi source. Node stdlib only. Run: `node docs/skills-map.mjs` (or `just skills-map`).
// The output is deterministic: a rerun on the same source gives no diff.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUT_MD = "docs/skills-map.md";
const OUT_HTML = "docs/skills-map.html";
const NOTES = "docs/skills-map.notes.md";
const MERMAID_URL =
  "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js";
const MARKED_URL = "https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js";
// Split the full graph by cluster above this node count. One graph of 67 nodes and 157 edges
// rendered as an unreadable tangle, so the limit sits well below the 80 nodes first assumed.
const SPLIT_ABOVE = 40;

// Work or sensitive terms, one regular expression per line, in a local file that git ignores, so
// the terms never enter the repository. A node whose name or description matches is dropped, and
// the generator refuses to write an output that contains one. Without the file, nothing is blocked.
const BLOCKLIST = path.join(ROOT, "docs/.skills-map-blocklist");
const terms = fs.existsSync(BLOCKLIST)
  ? fs.readFileSync(BLOCKLIST, "utf8").split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("#"))
  : [];
const BLOCKED = terms.length ? new RegExp(terms.join("|"), "i") : /(?!)/;

const CLUSTERS = {
  planning: [
    "deep-plan",
    "simple-plan",
    "deep-execute",
    "implement",
    "explore-options",
  ],
  review: ["deep-review", "simplify", "shed-light", "blindspot"],
  qa: ["qa-plan", "qa-execute", "qa-test-plan", "qa-business", "qa-ui"],
  "pr-ticket": [
    "pr",
    "pr-description",
    "address-pr-comments",
    "jira-workflow",
    "follow-up-jira",
  ],
  workflow: [
    "workflow-mode",
    "workflow-post-plan",
    "workflow-post-implementation",
    "workflow-finish",
  ],
  "media-design": [
    "annotated-screenshots",
    "video-demo",
    "ui-designer",
    "hallmark",
  ],
  study: ["anki"],
};
const CLUSTER_OF = Object.fromEntries(
  Object.entries(CLUSTERS).flatMap(([c, names]) => names.map((n) => [n, c])),
);

// ---------- scanning ----------

const rel = (p) => path.relative(ROOT, p).split(path.sep).join("/");
const exists = (p) => fs.existsSync(path.join(ROOT, p));

function listMd(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name !== "tests" && e.name !== "node_modules")
        out.push(...listMd(p));
    } else if (e.name.endsWith(".md")) out.push(p);
  }
  return out.sort();
}

export function frontmatter(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---/);
  if (!m) return {};
  const fm = {};
  const lines = m[1].split("\n");
  for (let i = 0; i < lines.length; i++) {
    const kv = lines[i].match(/^([\w-]+):\s*(.*)$/);
    if (!kv) continue;
    let val = kv[2].trim();
    if (/^[|>][-+]?$/.test(val)) {
      const block = [];
      while (i + 1 < lines.length && /^\s+\S|^\s*$/.test(lines[i + 1]))
        block.push(lines[++i].trim());
      val = block.join(" ").trim();
    }
    fm[kv[1]] = val.replace(/^["']|["']$/g, "");
  }
  return fm;
}

function scan() {
  const nodes = new Map(); // id -> node
  const dropped = [];
  const add = (type, name, file, files) => {
    const text = fs.readFileSync(file, "utf8");
    const fm = frontmatter(text);
    const node = {
      id: nodeId(type, name),
      type,
      name: fm.name && type !== "command" ? fm.name : name,
      file: rel(file),
      files: files.map(rel),
      description: fm.description || "",
    };
    if (BLOCKED.test(node.name) || BLOCKED.test(node.description)) {
      dropped.push(node.name);
      return;
    }
    if (!nodes.has(node.id)) nodes.set(node.id, node);
  };
  for (const base of ["dot_claude/skills", "dot_agents/skills"]) {
    if (!exists(base)) continue;
    for (const e of fs
      .readdirSync(path.join(ROOT, base), { withFileTypes: true })
      .sort(byName)) {
      const skillMd = path.join(ROOT, base, e.name, "SKILL.md");
      if (e.isDirectory() && e.name !== "_shared" && fs.existsSync(skillMd)) {
        add("skill", e.name, skillMd, listMd(path.join(ROOT, base, e.name)));
      }
    }
  }
  for (const [type, dir] of [
    ["command", "dot_claude/commands"],
    ["agent", "dot_claude/agents"],
    ["shared", "dot_claude/skills/_shared"],
  ]) {
    if (!exists(dir)) continue;
    for (const f of listMd(path.join(ROOT, dir))) {
      if (path.dirname(f) !== path.join(ROOT, dir)) continue;
      const base = path.basename(f);
      add(type, type === "shared" ? base : base.replace(/\.md$/, ""), f, [f]);
    }
  }
  return { nodes, dropped: dropped.sort() };
}

const byName = (a, b) => cmp(a.name, b.name);
export const nodeId = (type, name) =>
  ({ skill: "s_", command: "c_", agent: "a_", shared: "d_", external: "x_" })[
    type
  ] + name.replace(/\.md$/, "").replace(/[^A-Za-z0-9]+/g, "_");

// ---------- edge extraction ----------

/**
 * Extract references from markdown text.
 * known = { skills:Set, commands:Set, agents:Set, shared:Set, namespaces:Set }
 * Returns [{ type: 'invoke'|'agent'|'command'|'reads', target, kind, line }]
 * kind is the target node type: skill, command, agent, shared or external.
 */
export function extractEdges(text, known) {
  const out = [];
  const push = (type, target, kind, line) =>
    out.push({ type, target, kind, line });
  const skillKind = (n) => (known.skills.has(n) ? "skill" : "external");
  text.split("\n").forEach((ln, i) => {
    const line = i + 1;
    // invokes skill
    for (const m of ln.matchAll(
      /\bSkill\(\s*(?:skill\s*=\s*)?["']?([\w:.-]+)/g,
    ))
      push("invoke", m[1], skillKind(m[1]), line);
    for (const m of ln.matchAll(/`([\w:-]+)` skill\b/g))
      push("invoke", m[1], skillKind(m[1]), line);
    for (const m of ln.matchAll(/\binvoke (?:the )?([a-z][\w:-]*) skill\b/gi)) {
      if (known.skills.has(m[1])) push("invoke", m[1], "skill", line);
    }
    for (const m of ln.matchAll(/`([a-z][\w-]*):([a-z][\w-]*)`/g)) {
      if (known.namespaces.has(m[1]))
        push("invoke", `${m[1]}:${m[2]}`, "external", line);
    }
    // spawns agent
    for (const m of ln.matchAll(/`([\w:-]+)` agent\b|\bagent `([\w:-]+)`/g)) {
      const n = m[1] || m[2];
      if (known.agents.has(n)) push("agent", n, "agent", line);
    }
    for (const m of ln.matchAll(
      /agents\/([\w-]+)\.md|subagent_type["']?\s*[=:]\s*["']([\w:-]+)/g,
    )) {
      const n = m[1] || m[2];
      push("agent", n, known.agents.has(n) ? "agent" : "external", line);
    }
    // runs command: a /name that is a real command or skill, not part of a path
    for (const m of ln.matchAll(
      /(?<![\w./~>$})-])\/([a-z][a-z0-9-]*)(?![\w/.-])/g,
    )) {
      if (known.commands.has(m[1])) push("command", m[1], "command", line);
      else if (known.skills.has(m[1])) push("command", m[1], "skill", line);
    }
    // reads shared doc
    for (const m of ln.matchAll(/_shared\/([\w-]+\.md)/g)) {
      push("reads", m[1], known.shared.has(m[1]) ? "shared" : "external", line);
    }
  });
  return out;
}

function buildGraph() {
  const { nodes, dropped } = scan();
  const names = (t) =>
    new Set([...nodes.values()].filter((n) => n.type === t).map((n) => n.name));
  const known = {
    skills: names("skill"),
    commands: names("command"),
    agents: names("agent"),
    shared: names("shared"),
    namespaces: new Set(),
  };
  const sources = [...nodes.values()].flatMap((n) =>
    n.files.map((f) => ({
      n,
      f,
      text: fs.readFileSync(path.join(ROOT, f), "utf8"),
    })),
  );
  for (const { text } of sources)
    for (const m of text.matchAll(/Skill\(\s*(?:skill\s*=\s*)?["']?([\w-]+):/g))
      known.namespaces.add(m[1]);
  const edges = new Map();
  const missing = new Map(); // target id -> { name, refs:[] }
  for (const { n, f, text } of sources)
    for (const e of extractEdges(text, known)) {
      if (BLOCKED.test(e.target)) continue;
      const to = nodeId(e.kind, e.target);
      if (to === n.id) continue;
      if (e.kind === "command" && e.target === n.name) continue; // its own command
      if (e.kind === "external") {
        if (!nodes.has(to))
          nodes.set(to, {
            id: to,
            type: "external",
            name: e.target,
            files: [],
            description: "",
          });
        if (!missing.has(to)) missing.set(to, { name: e.target, refs: [] });
        missing.get(to).refs.push(`${f}:${e.line}`);
      }
      const key = `${n.id}|${to}|${e.type}`;
      if (!edges.has(key))
        edges.set(key, {
          from: n.id,
          to,
          type: e.type,
          at: `${f}:${e.line}`,
        });
    }
  const sortedNodes = [...nodes.values()].sort(
    (a, b) => cmp(typeRank(a), typeRank(b)) || cmp(a.name, b.name),
  );
  // A skill that mentions the command wrapping it (pr-description -> /pr) is not a flow.
  const wraps = new Set(
    [...edges.values()]
      .filter((e) => e.type === "invoke" && e.from.startsWith("c_"))
      .map((e) => `${e.to}|${e.from}`),
  );
  const sortedEdges = [...edges.values()]
    .filter((e) => !(e.type === "command" && wraps.has(`${e.from}|${e.to}`)))
    .sort((a, b) => cmp(a.from, b.from) || cmp(a.to, b.to) || cmp(a.type, b.type));
  return {
    nodes: sortedNodes,
    byId: nodes,
    edges: sortedEdges,
    missing,
    dropped,
  };
}

const cmp = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
const typeRank = (n) =>
  ["command", "skill", "agent", "shared", "external"].indexOf(n.type);
const countOfType = (nodes, type) => nodes.filter((n) => n.type === type).length;

function clusterOf(n) {
  if (n.type === "shared") return "shared-docs";
  if (n.type === "external") return "external";
  return CLUSTER_OF[n.name] || "other";
}

// ---------- mermaid ----------

const EDGE = {
  invoke: { arrow: "-->", color: "#2563eb", label: "invokes skill" },
  agent: { arrow: "==>", color: "#db2777", label: "spawns agent" },
  command: { arrow: "-.->", color: "#16a34a", label: "runs command" },
  reads: { arrow: "--o", color: "#9ca3af", label: "reads shared doc" },
};
const CLASSDEFS = [
  "classDef skill fill:#dbeafe,stroke:#2563eb,color:#0f172a",
  "classDef command fill:#dcfce7,stroke:#16a34a,color:#0f172a",
  "classDef agent fill:#fce7f3,stroke:#db2777,color:#0f172a",
  "classDef shared fill:#f3f4f6,stroke:#6b7280,color:#0f172a",
  "classDef external fill:#fef9c3,stroke:#a16207,color:#0f172a,stroke-dasharray:4 3",
  "classDef step fill:#ffffff,stroke:#6b7280,color:#0f172a,stroke-dasharray:2 2",
];

function shape(n) {
  let label = n.name;
  if (n.type === "command") label = `/${n.name}`;
  else if (n.type === "shared") label = `_shared/${n.name}`;
  const q = `"${label.replace(/"/g, "#quot;")}"`;
  return (
    {
      skill: `${n.id}(${q})`,
      command: `${n.id}([${q}])`,
      agent: `${n.id}{{${q}}}`,
      shared: `${n.id}[(${q})]`,
      external: `${n.id}[[${q}]]`,
    }[n.type] + `:::${n.type}`
  );
}

function graphDiagram(nodes, edges, title) {
  const out = ["flowchart LR"];
  if (title) out.push(`  %% ${title}`);
  const groups = new Map();
  for (const n of nodes) {
    const c = clusterOf(n);
    if (!groups.has(c)) groups.set(c, []);
    groups.get(c).push(n);
  }
  for (const c of [...groups.keys()].sort()) {
    out.push(
      `  subgraph cl_${c.replace(/-/g, "_")}["${c}"]`,
      "    direction TB",
    );
    for (const n of groups.get(c)) out.push(`    ${shape(n)}`);
    out.push("  end");
  }
  edges.forEach((e) => out.push(`  ${e.from} ${EDGE[e.type].arrow} ${e.to}`));
  edges.forEach((e, i) =>
    out.push(`  linkStyle ${i} stroke:${EDGE[e.type].color}`),
  );
  out.push(...CLASSDEFS.map((c) => `  ${c}`));
  return out.join("\n");
}

// The main chains, drawn by hand from the files they cite. `ref` names a scanned node; the
// generator fails when that node disappears, so the diagram cannot silently drift.
const PHASES = [
  ["intake", "Intake"],
  ["plan", "Plan"],
  ["build", "Build"],
  ["review", "Review"],
  ["qa", "QA"],
  ["pr", "PR"],
  ["watch", "Watch"],
];
const CHAIN_NODES = [
  ["jw", "intake", "jira-workflow", "s_jira_workflow"],
  ["jw_setup", "intake", "ticket, branch", null],
  ["ts", "intake", "_shared/ticket-start.md", "d_ticket_start"],
  ["wm", "intake", "workflow-mode", "s_workflow_mode"],
  ["dp", "plan", "/deep-plan", "c_deep_plan"],
  ["sp", "plan", "/simple-plan", "c_simple_plan"],
  ["qap", "plan", "/qa-plan", "c_qa_plan"],
  ["pa", "plan", "Plannotator approval", null],
  ["wpp", "plan", "workflow-post-plan", "s_workflow_post_plan"],
  ["aa", "build", "_shared/after-approval.md", "d_after_approval"],
  ["rt", "build", "_shared/plan-routing.md", "d_plan_routing"],
  ["de", "build", "/deep-execute (option A)", "c_deep_execute"],
  ["impl", "build", "implement (option B)", "s_implement"],
  ["fast", "build", "fast mode: implement and test", null],
  ["dr", "review", "/deep-review", "c_deep_review"],
  ["simp", "review", "simplify", "s_simplify"],
  [
    "wpi",
    "review",
    "workflow-post-implementation",
    "s_workflow_post_implementation",
  ],
  ["qaui", "qa", "qa-ui agent", "a_qa_ui"],
  ["qabiz", "qa", "qa-business agent", "a_qa_business"],
  ["qtp", "qa", "/qa-test-plan", "c_qa_test_plan"],
  ["fix", "qa", "separate fixer agent", null],
  ["wf", "pr", "workflow-finish", "s_workflow_finish"],
  ["pr", "pr", "/pr (pr-description)", "c_pr"],
  ["bs", "pr", "blindspot", "s_blindspot"],
  ["rep", "pr", "HTML run report", null],
  ["watch", "watch", "PR watch: Monitor, then loop", null],
  ["apc", "watch", "address-pr-comments", "s_address_pr_comments"],
  ["fuj", "watch", "follow-up-jira", "s_follow_up_jira"],
];
const CHAINS = [
  {
    name: "build chain (deep-plan, simple-plan)",
    color: "#2563eb",
    edges: [
      ["dp", "qap", "Phase 2.4"],
      ["qap", "pa"],
      ["sp", "pa"],
      ["dp", "rt", "Phase 0.4"],
      ["sp", "rt", "Phase 0.5"],
      ["pa", "aa", "approved"],
      ["aa", "rt", "executor"],
      ["rt", "de", "A"],
      ["rt", "impl", "B"],
      ["de", "dr"],
      ["impl", "dr"],
      ["dr", "simp", "Phase 5"],
      ["dr", "qaui"],
      ["dr", "qabiz"],
      ["qabiz", "qtp", "qa-plan.yaml"],
      ["qaui", "fix"],
      ["qabiz", "fix"],
      ["fix", "pr"],
      ["pr", "bs", "Phase 2.7"],
      ["pr", "rep"],
      ["pr", "watch", "Phase 5"],
      ["watch", "apc"],
    ],
  },
  {
    name: "workflow stage chain",
    color: "#16a34a",
    edges: [
      ["wm", "rt", "criteria"],
      ["wm", "dp", "standard"],
      ["wm", "sp", "standard"],
      ["pa", "wpp"],
      ["wpp", "aa"],
      ["dr", "wpi", "step 7.0"],
      ["wpi", "wf"],
      ["wf", "pr"],
      ["wm", "fast", "fast"],
      ["fast", "wf"],
    ],
  },
  {
    name: "jira-workflow chain",
    color: "#ea580c",
    edges: [
      ["jw", "jw_setup"],
      ["jw_setup", "ts"],
      ["ts", "dp", "--ticket"],
      ["sp", "ts", "Jira key"],
      ["watch", "fuj", "after deploy"],
      ["fuj", "pr", "new PR"],
    ],
  },
];

function chainDiagram(byId) {
  const out = ["flowchart LR"];
  for (const [phase, title] of PHASES) {
    out.push(`  subgraph ph_${phase}["${title}"]`, "    direction TB");
    for (const [id, p, label, ref] of CHAIN_NODES) {
      if (p !== phase) continue;
      if (ref && !byId.has(ref))
        throw new Error(`chain node ${id} refers to missing node ${ref}`);
      const type = ref ? byId.get(ref).type : "step";
      out.push(`    ${id}("${label}"):::${type}`);
    }
    out.push("  end");
  }
  const styles = [];
  let i = 0;
  for (const c of CHAINS) {
    for (const [a, b, label] of c.edges) {
      out.push(`  ${a} -->${label ? `|"${label}"|` : ""} ${b}`);
      styles.push(`  linkStyle ${i++} stroke:${c.color},stroke-width:2px`);
    }
  }
  out.push(...styles, ...CLASSDEFS.map((c) => `  ${c}`));
  return out.join("\n");
}

// ---------- documents ----------

const fence = (src) => "```mermaid\n" + src + "\n```";

function orphans(g) {
  const inbound = new Set(g.edges.map((e) => e.to));
  const triggered = (n) =>
    n.type === "command" ||
    (n.type !== "shared" &&
      /\buse\b|when the user|\/[a-z]/i.test(n.description));
  return g.nodes.filter(
    (n) => n.type !== "external" && !inbound.has(n.id) && !triggered(n),
  );
}

function markdown(g) {
  const notes = exists(NOTES)
    ? fs.readFileSync(path.join(ROOT, NOTES), "utf8").trim()
    : "_No notes file._";
  const count = (t) => countOfType(g.nodes, t);
  const countE = (t) => g.edges.filter((e) => e.type === t).length;
  const L = [];
  L.push("# Skills map", "");
  L.push(
    "<!-- Generated by docs/skills-map.mjs. Do not edit by hand. Edit docs/skills-map.notes.md for the duplicates section. -->",
    "",
  );
  L.push(
    "This page maps the Claude Code skills, commands and agents in this repository, and the flows between them.",
  );
  L.push(
    'A generator reads the source files and draws the graph. The "Possible duplicates" section is hand-written.',
    "",
  );
  L.push("## How to regenerate", "");
  L.push(
    "Run `just skills-map`, or `node docs/skills-map.mjs` from the repository root.",
  );
  L.push(
    "The generator reads `dot_claude/skills/**/*.md`, `dot_claude/commands/*.md`, `dot_claude/agents/*.md` and `dot_agents/skills/**/*.md`.",
  );
  L.push(
    "It writes `docs/skills-map.md` and `docs/skills-map.html`. A second run gives no diff.",
  );
  L.push(
    "Run `node --test docs/skills-map.test.mjs` to test the edge extraction.",
    "",
  );
  L.push(
    `Counts: ${count("skill")} skills, ${count("command")} commands, ${count("agent")} agents, ` +
      `${count("shared")} shared docs, ${count("external")} external references. ` +
      `${g.edges.length} edges: ${countE("invoke")} invokes skill, ${countE("agent")} spawns agent, ` +
      `${countE("command")} runs command, ${countE("reads")} reads shared doc.`,
    "",
  );

  L.push("## Diagram 1: the main chains", "");
  L.push(
    "Blue is the build chain of `deep-plan` and `simple-plan` (`_shared/after-approval.md`).",
  );
  L.push(
    "Green is the workflow stage chain for a repository with `.workflow/config.json`.",
  );
  L.push(
    "Orange is the Jira path: `jira-workflow` claims the ticket, then hands off to the blue chain. Dashed white boxes are steps, not files.",
    "",
  );
  L.push(fence(chainDiagram(g.byId)), "");

  L.push("## Diagram 2: the full graph", "");
  L.push(
    "Shapes: a rounded box is a skill, a stadium is a command, a hexagon is an agent, a cylinder is a shared doc, and a double-edged box is a reference to a skill that is not in this repository.",
  );
  L.push(
    "Edges: blue solid arrows invoke a skill, thick pink arrows spawn an agent, green dotted arrows mention or run a command (`/name`), and grey lines with a circle read a shared doc.",
    "",
  );
  if (g.nodes.length <= SPLIT_ABOVE) {
    L.push(fence(graphDiagram(g.nodes, g.edges)), "");
  } else {
    L.push(
      "The graph is too large for one diagram. Each cluster diagram shows the nodes of the cluster and the edges that start there. A node from another cluster appears as the target of such an edge.",
      "",
    );
    const clusters = [...new Set(g.nodes.map(clusterOf))].sort();
    for (const c of clusters) {
      if (c === "external") continue; // external nodes have no outbound edge
      const ids = new Set(
        g.nodes.filter((n) => clusterOf(n) === c).map((n) => n.id),
      );
      // Outbound edges only: each edge appears in exactly one cluster diagram.
      const edges = g.edges.filter((e) => ids.has(e.from));
      const used = new Set([...ids, ...edges.flatMap((e) => [e.from, e.to])]);
      L.push(
        `### Cluster: ${c}`,
        "",
        fence(
          graphDiagram(
            g.nodes.filter((n) => used.has(n.id)),
            edges,
          ),
        ),
        "",
      );
    }
  }

  L.push("## Possible duplicates", "", notes, "");

  L.push("## Orphans", "");
  const orph = orphans(g);
  L.push(
    'Nodes with no inbound edge and no user trigger (no command, and no "use when" in the description):',
    "",
  );
  L.push(
    ...(orph.length
      ? orph.map((n) => `- \`${n.file}\` (${n.type})`)
      : ["- None."]),
    "",
  );
  const inbound = new Set(g.edges.map((e) => e.to));
  const entry = g.nodes.filter((n) => n.type === "skill" && !inbound.has(n.id));
  L.push(
    "Skills that no other file references. Only the user or the description trigger starts them:",
    "",
    ...entry.map((n) => `- \`${n.name}\` (\`${n.file}\`)`),
    "",
  );
  L.push(
    "References to skills, agents or shared docs that this repository does not define. A name with a colon comes from a plugin. A name without a colon is a local skill, a plugin skill or a built-in, or the reference is broken:",
    "",
  );
  const miss = [...g.missing.values()].sort((a, b) => cmp(a.name, b.name));
  L.push(
    ...(miss.length
      ? miss.map(
          (m) =>
            `- \`${m.name}\`: ${[...new Set(m.refs)].map((r) => `\`${r}\``).join(", ")}`,
        )
      : ["- None."]),
    "",
  );

  L.push("## Edge list", "");
  L.push(
    "<details><summary>Every edge, with the first line that creates it</summary>",
    "",
  );
  L.push("| from | edge | to | evidence |", "|---|---|---|---|");
  const label = (id) => {
    const n = g.byId.get(id);
    return n.type === "command" ? `/${n.name}` : n.name;
  };
  for (const e of g.edges)
    L.push(
      `| ${label(e.from)} | ${EDGE[e.type].label} | ${label(e.to)} | \`${e.at}\` |`,
    );
  L.push("", "</details>", "");
  return L.join("\n");
}

function html(md) {
  const data = JSON.stringify(md).replace(/</g, "\\u003c");
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Skills Map</title>
<!-- Generated by docs/skills-map.mjs from the same Markdown as docs/skills-map.md. -->
<style>
  :root { --bg:#ffffff; --fg:#111827; --muted:#4b5563; --line:#e5e7eb; --code:#f3f4f6; --link:#1d4ed8; }
  @media (prefers-color-scheme: dark) { :root { --bg:#0d1117; --fg:#e6edf3; --muted:#9ca3af; --line:#30363d; --code:#161b22; --link:#58a6ff; } }
  body { margin:0; background:var(--bg); color:var(--fg); font:15px/1.55 system-ui, -apple-system, "Segoe UI", sans-serif; }
  main { max-width:1200px; margin:0 auto; padding:24px 16px 64px; }
  a { color:var(--link); }
  code { background:var(--code); padding:1px 4px; border-radius:4px; font-size:.9em; overflow-wrap:anywhere; }
  table { border-collapse:collapse; display:block; overflow-x:auto; margin:12px 0; }
  th, td { border:1px solid var(--line); padding:6px 8px; text-align:left; vertical-align:top; }
  .mermaid { overflow-x:auto; background:#ffffff; border:1px solid var(--line); border-radius:8px; padding:12px; margin:12px 0; }
  details summary { cursor:pointer; color:var(--muted); }
</style>
</head>
<body>
<main id="doc">Loading…</main>
<script src="${MARKED_URL}"></script>
<script src="${MERMAID_URL}"></script>
<script>
  const md = ${data};
  const doc = document.getElementById('doc');
  doc.innerHTML = marked.parse(md);
  doc.querySelectorAll('pre > code.language-mermaid').forEach((code) => {
    const div = document.createElement('div');
    div.className = 'mermaid';
    div.textContent = code.textContent;
    code.parentElement.replaceWith(div);
  });
  // The class colors are light fills with dark text, so a light canvas reads well in both themes.
  mermaid.initialize({ startOnLoad: false, theme: 'default', securityLevel: 'strict', maxEdges: 2000, flowchart: { useMaxWidth: false } });
  mermaid.run({ querySelector: '.mermaid' });
</script>
</body>
</html>
`;
}

// ---------- main ----------

if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const g = buildGraph();
  const md = markdown(g);
  const page = html(md);
  for (const [file, body] of [
    [OUT_MD, md],
    [OUT_HTML, page],
  ]) {
    const hit = body.match(BLOCKED);
    if (hit)
      throw new Error(`${file} would contain the blocked term "${hit[0]}"`);
    fs.writeFileSync(path.join(ROOT, file), body);
  }
  const t = (x) => countOfType(g.nodes, x);
  console.log(
    `nodes=${g.nodes.length} (skill ${t("skill")}, command ${t("command")}, agent ${t("agent")}, ` +
      `shared ${t("shared")}, external ${t("external")}) edges=${g.edges.length}` +
      (g.dropped.length ? ` dropped=${g.dropped.length}` : ""),
  );
}
