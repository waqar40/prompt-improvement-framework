---
description: "One-step setup/repair of the prompt-journal recorder hook — detects your OS, wires the UserPromptSubmit hook to this clone's recorder, auto-fixes issues, self-tests, and guides you only if something needs your hands."
argument-hint: "[--project] [--journal <path>]   (default: global hook + sibling ../prompts journal)"
allowed-tools: Read, Bash, PowerShell, Edit
---

Read `.claude/skills/configure/SKILL.md` and follow it exactly. Detect the OS, run the
matching `scripts/configure.*`, and relay every `[ACTION]` line as a clear numbered step.

Options (pass through if given):

$ARGUMENTS
