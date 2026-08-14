#!/usr/bin/env bash
# ai-gen — one-step configurator for the prompt-journal recorder hook (macOS / Linux).
# Wires a UserPromptSubmit hook into your Claude Code settings so every prompt in every repo
# is captured into a sibling 'prompts' dir beside THIS clone. Idempotent, self-healing, re-runnable.
#
#   bash scripts/configure.sh                    # global hook + default sibling 'prompts' dir
#   bash scripts/configure.sh --project          # patch this repo's .claude/settings.json instead
#   bash scripts/configure.sh --journal <path>   # keep the journal somewhere else
#
set -euo pipefail

# --- Resolve locations (never hardcode a clone path — derive from this script) ----------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RECORD_SCRIPT="$SCRIPT_DIR/record-prompt.sh"
DEFAULT_JOURNAL="$(dirname "$REPO_ROOT")/prompts"   # sibling 'prompts' beside the clone

OK=(); FIXED=(); ACTIONS=(); OPTIONAL=()
note_ok()       { OK+=("$1"); }
note_fixed()    { FIXED+=("$1"); }
note_action()   { ACTIONS+=("$1"); }
note_optional() { OPTIONAL+=("$1"); }

# --- Arg parsing ------------------------------------------------------------------------------
PROJECT=0; SETTINGS_PATH=""; JOURNAL_DIR=""; EXPLICIT_JOURNAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT=1 ;;
    --settings) SETTINGS_PATH="${2:-}"; shift ;;
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

# Outputs live OUTSIDE the repo too: a sibling 'prompts-review-outcomes' (override at analyse time
# with PROMPT_OUTCOMES_DIR). Holds scores/ guides/ suggestions/ reviews/.
OUTCOMES_DIR="${PROMPT_OUTCOMES_DIR:-$(dirname "$REPO_ROOT")/prompts-review-outcomes}"
made_outcomes=0
for sub in scores guides suggestions reviews; do
  [ -d "$OUTCOMES_DIR/$sub" ] || { mkdir -p "$OUTCOMES_DIR/$sub"; made_outcomes=1; }
done
if [ "$made_outcomes" -eq 1 ]; then note_fixed "Created outcomes directory (scores/guides/suggestions/reviews): $OUTCOMES_DIR"
else note_ok "Outcomes directory present: $OUTCOMES_DIR"; fi

if [ ! -x "$RECORD_SCRIPT" ]; then chmod +x "$RECORD_SCRIPT"; note_fixed "Made recorder executable (chmod +x)"; fi

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

# Bake the journal path into the hook only when the user relocated it; otherwise let the
# recorder use its own sibling-'prompts' default so the command stays path-derived and portable.
if [ "$EXPLICIT_JOURNAL" -eq 1 ]; then
  HOOK_COMMAND="bash \"$RECORD_SCRIPT\" \"$JOURNAL_DIR\""
else
  HOOK_COMMAND="bash \"$RECORD_SCRIPT\""
fi

# --- Merge the hook into settings.json (python3 preferred, jq fallback) -----------------------
merge_with_python3() {
  SETTINGS_PATH="$SETTINGS_PATH" HOOK_COMMAND="$HOOK_COMMAND" python3 - <<'PY'
import json, os, sys
path = os.environ["SETTINGS_PATH"]
cmd  = os.environ["HOOK_COMMAND"]
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
def is_recorder(group):
    for h in group.get("hooks", []) if isinstance(group, dict) else []:
        c = h.get("command", "")
        if "record-prompt" in c or "log-prompt" in c:
            return True
    return False
hooks = data.setdefault("hooks", {})
existing = hooks.get("UserPromptSubmit", []) or []
removed  = [g for g in existing if is_recorder(g)]
kept     = [g for g in existing if not is_recorder(g)]
kept.append({"hooks": [{"type": "command", "command": cmd, "timeout": 15}]})
hooks["UserPromptSubmit"] = kept
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print("REMOVED " + str(len(removed)))
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
  local before after
  before="$(jq '[.hooks.UserPromptSubmit // [] | .[] | select([.hooks[].command] | any(test("record-prompt|log-prompt")))] | length' "$SETTINGS_PATH")"
  jq --arg cmd "$HOOK_COMMAND" '
    .hooks = (.hooks // {})
    | .hooks.UserPromptSubmit =
        (((.hooks.UserPromptSubmit // [])
          | map(select([.hooks[].command] | any(test("record-prompt|log-prompt")) | not)))
         + [{hooks: [{type: "command", command: $cmd, timeout: 15}]}])
  ' "$SETTINGS_PATH" > "$tmp" && mv "$tmp" "$SETTINGS_PATH"
  echo "REMOVED ${before:-0}"
}

MERGE_OUT=""; MERGE_RC=0
if command -v python3 >/dev/null 2>&1; then MERGE_OUT="$(merge_with_python3)" || MERGE_RC=$?
elif command -v jq >/dev/null 2>&1;    then MERGE_OUT="$(merge_with_jq)"     || MERGE_RC=$?
else
  note_action "Cannot edit settings.json automatically (need python3 or jq). Add this hook by hand to $SETTINGS_PATH under .hooks.UserPromptSubmit: {\"hooks\":[{\"type\":\"command\",\"command\":\"$HOOK_COMMAND\",\"timeout\":15}]}"
  MERGE_RC=99
fi

if [ "$MERGE_RC" -eq 3 ]; then
  note_action "settings.json was not valid JSON; moved aside to ${MERGE_OUT#INVALID_JSON }. Fix or delete the backup, then re-run /configure."
elif [ "$MERGE_RC" -eq 0 ]; then
  removed_n="${MERGE_OUT#REMOVED }"
  if [ "${removed_n:-0}" -gt 0 ] 2>/dev/null; then note_fixed "Replaced $removed_n stale prompt-recorder hook(s) with this clone's recorder"
  else note_ok "Registered UserPromptSubmit hook -> $RECORD_SCRIPT"; fi
  note_ok "Wrote hook into $SETTINGS_PATH"
fi

# --- Self-test: run the recorder against a throwaway journal dir -------------------------------
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
  echo "Done. Restart Claude Code (or start a new session) so it reloads settings."
  echo "  Prompts (input)  -> $JOURNAL_DIR"
  echo "  Review outputs   -> $OUTCOMES_DIR   (scores/ guides/ suggestions/ reviews/)"
  exit 0
else
  echo "Configuration finished with actions required — see [ACTION] lines above."
  exit 1
fi
