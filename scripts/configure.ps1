# ai-gen — one-step configurator for the prompt-journal recorder hook (Windows / PowerShell).
# Wires a UserPromptSubmit hook into your Claude Code settings so every prompt in every repo
# is captured into a sibling 'prompts' dir beside THIS clone. Idempotent, self-healing, re-runnable.
#
#   pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\configure.ps1
#
# Flags:
#   -Project        Write the hook to the repo's .claude\settings.json instead of the global
#                   ~/.claude\settings.json (global is the default so all repos are captured).
#   -SettingsPath   Explicit path to the settings.json to patch (overrides -Project).
#   -JournalDir     Where prompts are logged. Default: a sibling 'prompts' folder next to the
#                   clone (<clone>\..\prompts). Pass this to keep the journal somewhere else.
[CmdletBinding()]
param(
    [switch]$Project,
    [string]$SettingsPath,
    [string]$JournalDir
)
$ErrorActionPreference = 'Stop'
$explicitJournal = $PSBoundParameters.ContainsKey('JournalDir')

# --- Resolve locations (never hardcode a clone path — derive from this script) ----------------
$RepoRoot     = Split-Path $PSScriptRoot -Parent
$RecordScript = Join-Path $PSScriptRoot 'record-prompt.ps1'
# Default journal = sibling 'prompts' beside the clone, so raw data stays out of the repo.
if (-not $explicitJournal) { $JournalDir = Join-Path (Split-Path $RepoRoot -Parent) 'prompts' }
$JournalDir   = [System.IO.Path]::GetFullPath($JournalDir)

$ok = @(); $fixed = @(); $actions = @()   # collected for the final report

function Say([string]$tag, [string]$msg) { Write-Host ("[{0}] {1}" -f $tag, $msg) }

# --- Preconditions ----------------------------------------------------------------------------
if (-not (Test-Path $RecordScript)) {
    Say 'ACTION' "Recorder not found at $RecordScript — is this the prompt-journal clone? Re-clone the repo."
    exit 2
}

# Pick a PowerShell executable for the hook command: prefer pwsh (7+), fall back to Windows PS.
$exe = $null
foreach ($cand in 'pwsh', 'powershell') {
    if (Get-Command $cand -ErrorAction SilentlyContinue) { $exe = $cand; break }
}
if (-not $exe) {
    Say 'ACTION' "No PowerShell executable found on PATH (pwsh or powershell). Install PowerShell 7."
    exit 2
}
$ok += "PowerShell executable for hook: $exe"

# --- Auto-fix: ensure the journal (prompts) dir exists ----------------------------------------
if (-not (Test-Path $JournalDir)) {
    New-Item -ItemType Directory -Force -Path $JournalDir | Out-Null
    $fixed += "Created journal (prompts) directory: $JournalDir"
} else {
    $ok += "Journal (prompts) directory present: $JournalDir"
}

# --- Auto-fix: ensure the outcomes dir exists (outputs live OUTSIDE the repo too) -------------
# Default: sibling 'prompts-review-outcomes' beside the clone. Override at analyse time with
# $env:PROMPT_OUTCOMES_DIR. Holds scores/ guides/ suggestions/ reviews/.
$OutcomesDir = if ($env:PROMPT_OUTCOMES_DIR) { $env:PROMPT_OUTCOMES_DIR }
               else { Join-Path (Split-Path $RepoRoot -Parent) 'prompts-review-outcomes' }
$OutcomesDir = [System.IO.Path]::GetFullPath($OutcomesDir)
$madeOutcomes = $false
foreach ($sub in 'scores','guides','suggestions','reviews') {
    $p = Join-Path $OutcomesDir $sub
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null; $madeOutcomes = $true }
}
if ($madeOutcomes) { $fixed += "Created outcomes directory (scores/guides/suggestions/reviews): $OutcomesDir" }
else { $ok += "Outcomes directory present: $OutcomesDir" }

# --- Resolve which settings.json to patch -----------------------------------------------------
if (-not $SettingsPath) {
    if ($Project) {
        $SettingsPath = Join-Path $RepoRoot '.claude\settings.json'
    } else {
        $claudeHome = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
        $SettingsPath = Join-Path $claudeHome 'settings.json'
    }
}
$settingsDir = Split-Path $SettingsPath -Parent
if (-not (Test-Path $settingsDir)) {
    New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null
    $fixed += "Created settings directory: $settingsDir"
}

# --- Load settings (tolerate missing / empty file) --------------------------------------------
$settings = $null
if (Test-Path $SettingsPath) {
    $rawJson = (Get-Content -Raw -LiteralPath $SettingsPath).Trim()
    if ($rawJson) {
        try { $settings = $rawJson | ConvertFrom-Json }
        catch {
            $backup = "$SettingsPath.bak-$(Get-Date -Format 'yyyyMMddHHmmss')"
            Copy-Item -LiteralPath $SettingsPath -Destination $backup
            Say 'ACTION' "settings.json is not valid JSON. Backed it up to $backup and cannot safely edit it. Fix the JSON, then re-run /configure."
            exit 2
        }
    }
}
if (-not $settings) { $settings = [pscustomobject]@{} }

# --- Helpers ----------------------------------------------------------------------------------
function Set-Prop($obj, [string]$name, $value) {
    if ($obj.PSObject.Properties[$name]) { $obj.$name = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force }
}
# True when a UserPromptSubmit group is one of our recorder hooks (this or a stale one).
function Test-RecorderGroup($group) {
    foreach ($h in @($group.hooks)) {
        if ($h.command -and ($h.command -match 'record-prompt' -or $h.command -match 'log-prompt')) { return $true }
    }
    return $false
}

# --- Build the desired hook command -----------------------------------------------------------
# Bake -JournalDir into the hook only when the user relocated it; otherwise let the recorder use
# its own sibling-'prompts' default so the hook command stays path-derived and portable.
$hookCommand = '{0} -NoProfile -ExecutionPolicy Bypass -File "{1}"' -f $exe, $RecordScript
if ($explicitJournal) { $hookCommand += ' -JournalDir "{0}"' -f $JournalDir }
$newGroup = [pscustomobject]@{
    hooks = @([pscustomobject]@{ type = 'command'; command = $hookCommand; timeout = 15 })
}

# --- Merge idempotently: drop any prior recorder groups, then append ours ----------------------
if (-not $settings.PSObject.Properties['hooks']) { Set-Prop $settings 'hooks' ([pscustomobject]@{}) }
$existing = @()
if ($settings.hooks.PSObject.Properties['UserPromptSubmit']) { $existing = @($settings.hooks.UserPromptSubmit) }

$removed = @($existing | Where-Object { Test-RecorderGroup $_ }).Count
$kept    = @($existing | Where-Object { -not (Test-RecorderGroup $_) })
$final   = @($kept) + $newGroup
Set-Prop $settings.hooks 'UserPromptSubmit' $final

if ($removed -gt 0) { $fixed += "Replaced $removed stale prompt-recorder hook(s) with this clone's recorder" }
else { $ok += "Registered UserPromptSubmit hook -> $RecordScript" }

# --- Write settings back (readable, deep) -----------------------------------------------------
$settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $SettingsPath -Encoding utf8
$ok += "Wrote hook into $SettingsPath"

# --- Self-test: run the recorder against a throwaway journal dir -------------------------------
$selfTestOk = $false
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("phook-selftest-" + [guid]::NewGuid().ToString('N'))
try {
    $prev = $env:PROMPT_JOURNAL_DIR
    $env:PROMPT_JOURNAL_DIR = $tmp
    $marker  = "[configure self-test] recorder OK"
    $payload = @{ prompt = $marker; cwd = $RepoRoot } | ConvertTo-Json -Compress
    $payload | & $exe -NoProfile -ExecutionPolicy Bypass -File $RecordScript | Out-Null
    $hit = @(Get-ChildItem -Path $tmp -Filter *.txt -ErrorAction SilentlyContinue |
             Where-Object { (Get-Content -Raw $_.FullName) -match [regex]::Escape($marker) })
    $selfTestOk = $hit.Count -gt 0
} catch {
    $selfTestOk = $false
} finally {
    if ($null -ne $prev) { $env:PROMPT_JOURNAL_DIR = $prev } else { Remove-Item Env:PROMPT_JOURNAL_DIR -ErrorAction SilentlyContinue }
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
if ($selfTestOk) { $ok += "Self-test passed — recorder writes a log entry" }
else { $actions += "Self-test did not produce a log entry. Run the recorder manually to see the error: echo '{}' | $exe -NoProfile -File `"$RecordScript`"" }

# --- Report -----------------------------------------------------------------------------------
Write-Host ""
Write-Host "prompt-journal recorder — configuration summary" -ForegroundColor Cyan
foreach ($m in $ok)      { Say 'OK'     $m }
foreach ($m in $fixed)   { Say 'FIXED'  $m }
foreach ($m in $actions) { Say 'ACTION' $m }
Write-Host ""
if ($actions.Count -eq 0 -and $selfTestOk) {
    Write-Host "Done. Restart Claude Code (or start a new session) so it reloads settings." -ForegroundColor Green
    Write-Host "  Prompts (input)  -> $JournalDir"
    Write-Host "  Review outputs   -> $OutcomesDir   (scores/ guides/ suggestions/ reviews/)"
    exit 0
} else {
    Write-Host "Configuration finished with actions required — see [ACTION] lines above." -ForegroundColor Yellow
    exit 1
}
