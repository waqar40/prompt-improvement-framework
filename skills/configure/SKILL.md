---
name: configure
description: Use to verify (or repair) the prompt-journal recorder after installing this plugin — the /configure command. As an installed plugin all three recorder hooks (UserPromptSubmit, PostToolUse, Stop) wire themselves automatically via hooks/hooks.json; this skill's job is to make sure the rest of the setup actually works — the journal/outcomes dirs exist, the recorder self-tests clean, and the optional PDF/Word guide-rendering deps are installed. Also supports --legacy-hook for standalone (non-plugin) use, patching all three hooks into settings.json by hand the old way. Triggers include "configure", "set up the hook", "install the recorder", "wire up prompt logging", "fix my prompt journal hook".
---

# Configure the prompt-journal recorder

One command to make a fresh install fully working. The deterministic work lives in two
OS-specific scripts — this skill only **detects the OS, runs the right one, and relays the
result**. Do not reimplement the logic here; the scripts own it and are idempotent (safe to
re-run any time).

- Windows → `scripts/configure.ps1`
- macOS / Linux → `scripts/configure.sh`

**As an installed plugin, all three recorder hooks are already active** — `hooks/hooks.json`
wires `UserPromptSubmit` (`scripts/record-prompt.*`), `PostToolUse` (`scripts/record-tool-use.*`,
matcher-scoped to `Skill|Task|Read|Edit|Write|NotebookEdit`), and `Stop`
(`scripts/record-turn-end.*`) automatically, no settings.json edit required. By default the
scripts only: create the journal dir (default
`~/.claude/prompt-journal/prompts`) and the outcomes dir (default
`~/.claude/prompt-journal/prompts-review-outcomes`, both overridable with `PROMPT_JOURNAL_DIR`
/ `PROMPT_OUTCOMES_DIR` or `--journal`), self-test the recorder directly, and best-effort
install the pinned PDF/Word guide-rendering deps (`scripts/requirements.txt` —
`reportlab==4.1.0`, `python-docx==1.1.2`; capped below 4.2 for Python 3.8's `hashlib` compat).
This last step is **optional and never blocking** — the Markdown view, and the rest of the
pipeline, work with no Python deps at all.

Pass `--legacy-hook` (bash) / `-LegacyHook` (PowerShell) only if this repo is being run
**standalone**, not as an installed plugin (e.g. developing on the framework itself) — it
patches all three hooks into `settings.json` the old way. `--project`/`-Project` and
`--settings`/`-SettingsPath` imply `--legacy-hook`.

## Workflow

### Step 1 — Detect the OS
Use the environment already known to you (platform) — or run `uname -s` (Unix) vs. the
presence of `%SystemRoot%` / PowerShell to disambiguate. Pick exactly one script.

### Step 2 — Run the configurator
Run it from the plugin root and capture stdout + exit code. Do **not** edit `settings.json`
yourself — let the script do it so the result is deterministic and re-runnable.

- Windows: `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/configure.ps1`
  (if `pwsh` is unavailable, use `powershell` with the same arguments)
- macOS / Linux: `bash scripts/configure.sh`

Pass `--legacy-hook`/`-LegacyHook` only if the user explicitly says they're running this
outside the plugin system (a standalone clone).

### Step 3 — Interpret the output
The script prints tagged lines. Relay them faithfully:
- `[OK]` — already correct or verified. `[FIXED]` — the script auto-resolved it.
- `[OPTIONAL]` — a non-blocking gap in the PDF/Word guide-rendering deps only; mention it but
  don't treat it as unfinished setup. Give the printed `pip install -r scripts/requirements.txt`
  command if the user wants those formats.
- `[ACTION]` — needs the human. Surface each `[ACTION]` line as a numbered, concrete step
  (e.g. "install PowerShell 7", "install jq or python3", "fix invalid JSON in settings.json").

Exit `0` = fully configured and self-test passed. Exit `1` = configured but actions remain.
Exit `2` = could not proceed (missing prerequisite) — the message says what to install.

### Step 4 — Report
Tell the user, in this order:
1. That all three recorder hooks are active (native plugin hooks, unless `--legacy-hook` was
   used — then confirm the settings.json patch registered all three) and the **self-test passed**.
2. What was auto-fixed (`[FIXED]` lines), if anything — including the guide-rendering deps.
3. Any `[OPTIONAL]` line — mention once, in passing; it does not mean setup is incomplete.
4. Any remaining `[ACTION]` steps — only if present; otherwise say none are needed.
5. If `--legacy-hook` was used, tell the user to **restart Claude Code / start a new session**
   so it reloads `settings.json`. Otherwise no restart is needed — the plugin hooks are already
   live. Every prompt is logged to the journal dir, with an `assets-used` block appended once the
   turn finishes if it invoked any trackable skills/subagents/tools; `/analyse` runs the review
   pipeline.

## Constraints
- ALWAYS run the OS-appropriate script rather than editing settings.json by hand — the script
  is idempotent, removes stale recorder hooks, and backs up invalid JSON.
- NEVER hardcode a clone path or a user's directory; the scripts resolve everything relative
  to themselves or the user's home.
- NEVER leave the user guessing: if an `[ACTION]` remains, give the exact command or edit.
- ONLY require user intervention when the script reports `[ACTION]`; auto-fixable issues are
  the script's job.
- ONLY pass `--legacy-hook`/`-LegacyHook` (or `--project`/`--settings`) when the user is
  explicitly running this repo outside the plugin system.
