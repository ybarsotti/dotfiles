// Run: node --test docs/skills-map.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { extractEdges, frontmatter } from "./skills-map.mjs";

const known = {
  skills: new Set(["deep-review", "simplify", "plan", "qa-test-plan"]),
  commands: new Set(["pr", "deep-review"]),
  agents: new Set(["qa-ui"]),
  shared: new Set(["after-approval.md"]),
  namespaces: new Set(["superpowers"]),
};
const edges = (text) =>
  extractEdges(text, known).map(
    (e) => `${e.type}:${e.kind}:${e.target}@${e.line}`,
  );

test("invokes skill: Skill() call, backticked name, prose, plugin name", () => {
  assert.deepEqual(edges('Skill(skill="simplify")\nSkill(qa-test-plan)'), [
    "invoke:skill:simplify@1",
    "invoke:skill:qa-test-plan@2",
  ]);
  assert.deepEqual(
    edges("Invoke the `deep-review` skill. invoke this skill."),
    ["invoke:skill:deep-review@1"],
  );
  assert.deepEqual(edges("use `superpowers:writing-plans` and `file:line`"), [
    "invoke:external:superpowers:writing-plans@1",
  ]);
  assert.deepEqual(edges('Skill(skill="missing-one")'), [
    "invoke:external:missing-one@1",
  ]);
});

test("spawns agent: known names, agents path, subagent_type", () => {
  assert.deepEqual(edges("the `qa-ui` agent\nthe `Agent` tool"), [
    "agent:agent:qa-ui@1",
  ]);
  assert.deepEqual(
    edges('Read ~/.claude/agents/qa-ui.md\nsubagent_type: "ghost"'),
    ["agent:agent:qa-ui@1", "agent:external:ghost@2"],
  );
});

test("runs command: only real names, never a path segment", () => {
  assert.deepEqual(edges("run `/pr`, then /deep-review default"), [
    "command:command:pr@1",
    "command:command:deep-review@1",
  ]);
  assert.deepEqual(edges("$RUN_DIR/plan.md tmp/<slug>/plan ~/pr /unknown"), []);
  assert.deepEqual(edges("type /plan"), ["command:skill:plan@1"]);
});

test("reads shared doc", () => {
  assert.deepEqual(
    edges(
      "see `~/.claude/skills/_shared/after-approval.md` and _shared/gone.md",
    ),
    ["reads:shared:after-approval.md@1", "reads:external:gone.md@1"],
  );
});

test("frontmatter reads folded descriptions", () => {
  assert.deepEqual(
    frontmatter("---\nname: x\ndescription: |\n  one\n  two\n---\nbody"),
    {
      name: "x",
      description: "one two",
    },
  );
});
