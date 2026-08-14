---
description: "Review existing Claude Code assets (skill/agent/hook/command/rule/script — one or a whole .claude/ tree) against the shared quality gate: frontmatter, anatomy, the 7 rubrics, non-destructive permissions, model tier, and a shipped verification. Read-only — reports findings + PASS/FAIL, never edits."
argument-hint: "[<asset-file-or-dir>] [--focus <type|rubric>]   (default: ./.claude)"
allowed-tools: Read, Grep, Glob, Bash
---

Read `.claude/skills/artifact-reviewer/SKILL.md` and follow it exactly: run
`scripts/validate-frontmatter.py` first, then audit against
`.claude/skills/asset-architect/references/quality-gate.md`, and report a severity-ranked findings
report + score + PASS/FAIL with a fix per finding. Do NOT edit any asset — route fixes to `/scaffold-asset`.

The asset(s) to review (default `./.claude`):

$ARGUMENTS
