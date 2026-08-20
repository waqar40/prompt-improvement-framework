#!/usr/bin/env bash
# ai-gen — Claude Code Stop hook: flushes this turn's buffered asset invocations (written by
# record-tool-use.sh) into an "assets-used" block appended to the journal entry that
# record-prompt.sh wrote for the prompt that started this turn. Best-effort and silent: never
# blocks the turn, and writes nothing if there's no matching prompt entry (e.g. a skipped
# <task-notification> turn, or a turn that used no trackable tools/assets) — see
# record-prompt.sh for how the marker this depends on gets written.
set -uo pipefail

raw="$(cat)"

read_field() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$raw" | jq -r --arg k "$1" '.[$k] // empty'
  else
    printf '%s' "$raw" | python3 -c 'import sys,json;d=json.load(sys.stdin);v=d.get(sys.argv[1]);print(v if isinstance(v,str) else "")' "$1" 2>/dev/null || true
  fi
}

session_id="$(read_field session_id)"
[ -z "$session_id" ] && exit 0

BUFFER_DIR="${TMPDIR:-/tmp}/prompt-journal-turn"
MARKER="$BUFFER_DIR/$session_id.journal"
TOOLS_FILE="$BUFFER_DIR/$session_id.tools.jsonl"

cleanup() { rm -f "$MARKER" "$TOOLS_FILE" 2>/dev/null || true; }

# No prompt was recorded this turn (task-notification skip, empty prompt, or the marker was
# never written) — discard any buffered tool calls rather than misattribute them to whatever
# entry happens to be last in the journal file.
[ -f "$MARKER" ] || { cleanup; exit 0; }
[ -s "$TOOLS_FILE" ] || { cleanup; exit 0; }

journal_file="$(cat "$MARKER" 2>/dev/null || true)"
[ -n "$journal_file" ] && [ -f "$journal_file" ] || { cleanup; exit 0; }

# Dedupe (kind,name,path) triples and format as one line each:
#   <kind>: <name> -> <path-or-(unresolved)>
block="$(
  if command -v jq >/dev/null 2>&1; then
    jq -rs 'unique_by([.kind,.name,.path]) | .[] | "\(.kind): \(.name) -> \(if .path == "" then "(unresolved)" else .path end)"' "$TOOLS_FILE" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
seen = []
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except json.JSONDecodeError:
        continue
    key = (d.get("kind", ""), d.get("name", ""), d.get("path", ""))
    if key in seen:
        continue
    seen.append(key)
    kind, name, path = key
    print(f"{kind}: {name} -> {path or \"(unresolved)\"}")
' "$TOOLS_FILE" 2>/dev/null
  fi
)"

if [ -n "$block" ]; then
  {
    printf -- '----- assets-used -----\n'
    printf '%s\n' "$block"
    printf -- '----- end-assets-used -----\n'
  } >> "$journal_file"
fi

cleanup
exit 0
