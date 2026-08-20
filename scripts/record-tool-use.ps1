# ai-gen — Claude Code PostToolUse hook: buffers asset invocations (Skill/Task/file-touching
# tools/MCP tool calls) for the current turn, keyed by session_id, so record-turn-end.ps1 (the
# Stop hook) can attach a summary to the journal entry record-prompt.ps1 wrote for this turn's
# prompt. hooks/hooks.json scopes this hook to
# Skill|Task|Read|Edit|Write|NotebookEdit|mcp__.* via its matcher, so it only runs for tool
# calls worth recording. Best-effort and silent: never blocks a tool call, exits 0 on any error.
$ErrorActionPreference = 'Stop'

$raw = [Console]::In.ReadToEnd()
try { $data = $raw | ConvertFrom-Json } catch { exit 0 }

$sessionId = [string]$data.session_id
if ([string]::IsNullOrWhiteSpace($sessionId)) { exit 0 }

$toolName = [string]$data.tool_name
if ([string]::IsNullOrWhiteSpace($toolName)) { exit 0 }

try {
    $bufferDir = Join-Path ([System.IO.Path]::GetTempPath()) 'prompt-journal-turn'
    New-Item -ItemType Directory -Force -Path $bufferDir | Out-Null
} catch { exit 0 }
$toolsFile = Join-Path $bufferDir "$sessionId.tools.jsonl"

# Resolve a candidate relative path against the target repo (CLAUDE_PROJECT_DIR, set by Claude
# Code for hooks) — returns it only if the file actually exists; empty otherwise ("unresolved").
function Resolve-AssetPath([string]$rel) {
    $base = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { (Get-Location).Path }
    $candidate = Join-Path $base $rel
    if (Test-Path $candidate -PathType Leaf) { return $candidate }
    return ''
}

function Write-BufferLine([string]$kind, [string]$name, [string]$path) {
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    try {
        $line = [pscustomobject]@{ kind = $kind; name = $name; path = $path } | ConvertTo-Json -Compress
        Add-Content -Path $toolsFile -Value $line -Encoding utf8
    } catch { }
}

switch ($toolName) {
    'Skill' {
        $name = [string]$data.tool_input.skill
        $path = Resolve-AssetPath ".claude/skills/$name/SKILL.md"
        if (-not $path) { $path = Resolve-AssetPath "skills/$name/SKILL.md" }
        Write-BufferLine 'skill' $name $path
    }
    'Task' {
        $name = [string]$data.tool_input.subagent_type
        $path = Resolve-AssetPath ".claude/agents/$name.md"
        if (-not $path) { $path = Resolve-AssetPath "agents/$name.md" }
        Write-BufferLine 'subagent' $name $path
    }
    { $_ -in 'Read', 'Edit', 'Write', 'NotebookEdit' } {
        $path = [string]$data.tool_input.file_path
        Write-BufferLine 'tool' $toolName $path
    }
    default {
        if ($toolName -like 'mcp__*') {
            # No file-path concept for most MCP calls; record the full tool name (e.g.
            # mcp__github__create_pull_request) as the name — that's the useful identifier here.
            Write-BufferLine 'mcp' $toolName ''
        }
        # else: hooks.json's matcher already restricts events to the cases above
    }
}

exit 0
