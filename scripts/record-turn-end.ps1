# ai-gen — Claude Code Stop hook: flushes this turn's buffered asset invocations (written by
# record-tool-use.ps1) into an "assets-used" block appended to the journal entry that
# record-prompt.ps1 wrote for the prompt that started this turn. Best-effort and silent: never
# blocks the turn, and writes nothing if there's no matching prompt entry (e.g. a skipped
# <task-notification> turn, or a turn that used no trackable tools/assets).
$ErrorActionPreference = 'Stop'

$raw = [Console]::In.ReadToEnd()
try { $data = $raw | ConvertFrom-Json } catch { exit 0 }

$sessionId = [string]$data.session_id
if ([string]::IsNullOrWhiteSpace($sessionId)) { exit 0 }

$bufferDir = Join-Path ([System.IO.Path]::GetTempPath()) 'prompt-journal-turn'
$marker    = Join-Path $bufferDir "$sessionId.journal"
$toolsFile = Join-Path $bufferDir "$sessionId.tools.jsonl"

function Remove-Buffer {
    Remove-Item -Path $marker -ErrorAction SilentlyContinue
    Remove-Item -Path $toolsFile -ErrorAction SilentlyContinue
}

# No prompt was recorded this turn — discard any buffered tool calls rather than misattribute
# them to whatever entry happens to be last in the journal file.
if (-not (Test-Path $marker -PathType Leaf)) { Remove-Buffer; exit 0 }
if (-not (Test-Path $toolsFile -PathType Leaf) -or (Get-Item $toolsFile).Length -eq 0) { Remove-Buffer; exit 0 }

$journalFile = (Get-Content -Raw -LiteralPath $marker).Trim()
if ([string]::IsNullOrWhiteSpace($journalFile) -or -not (Test-Path $journalFile -PathType Leaf)) { Remove-Buffer; exit 0 }

# Dedupe (kind,name,path) triples, preserve first-seen order, format as one line each:
#   <kind>: <name> -> <path-or-(unresolved)>
$seen = New-Object System.Collections.Generic.HashSet[string]
$lines = @()
foreach ($raw in Get-Content -LiteralPath $toolsFile) {
    if ([string]::IsNullOrWhiteSpace($raw)) { continue }
    try { $d = $raw | ConvertFrom-Json } catch { continue }
    $key = "$($d.kind)|$($d.name)|$($d.path)"
    if ($seen.Contains($key)) { continue }
    [void]$seen.Add($key)
    $path = if ($d.path) { $d.path } else { '(unresolved)' }
    $lines += "$($d.kind): $($d.name) -> $path"
}

if ($lines.Count -gt 0) {
    $block = @('----- assets-used -----') + $lines + @('----- end-assets-used -----')
    Add-Content -Path $journalFile -Value $block -Encoding utf8
}

Remove-Buffer
exit 0
