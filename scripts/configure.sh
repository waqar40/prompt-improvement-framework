#!/usr/bin/env bash
# ai-gen — one-step configurator/repair for the prompt-journal recorder (macOS / Linux).
#
# As an installed plugin, the UserPromptSubmit recorder hook is wired automatically by
# hooks/hooks.json — no settings.json patch needed. This script's default job is just to make
# sure a fresh install actually works: create the journal/outcomes dirs, self-test the recorder
# directly, and best-effort install the optional PDF/Word guide-rendering deps.
#
# The old behaviour — patching a settings.json UserPromptSubmit hook by hand — is still available
# for standalone/non-plugin use (e.g. developing on this repo directly) via --legacy-hook,
# --project, or --settings (any of which imply legacy mode).
#
#   bash scripts/configure.sh                         # plugin mode: dirs + self-test + deps only
#   bash scripts/configure.sh --legacy-hook            # also patch the global settings.json hook
#   bash scripts/configure.sh --project                # legacy hook, scoped to this repo's .claude/settings.json
#   bash scripts/configure.sh --journal <path>          # keep the journal somewhere else
#
set -euo pipefail

# --- Resolve locations (never hardcode a clone path — derive from this script) ----------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RECORD_SCRIPT="$SCRIPT_DIR/record-prompt.sh"
# Default lives in the user's home, not beside this script — as an installed plugin this script
# runs from Claude Code's managed plugin cache, which is not a stable place for personal data.
DEFAULT_JOURNAL="$HOME/.claude/prompt-journal/prompts"

OK=(); FIXED=(); ACTIONS=(); OPTIONAL=()
note_ok()       { OK+=("$1"); }
note_fixed()    { FIXED+=("$1"); }
note_action()   { ACTIONS+=("$1"); }
note_optional() { OPTIONAL+=("$1"); }

# --- Arg parsing ------------------------------------------------------------------------------
PROJECT=0; SETTINGS_PATH=""; JOURNAL_DIR=""; EXPLICIT_JOURNAL=0; LEGACY_HOOK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --legacy-hook) LEGACY_HOOK=1 ;;
    --project) PROJECT=1; LEGACY_HOOK=1 ;;
    --settings) SETTINGS_PATH="${2:-}"; LEGACY_HOOK=1; shift ;;
    --journal) JOURNAL_DIR="${2:-}"; EXPLICIT_JOURNAL=1; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
[ "$EXPLICIT_JOURNAL" -eq 1 ] || JOURNAL_DIR="$DEFAULT_JOURNAL"

# --- Preconditions ----------------------------------------------------------------------------
if [ ! -f "$RECORD_SCRIPT" ]; then
  echo "[ACTION] Recorder not found at $RECORD_SCRIPT — is this the prompt-journal clone? Re-clone the repo." >&2
  exit 2
fi

# The recorder parses hook JSON with jq or python3 — one must be present.
if command -v jq >/dev/null 2>&1;        then note_ok "jq present (recorder JSON parsing)"
elif command -v python3 >/dev/null 2>&1; then note_ok "python3 present (recorder JSON parsing)"
else note_action "Install jq OR python3 — the recorder needs one to parse the hook payload."
fi

# --- Auto-fix: journal (prompts) dir + executable bit -----------------------------------------
if [ ! -d "$JOURNAL_DIR" ]; then mkdir -p "$JOURNAL_DIR"; note_fixed "Created journal (prompts) directory: $JOURNAL_DIR"
else note_ok "Journal (prompts) directory present: $JOURNAL_DIR"; fi

# Outputs live OUTSIDE the repo too: default ~/.claude/prompt-journal/prompts-review-outcomes
# (override at analyse time with PROMPT_OUTCOMES_DIR). Holds scores/ guides/ suggestions/ reviews/.
OUTCOMES_DIR="${PROMPT_OUTCOMES_DIR:-$HOME/.claude/prompt-journal/prompts-review-outcomes}"
made_outcomes=0
for sub in scores guides suggestions reviews; do
  [ -d "$OUTCOMES_DIR/$sub" ] || { mkdir -p "$OUTCOMES_DIR/$sub"; made_outcomes=1; }
done
if [ "$made_outcomes" -eq 1 ]; then note_fixed "Created outcomes directory (scores/guides/suggestions/reviews): $OUTCOMES_DIR"
else note_ok "Outcomes directory present: $OUTCOMES_DIR"; fi

if [ ! -x "$RECORD_SCRIPT" ]; then chmod +x "$RECORD_SCRIPT"; note_fixed "Made recorder executable (chmod +x)"; fi

# --- Hook registration --------------------------------------------------------------------------
MERGE_RC=0
if [ "$LEGACY_HOOK" -eq 0 ]; then
  note_ok "Native plugin hook active (hooks/hooks.json) — no settings.json patch needed. Pass --legacy-hook if you're running this repo standalone, not as an installed plugin."
else
  # --- Resolve which settings.json to patch -----------------------------------------------------
  if [ -z "$SETTINGS_PATH" ]; then
    if [ "$PROJECT" -eq 1 ]; then
      SETTINGS_PATH="$REPO_ROOT/.claude/settings.json"
    else
      CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
      SETTINGS_PATH="$CLAUDE_HOME/settings.json"
    fi
  fi
  mkdir -p "$(dirname "$SETTINGS_PATH")"

  # Bake the journal path into the UserPromptSubmit hook only when the user relocated it;
  # otherwise let the recorder use its own default so the command stays path-derived and portable.
  if [ "$EXPLICIT_JOURNAL" -eq 1 ]; then
    PROMPT_HOOK_COMMAND="bash \"$RECORD_SCRIPT\" \"$JOURNAL_DIR\""
  else
    PROMPT_HOOK_COMMAND="bash \"$RECORD_SCRIPT\""
  fi
  TOOLUSE_HOOK_COMMAND="bash \"$SCRIPT_DIR/record-tool-use.sh\""
  TURNEND_HOOK_COMMAND="bash \"$SCRIPT_DIR/record-turn-end.sh\""

  # --- Merge all three recorder hooks into settings.json (python3 preferred, jq fallback) -------
  # Registers UserPromptSubmit (records the prompt), PostToolUse (buffers asset invocations —
  # matcher scopes it to Skill|Task|Read|Edit|Write|NotebookEdit|mcp__.* only), and Stop (flushes the
  # buffer into that prompt's assets-used block) — the full asset-use capture pipeline that
  # hooks/hooks.json wires automatically for a plugin install.
  merge_with_python3() {
    SETTINGS_PATH="$SETTINGS_PATH" \
    PROMPT_CMD="$PROMPT_HOOK_COMMAND" TOOLUSE_CMD="$TOOLUSE_HOOK_COMMAND" TURNEND_CMD="$TURNEND_HOOK_COMMAND" \
    python3 - <<'PY'
import json, os, sys
path = os.environ["SETTINGS_PATH"]
data = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        raw = f.read().strip()
    if raw:
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            bak = path + ".bak"
            os.replace(path, bak)  # move the corrupt file aside so we don't clobber it silently
            print("INVALID_JSON " + bak)
            sys.exit(3)

def is_recorder(group, needles):
    for h in group.get("hooks", []) if isinstance(group, dict) else []:
        c = h.get("command", "")
        if any(n in c for n in needles):
            return True
    return False

def replace_event(hooks, event, needles, new_group):
    existing = hooks.get(event, []) or []
    removed = [g for g in existing if is_recorder(g, needles)]
    kept    = [g for g in existing if not is_recorder(g, needles)]
    kept.append(new_group)
    hooks[event] = kept
    return len(removed)

hooks = data.setdefault("hooks", {})
removed_total = 0
removed_total += replace_event(hooks, "UserPromptSubmit", ["record-prompt", "log-prompt"],
    {"hooks": [{"type": "command", "command": os.environ["PROMPT_CMD"], "timeout": 15}]})
removed_total += replace_event(hooks, "PostToolUse", ["record-tool-use"],
    {"matcher": "Skill|Task|Read|Edit|Write|NotebookEdit|mcp__.*",
     "hooks": [{"type": "command", "command": os.environ["TOOLUSE_CMD"], "timeout": 10}]})
removed_total += replace_event(hooks, "Stop", ["record-turn-end"],
    {"hooks": [{"type": "command", "command": os.environ["TURNEND_CMD"], "timeout": 10}]})

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("REMOVED " + str(removed_total))
PY
  }

  merge_with_jq() {
    local tmp; tmp="$(mktemp)"
    [ -s "$SETTINGS_PATH" ] || echo '{}' > "$SETTINGS_PATH"
    # Validate JSON first.
    if ! jq empty "$SETTINGS_PATH" >/dev/null 2>&1; then
      mv "$SETTINGS_PATH" "$SETTINGS_PATH.bak"
      echo "INVALID_JSON $SETTINGS_PATH.bak"; return 3
    fi
    local before_prompt before_tool before_stop
    before_prompt="$(jq '[.hooks.UserPromptSubmit // [] | .[] | select([.hooks[].command] | any(test("record-prompt|log-prompt")))] | length' "$SETTINGS_PATH")"
    before_tool="$(jq   '[.hooks.PostToolUse // []     | .[] | select([.hooks[].command] | any(test("record-tool-use")))] | length' "$SETTINGS_PATH")"
    before_stop="$(jq   '[.hooks.Stop // []            | .[] | select([.hooks[].command] | any(test("record-turn-end")))] | length' "$SETTINGS_PATH")"
    jq --arg pcmd "$PROMPT_HOOK_COMMAND" --arg tcmd "$TOOLUSE_HOOK_COMMAND" --arg scmd "$TURNEND_HOOK_COMMAND" '
      .hooks = (.hooks // {})
      | .hooks.UserPromptSubmit =
          (((.hooks.UserPromptSubmit // [])
            | map(select([.hooks[].command] | any(test("record-prompt|log-prompt")) | not)))
           + [{hooks: [{type: "command", command: $pcmd, timeout: 15}]}])
      | .hooks.PostToolUse =
          (((.hooks.PostToolUse // [])
            | map(select([.hooks[].command] | any(test("record-tool-use")) | not)))
           + [{matcher: "Skill|Task|Read|Edit|Write|NotebookEdit|mcp__.*",
               hooks: [{type: "command", command: $tcmd, timeout: 10}]}])
      | .hooks.Stop =
          (((.hooks.Stop // [])
            | map(select([.hooks[].command] | any(test("record-turn-end")) | not)))
           + [{hooks: [{type: "command", command: $scmd, timeout: 10}]}])
    ' "$SETTINGS_PATH" > "$tmp" && mv "$tmp" "$SETTINGS_PATH"
    echo "REMOVED $(( ${before_prompt:-0} + ${before_tool:-0} + ${before_stop:-0} ))"
  }

  MERGE_OUT=""
  if command -v python3 >/dev/null 2>&1; then MERGE_OUT="$(merge_with_python3)" || MERGE_RC=$?
  elif command -v jq >/dev/null 2>&1;    then MERGE_OUT="$(merge_with_jq)"     || MERGE_RC=$?
  else
    note_action "Cannot edit settings.json automatically (need python3 or jq). Add these hooks by hand to $SETTINGS_PATH: UserPromptSubmit -> {\"type\":\"command\",\"command\":\"$PROMPT_HOOK_COMMAND\",\"timeout\":15}; PostToolUse (matcher \"Skill|Task|Read|Edit|Write|NotebookEdit|mcp__.*\") -> {\"type\":\"command\",\"command\":\"$TOOLUSE_HOOK_COMMAND\",\"timeout\":10}; Stop -> {\"type\":\"command\",\"command\":\"$TURNEND_HOOK_COMMAND\",\"timeout\":10}."
    MERGE_RC=99
  fi

  if [ "$MERGE_RC" -eq 3 ]; then
    note_action "settings.json was not valid JSON; moved aside to ${MERGE_OUT#INVALID_JSON }. Fix or delete the backup, then re-run /configure."
  elif [ "$MERGE_RC" -eq 0 ]; then
    removed_n="${MERGE_OUT#REMOVED }"
    if [ "${removed_n:-0}" -gt 0 ] 2>/dev/null; then note_fixed "Replaced $removed_n stale prompt-journal hook(s) with this clone's recorders"
    else note_ok "Registered UserPromptSubmit + PostToolUse + Stop hooks -> $SCRIPT_DIR"; fi
    note_ok "Wrote hooks into $SETTINGS_PATH"
  fi
fi

# --- Self-test: run the recorder against a throwaway journal dir -------------------------------
# Runs regardless of hook mode — this proves the script itself works, independent of how it's wired.
SELFTEST_OK=0
if [ "$MERGE_RC" -eq 0 ] && { command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; }; then
  TMP="$(mktemp -d)"
  MARKER="[configure self-test] recorder OK"
  if printf '{"prompt":"%s","cwd":"%s"}' "$MARKER" "$REPO_ROOT" \
       | PROMPT_JOURNAL_DIR="$TMP" bash "$RECORD_SCRIPT" >/dev/null 2>&1 \
       && grep -rqF "$MARKER" "$TMP" 2>/dev/null; then
    SELFTEST_OK=1; note_ok "Self-test passed — recorder writes a log entry"
  else
    note_action "Self-test did not produce a log entry. Debug with: echo '{\"prompt\":\"x\"}' | bash \"$RECORD_SCRIPT\""
  fi
  rm -rf "$TMP"
fi

# --- Optional: guide-rendering deps (PDF/Word views of the per-user guide) --------------------
# Not required for recording or scoring prompts — only /analyse's PDF/Word render step needs
# these. Best-effort: install the pinned versions (scripts/requirements.txt) so plain `python3`
# renders correctly (reportlab must stay <4.2 to work on Python 3.8's hashlib); never block
# configuration on this, and never fail the run because of it.
REQS="$SCRIPT_DIR/requirements.txt"
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import reportlab, docx" >/dev/null 2>&1; then
    note_ok "Guide PDF/Word deps present (reportlab, python-docx)"
  elif python3 -m pip install --quiet -r "$REQS" >/dev/null 2>&1 && python3 -c "import reportlab, docx" >/dev/null 2>&1; then
    note_fixed "Installed pinned guide-rendering deps (pip install -r $REQS)"
  else
    note_optional "PDF/Word guide views need: python3 -m pip install -r $REQS (Markdown view always works without them)"
  fi
else
  note_optional "python3 not found — skipping guide PDF/Word deps (Markdown view still works without them)"
fi

# --- Report -----------------------------------------------------------------------------------
echo ""
echo "prompt-journal recorder — configuration summary"
for m in "${OK[@]:-}";       do [ -n "$m" ] && echo "[OK]       $m"; done
for m in "${FIXED[@]:-}";    do [ -n "$m" ] && echo "[FIXED]    $m"; done
for m in "${OPTIONAL[@]:-}"; do [ -n "$m" ] && echo "[OPTIONAL] $m"; done
for m in "${ACTIONS[@]:-}";  do [ -n "$m" ] && echo "[ACTION]   $m"; done
echo ""
if [ "${#ACTIONS[@]}" -eq 0 ] && [ "$SELFTEST_OK" -eq 1 ]; then
  echo "Done."
  [ "$LEGACY_HOOK" -eq 1 ] && echo "Restart Claude Code (or start a new session) so it reloads settings.json."
  echo "  Prompts (input)  -> $JOURNAL_DIR"
  echo "  Review outputs   -> $OUTCOMES_DIR   (scores/ guides/ suggestions/ reviews/)"
  exit 0
else
  echo "Configuration finished with actions required — see [ACTION] lines above."
  exit 1
fi
