# Global AGENTS.md

@RTK.md

# graphify

- **graphify** (`~/.Codex/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
- When user types `/graphify`, invoke Skill tool with `skill: "graphify"` before anything else.

# caveman

- Activate `caveman` skill in full mode by default every session.
- `/caveman lite|full|ultra` overrides current level.
- `stop caveman` or `normal mode` disables it for current session.

# Writing Style — Simplified Technical English

Anything you write that outlives the conversation follows **ASD-STE100** (Simplified
Technical English): docs, code comments, commit messages, PR and issue text, plans,
reports, and memory files. Write complete sentences with articles. This prose is not chat.

## Rules
- One instruction per sentence. Procedural sentences hold 20 words or fewer, descriptive ones 25.
- Paragraphs hold 6 sentences or fewer, and cover one topic each.
- Use the active voice and the present tense. Write "the script reads the manifest", not "the manifest is read".
- One word carries one meaning. Choose a term and reuse it. A lane stays a lane; never rename it for variety.
- Keep noun clusters to 3 words. Write "the script that validates run state", not "the run state validation script".
- State technical facts plainly. Do not use idiom, metaphor, or slang for them.
- Write sequential actions as separate sentences or numbered steps. Do not chain them into one sentence.
- Say what to do. Prefer the positive instruction when it carries the same rule as the negative one.

## Length
- Give the answer first. Add the support after it. Do not write a preamble and do not restate the question.
- Do not summarise work that the diff or the tool output already shows.
- Delete a sentence that only signals effort, such as "I carefully reviewed every file".

## Precedence
- **Chat replies**: `caveman` wins while it is active. Fragments and dropped articles are its purpose. STE governs the persisted artifacts that caveman already exempts.
- **Code**: `ponytail` decides what gets built. STE shapes only the prose around it.
- **Never compress away** a negation, a number, a unit, an exact error string, or a safety warning. Brevity never outranks accuracy.
