#!/usr/bin/env bash
# ai-gen — Claude Code UserPromptSubmit hook: append each submitted prompt to a per-branch journal log.
# Reads the hook JSON from stdin, resolves the current git branch, and appends a timestamped entry.
set -euo pipefail

raw="$(cat)"

# Extract prompt + cwd from the hook JSON (prefer jq, fall back to python3).
read_field() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$raw" | jq -r --arg k "$1" '.[$k] // ""'
  else
    printf '%s' "$raw" | python3 -c 'import sys,json;print(json.load(sys.stdin).get(sys.argv[1],""))' "$1" 2>/dev/null || true
  fi
}

prompt="$(read_field prompt)"
[ -z "$prompt" ] && exit 0   # never block the prompt on an empty/bad payload

# Skip harness machine-output turns (e.g. background <task-notification> completions) — not authored
# prompts; they would pollute the journal + score store. exit 0 so the prompt is never blocked.
case "$(printf '%s' "$prompt" | sed 's/^[[:space:]]*//')" in
  '<task-notification'*) exit 0 ;;
esac

cwd="$(read_field cwd)"
[ -z "$cwd" ] && cwd="$PWD"
session_id="$(read_field session_id)"

# Journal dir precedence: $1 arg > PROMPT_JOURNAL_DIR > default ~/.claude/prompt-journal/prompts.
# The default lives in the user's home, not beside this script, because as an installed plugin
# this script runs from Claude Code's managed plugin cache — a location that can be rewritten or
# relocated on update/reinstall and is not meant to hold personal data.
# ($1 is set by /configure --journal; the hook payload always arrives on stdin, never as an arg.)
journal="${1:-${PROMPT_JOURNAL_DIR:-$HOME/.claude/prompt-journal/prompts}}"

# Identifier resolution (what the log file and the entry header are keyed on):
#   1. current git branch                      -> "<branch>"
#   2. else the session name (env or payload)  -> "session/<name>"
#   3. else the repo root folder (or cwd) name -> "repo/<name>"
branch="$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
# Repo root of the cwd (one git call, reused below) — used for the identifier fallback AND for
# the project/root header fields that let analysis filter by project and the asset builder
# locate the real repo on disk.
top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
  identifier="$branch"
elif [ -n "${CLAUDE_SESSION_NAME:-}" ]; then
  identifier="session/$CLAUDE_SESSION_NAME"
elif [ -n "$(read_field session_name)" ]; then
  identifier="session/$(read_field session_name)"
else
  folder="$(basename "${top:-$cwd}")"
  identifier="repo/$folder"
fi

slug="$(printf '%s' "$identifier" | tr '/' '-' | sed 's/[^A-Za-z0-9._-]/-/g; s/^-*//; s/-*$//')"

# Project = repo folder name (sanitized, no spaces); root = the repo's absolute path (or cwd).
project_root="${top:-$cwd}"
project="$(basename "$project_root" | sed 's/[^A-Za-z0-9._-]/-/g')"

mkdir -p "$journal"
ts="$(date '+%Y-%m-%d %H:%M:%S')"
entry_file="$journal/$slug.txt"
# 'root=' is LAST so a path containing spaces is captured cleanly by the parser (branch/project are space-free).
printf '===== [%s] branch=%s project=%s root=%s =====\n%s\n\n\n' "$ts" "$identifier" "$project" "$project_root" "$prompt" >> "$entry_file"

# Drop a marker naming the file we just wrote to, keyed by session_id, so record-turn-end.sh
# (the Stop hook) knows where to attach this turn's "assets-used" block once the turn finishes.
# Best-effort only — a missing/unwritable marker just means that block gets silently skipped.
if [ -n "$session_id" ]; then
  BUFFER_DIR="${TMPDIR:-/tmp}/prompt-journal-turn"
  mkdir -p "$BUFFER_DIR" 2>/dev/null && printf '%s' "$entry_file" > "$BUFFER_DIR/$session_id.journal" 2>/dev/null || true
fi
exit 0
