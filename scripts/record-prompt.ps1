# ai-gen — Claude Code UserPromptSubmit hook: append each submitted prompt to a per-branch journal log.
# Reads the hook JSON from stdin, resolves the current git branch, and appends a timestamped entry.
param([string]$JournalDir)   # optional explicit journal dir (highest precedence); set by /configure --journal
$ErrorActionPreference = 'Stop'

$raw = [Console]::In.ReadToEnd()
try { $data = $raw | ConvertFrom-Json } catch { exit 0 }   # never block the prompt on a bad payload

$promptText = [string]$data.prompt
if ([string]::IsNullOrWhiteSpace($promptText)) { exit 0 }

# Skip harness machine-output turns (e.g. background <task-notification> completions). They are not
# authored prompts and would pollute the journal + score store. Exit 0 so the prompt is never blocked.
if ($promptText.TrimStart() -match '^<task-notification\b') { exit 0 }

$cwd = if ($data.cwd) { [string]$data.cwd } else { (Get-Location).Path }
# Journal dir precedence: -JournalDir arg > $env:PROMPT_JOURNAL_DIR > default
# ~/.claude/prompt-journal/prompts. The default lives in the user's home, not beside this
# script, because as an installed plugin this script runs from Claude Code's managed plugin
# cache — a location that can be rewritten or relocated on update/reinstall and is not meant
# to hold personal data.
$journal = if ($JournalDir) { $JournalDir }
           elseif ($env:PROMPT_JOURNAL_DIR) { $env:PROMPT_JOURNAL_DIR }
           else { Join-Path $HOME '.claude\prompt-journal\prompts' }

# Identifier resolution (what the log file and the entry header are keyed on):
#   1. current git branch                      -> "<branch>"
#   2. else the session name (env or payload)  -> "session/<name>"
#   3. else the repo root folder (or cwd) name -> "repo/<name>"
$branch = try { (& git -C $cwd symbolic-ref --quiet --short HEAD 2>$null) } catch { $null }
if ($branch) { $branch = $branch.Trim() }

# Repo root of the cwd (one git call, reused below) — used for the identifier fallback AND for
# the project/root header fields that let analysis filter by project and the asset builder
# locate the real repo on disk.
$top = try { (& git -C $cwd rev-parse --show-toplevel 2>$null) } catch { $null }
if ($top) { $top = $top.Trim() }

if ($branch -and $branch -ne 'HEAD') {
    $identifier = $branch
} elseif ($env:CLAUDE_SESSION_NAME) {
    $identifier = "session/$($env:CLAUDE_SESSION_NAME)"
} elseif ($data.session_name) {
    $identifier = "session/$([string]$data.session_name)"
} else {
    $folder = if ($top) { Split-Path $top -Leaf } else { Split-Path $cwd -Leaf }
    $identifier = "repo/$folder"
}

$slug = ($identifier -replace '/', '-') -replace '[^A-Za-z0-9._-]', '-'
$slug = $slug.Trim('-')

# Project = repo folder name (sanitized, no spaces); root = the repo's absolute path (or cwd).
$projectRoot = if ($top) { $top } else { $cwd }
$project = (Split-Path $projectRoot -Leaf) -replace '[^A-Za-z0-9._-]', '-'

if (-not (Test-Path $journal)) { New-Item -ItemType Directory -Force -Path $journal | Out-Null }

$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$entryFile = Join-Path $journal "$slug.txt"
# 'root=' is LAST so a path containing spaces is captured cleanly by the parser (branch/project are space-free).
$entry = "===== [$ts] branch=$identifier project=$project root=$projectRoot =====`n$promptText`n`n`n"
Add-Content -Path $entryFile -Value $entry -NoNewline -Encoding utf8

# Drop a marker naming the file we just wrote to, keyed by session_id, so record-turn-end.ps1
# (the Stop hook) knows where to attach this turn's "assets-used" block once the turn finishes.
# Best-effort only — a missing/unwritable marker just means that block gets silently skipped.
$sessionId = [string]$data.session_id
if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
    try {
        $bufferDir = Join-Path ([System.IO.Path]::GetTempPath()) 'prompt-journal-turn'
        New-Item -ItemType Directory -Force -Path $bufferDir | Out-Null
        Set-Content -Path (Join-Path $bufferDir "$sessionId.journal") -Value $entryFile -NoNewline -Encoding utf8
    } catch { }   # never let marker bookkeeping fail the recorder itself
}
exit 0
