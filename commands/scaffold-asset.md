---
description: "Decide the right asset type + placement for a need and scaffold it (skill/subagent/hook/command/rule/script/plugin), grounded + deep-researched (code, topic, edge cases, Responsible AI, memory files). Asks rather than assumes, presents a written plan + draft before writing, and generates a real validation artifact on disk."
argument-hint: "<suggestion-id | inline need> [--repo <path>] [--confluence <url|id>] [--docs <path>] [--code <glob>] [--prompts <log|user>] [--user <name>]"
allowed-tools: Read, Write, Edit, Glob, Grep, Skill, Bash, WebSearch, WebFetch
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/asset-architect/SKILL.md` and follow it exactly: ground + deep-research
first (code, CLAUDE.md/rules, Confluence/docs/prompts/memory, topic + edge cases + Responsible AI —
never assume, ask when a source is missing), write and confirm the plan, then emit the artifact with
a real on-disk verification. Do NOT write any asset until the plan + draft are approved.

The candidate to build (a `suggestions/<user>.json` id, or an inline need) + any grounding flags:

$ARGUMENTS
