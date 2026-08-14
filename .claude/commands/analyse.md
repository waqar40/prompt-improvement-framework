---
description: "Analyse prompts — by default the WHOLE journal (all projects/branches), or narrowed to one --project/--branch/file. Scores each prompt, writes per-file reviews, and compiles the overall guide + machine-readable asset suggestions."
argument-hint: "[<file-or-dir> | --project <name> | --branch <name>] [--user <name>]"
allowed-tools: Read, Write, Edit, Glob, Grep, Skill, Bash
---

Read `.claude/skills/prompt-journal/SKILL.md` and follow it exactly.

Selector — **omit to analyse the whole journal** (the sibling `../prompts`); or narrow to a
single file/dir path, `--project <name>`, or `--branch <name>`:

$ARGUMENTS
