---
name: configure
description: Use to set up (or repair) the prompt-journal recorder hook in one step after cloning this repo — the /configure command. Detects the operating system, wires a UserPromptSubmit hook into the user's Claude Code settings so every prompt in every repo is captured into a sibling prompts/ folder beside the clone (relocatable with --journal), auto-fixes what it can (missing journal dir, stale/duplicate hooks, executable bit, missing settings.json), self-tests the recorder, and only asks the user to act when unavoidable — with clear, copy-pasteable steps. Triggers include "configure", "set up the hook", "install the recorder", "wire up prompt logging", "fix my prompt journal hook".
---

# Configure the prompt-journal recorder hook

One command to make a fresh clone fully working. The deterministic work lives in two
OS-specific scripts — this skill only **detects the OS, runs the right one, and relays the
result**. Do not reimplement the merge logic here; the scripts own it and are idempotent
(safe to re-run any time).

- Windows → `scripts/configure.ps1`
- macOS / Linux → `scripts/configure.sh`

Both derive the clone location from their own path (no hardcoded directory), register the
hook in the **global** `~/.claude/settings.json` by default (so prompts from *every* repo
are captured), point it at this clone's `scripts/record-prompt.*`, and land logs in a sibling
`prompts/` folder beside the clone (`<clone>/../prompts`) — kept out of the repo. Pass
`--journal <path>` (bash) / `-JournalDir <path>` (PowerShell) to relocate the journal.

## Workflow

### Step 1 — Detect the OS
Use the environment already known to you (platform) — or run `uname -s` (Unix) vs. the
presence of `%SystemRoot%` / PowerShell to disambiguate. Pick exactly one script.

### Step 2 — Run the configurator
Run it from the repo root and capture stdout + exit code. Do **not** edit `settings.json`
yourself — let the script do it so the result is deterministic and re-runnable.

- Windows: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/configure.ps1`
  (if `pwsh` is unavailable, use `powershell` with the same arguments)
- macOS / Linux: `bash scripts/configure.sh`

Pass `--project` (bash) / `-Project` (PowerShell) **only** if the user explicitly wants the
hook scoped to this repo instead of all repos.

### Step 3 — Interpret the output
The script prints tagged lines. Relay them faithfully:
- `[OK]` — already correct or verified. `[FIXED]` — the script auto-resolved it.
- `[ACTION]` — needs the human. Surface each `[ACTION]` line as a numbered, concrete step
  (e.g. "install PowerShell 7", "install jq or python3", "fix invalid JSON in settings.json").

Exit `0` = fully configured and self-test passed. Exit `1` = configured but actions remain.
Exit `2` = could not proceed (missing prerequisite) — the message says what to install.

### Step 4 — Report
Tell the user, in this order:
1. Whether the hook is now installed and the **self-test passed**.
2. What was auto-fixed (`[FIXED]` lines), if anything.
3. Any remaining `[ACTION]` steps — only if present; otherwise say none are needed.
4. **Restart Claude Code / start a new session** so it reloads `settings.json`, after which
   every prompt is logged to the sibling `<clone>/../prompts/`. Then `/analyse` (defaulting to
   `../prompts`) runs the review pipeline.

## Constraints
- ALWAYS run the OS-appropriate script rather than editing settings.json by hand — the script
  is idempotent, removes stale recorder hooks, and backs up invalid JSON.
- NEVER hardcode a clone path or a user's directory; the scripts resolve everything relative
  to themselves.
- NEVER leave the user guessing: if an `[ACTION]` remains, give the exact command or edit.
- ONLY require user intervention when the script reports `[ACTION]`; auto-fixable issues are
  the script's job.
