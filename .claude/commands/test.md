---
description: "End-to-end test the framework — runs the script harness, then drives every key skill/command over fixtures in an isolated _selftest sandbox and reports PASS/FAIL. Touches no real data."
argument-hint: "(no arguments)"
allowed-tools: Read, Write, Edit, Glob, Grep, Skill, Bash, PowerShell
---

Read `.claude/skills/test-framework/SKILL.md` and follow it exactly: run `scripts/selftest.sh`,
then drive prompt-critic, prompt-journal/`/analyse` (all selectors), asset-suggester,
asset-architect (draft-only), and `/catalog` under the `_selftest` user, checking each outcome
and tearing everything down. Report a PASS/FAIL checklist.

$ARGUMENTS
