---
description: "Verify/repair the prompt-journal recorder after install — detects your OS, confirms the plugin's UserPromptSubmit hook is working, auto-fixes issues (dirs, deps), self-tests, and guides you only if something needs your hands."
argument-hint: "[--legacy-hook] [--journal <path>]   (default: plugin hook already active; journal at ~/.claude/prompt-journal/prompts)"
allowed-tools: Read, Bash, PowerShell, Edit
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/configure/SKILL.md` and follow it exactly. Detect the OS, run
the matching `scripts/configure.*`, and relay every `[ACTION]` line as a clear numbered step.

Options (pass through if given):

$ARGUMENTS
