# ai-gen — Claude Code Stop hook: flushes this turn's buffered asset invocations (written by
# record-tool-use.ps1) and this turn's duration into an "assets-used" block appended to the
# journal entry that record-prompt.ps1 wrote for the prompt that started this turn. Best-effort
# and silent: never blocks the turn, and writes nothing if there's no matching prompt entry
# (e.g. a skipped <task-notification> turn, or no marker at all).
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

# No prompt was recorded this turn (no marker at all) — discard any buffered tool calls rather
# than misattribute them to whatever entry happens to be last in the journal file. Note: unlike
# before, we no longer bail out just because the tools file is empty — a tool-less turn can
# still carry a duration.
if (-not (Test-Path $marker -PathType Leaf)) { Remove-Buffer; exit 0 }

$markerLines = Get-Content -LiteralPath $marker
$journalFile = if ($markerLines.Count -ge 1) { $markerLines[0].Trim() } else { '' }
$startEpochRaw = if ($markerLines.Count -ge 2) { $markerLines[1].Trim() } else { '' }
if ([string]::IsNullOrWhiteSpace($journalFile) -or -not (Test-Path $journalFile -PathType Leaf)) { Remove-Buffer; exit 0 }

# Dedupe (kind,name,path) triples, preserve first-seen order, format as one line each:
#   <kind>: <name> -> <path-or-(unresolved)>
$lines = @()
if ((Test-Path $toolsFile -PathType Leaf) -and (Get-Item $toolsFile).Length -gt 0) {
    $seen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($raw in Get-Content -LiteralPath $toolsFile) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        try { $d = $raw | ConvertFrom-Json } catch { continue }
        $key = "$($d.kind)|$($d.name)|$($d.path)"
        if ($seen.Contains($key)) { continue }
        [void]$seen.Add($key)
        $path = if ($d.path) { $d.path } else { '(unresolved)' }
        $lines += "$($d.kind): $($d.name) -> $path"
    }
}

# Duration (best-effort — only if line 2 of the marker is a plain non-negative integer; a
# missing/corrupt start epoch just means no duration_s line, never a failure).
$durationLine = $null
$startEpoch = 0L
if ($startEpochRaw -match '^\d+$' -and [long]::TryParse($startEpochRaw, [ref]$startEpoch)) {
    $endEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $durationS = $endEpoch - $startEpoch
    if ($durationS -ge 0) { $durationLine = "duration_s: $durationS" }
}

if ($lines.Count -gt 0 -or $durationLine) {
    $block = @('----- assets-used -----')
    if ($durationLine) { $block += $durationLine }
    $block += $lines
    $block += '----- end-assets-used -----'
    Add-Content -Path $journalFile -Value $block -Encoding utf8
}

Remove-Buffer
exit 0
