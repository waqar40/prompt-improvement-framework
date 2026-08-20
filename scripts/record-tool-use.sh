#!/usr/bin/env bash
# ai-gen — Claude Code PostToolUse hook: buffers asset invocations (Skill/Task/file-touching
# tools/MCP tool calls) for the current turn, keyed by session_id, so record-turn-end.sh (the
# Stop hook) can attach a summary to the journal entry record-prompt.sh wrote for this turn's
# prompt. hooks/hooks.json scopes this hook to Skill|Task|Read|Edit|Write|NotebookEdit|mcp__.*
# via its matcher, so it only runs for tool calls worth recording — never for the high-frequency
# ones (Bash, Grep, Glob, ...). Best-effort and silent: never blocks a tool call, exits 0 on any error.
set -uo pipefail

raw="$(cat)"

# Extract a top-level string field (prefer jq, fall back to python3).
read_field() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$raw" | jq -r --arg k "$1" '.[$k] // empty'
  else
    printf '%s' "$raw" | python3 -c 'import sys,json;d=json.load(sys.stdin);v=d.get(sys.argv[1]);print(v if isinstance(v,str) else "")' "$1" 2>/dev/null || true
  fi
}

# Extract a nested field: $1 = jq path (e.g. '.tool_input.file_path'), $2 = python get-expr on `d`.
read_nested() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$raw" | jq -r "$1 // empty" 2>/dev/null
  else
    printf '%s' "$raw" | python3 -c "
import sys, json
d = json.load(sys.stdin)
try:
    v = $2
except Exception:
    v = ''
print(v if isinstance(v, str) else '')
" 2>/dev/null || true
  fi
}

session_id="$(read_field session_id)"
[ -z "$session_id" ] && exit 0   # can't correlate to a turn without a session id — skip silently

tool_name="$(read_field tool_name)"
[ -z "$tool_name" ] && exit 0

BUFFER_DIR="${TMPDIR:-/tmp}/prompt-journal-turn"
mkdir -p "$BUFFER_DIR" 2>/dev/null || exit 0
TOOLS_FILE="$BUFFER_DIR/$session_id.tools.jsonl"

# Resolve a candidate relative path against the target repo (CLAUDE_PROJECT_DIR, set by Claude
# Code for hooks) — prints it only if the file actually exists; empty otherwise ("unresolved").
resolve_path() {
  local base="${CLAUDE_PROJECT_DIR:-$PWD}"
  [ -f "$base/$1" ] && printf '%s' "$base/$1"
}

write_line() {
  local kind="$1" name="$2" path="$3"
  [ -z "$name" ] && return 0
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg k "$kind" --arg n "$name" --arg p "$path" '{kind:$k,name:$n,path:$p}' >> "$TOOLS_FILE" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.dumps({"kind":sys.argv[1],"name":sys.argv[2],"path":sys.argv[3]}))' "$kind" "$name" "$path" >> "$TOOLS_FILE" 2>/dev/null
  else
    printf '{"kind":"%s","name":"%s","path":"%s"}\n' "${kind//\"/\\\"}" "${name//\"/\\\"}" "${path//\"/\\\"}" >> "$TOOLS_FILE" 2>/dev/null
  fi
  return 0
}

case "$tool_name" in
  Skill)
    name="$(read_nested '.tool_input.skill' "d.get('tool_input',{}).get('skill','')")"
    path="$(resolve_path ".claude/skills/$name/SKILL.md")"
    [ -z "$path" ] && path="$(resolve_path "skills/$name/SKILL.md")"
    write_line skill "$name" "$path"
    ;;
  Task)
    name="$(read_nested '.tool_input.subagent_type' "d.get('tool_input',{}).get('subagent_type','')")"
    path="$(resolve_path ".claude/agents/$name.md")"
    [ -z "$path" ] && path="$(resolve_path "agents/$name.md")"
    write_line subagent "$name" "$path"
    ;;
  Read|Edit|Write|NotebookEdit)
    path="$(read_nested '.tool_input.file_path' "d.get('tool_input',{}).get('file_path','')")"
    write_line tool "$tool_name" "$path"
    ;;
  mcp__*)
    # No file-path concept for most MCP calls; record the full tool name (e.g.
    # mcp__github__create_pull_request) as "name" — that's the useful identifier here.
    write_line mcp "$tool_name" ""
    ;;
  *) : ;;   # hooks.json's matcher already restricts events to the cases above; ignore anything else
esac

exit 0
