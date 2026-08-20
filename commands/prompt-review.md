---
description: "Alias of /analyse — run the prompt-journal pipeline over a log or directory (score prompts, update the store + guide, refresh asset suggestions)."
argument-hint: "[<file-or-dir> | --project <name> | --branch <name>] [--user <name>]"
allowed-tools: Read, Write, Edit, Glob, Grep, Skill, Bash
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/prompt-journal/SKILL.md` and follow it exactly. (`/analyse` is
the primary name for this pipeline; this alias is kept for back-compat.)

The target:

$ARGUMENTS
