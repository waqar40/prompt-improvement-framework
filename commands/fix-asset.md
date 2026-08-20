---
description: "Apply the mechanical, fully-specified fixes from an artifact-reviewer findings report to an existing asset (dangling references, invalid frontmatter keys, stale table rows). Never authors new content — anything needing judgment is skipped and routed to /scaffold-asset."
argument-hint: "<asset-file> [--findings <path-or-json>]"
allowed-tools: Read, Edit, Grep, Glob, Bash
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/asset-fixer/SKILL.md` and follow it exactly: get a findings
report (run `/review-asset` on the target first if `--findings` wasn't given), apply only the
findings labeled mechanical, skip and report everything else with a reason, then re-run
`scripts/validate-frontmatter.py` on what changed. Never invent content; never edit a line no
finding cited.

The asset to fix, and optionally a findings report to apply:

$ARGUMENTS
