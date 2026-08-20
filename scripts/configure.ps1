# ai-gen — one-step configurator/repair for the prompt-journal recorder (Windows / PowerShell).
#
# As an installed plugin, the UserPromptSubmit recorder hook is wired automatically by
# hooks/hooks.json — no settings.json patch needed. This script's default job is just to make
# sure a fresh install actually works: create the journal/outcomes dirs, self-test the recorder
# directly, and best-effort install the optional PDF/Word guide-rendering deps.
#
# The old behaviour — patching a settings.json UserPromptSubmit hook by hand — is still available
# for standalone/non-plugin use (e.g. developing on this repo directly) via -LegacyHook,
# -Project, or -SettingsPath (any of which imply legacy mode).
#
#   pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\configure.ps1                # plugin mode
#   pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\configure.ps1 -LegacyHook    # also patch settings.json
#
# Flags:
#   -LegacyHook     Also patch a settings.json UserPromptSubmit hook (implied by -Project/-SettingsPath).
#   -Project        Legacy hook, written to the repo's .claude\settings.json instead of the global one.
#   -SettingsPath   Explicit settings.json path to patch (implies legacy mode).
#   -JournalDir     Where prompts are logged. Default: ~\.claude\prompt-journal\prompts.
[CmdletBinding()]
param(
    [switch]$LegacyHook,
    [switch]$Project,
    [string]$SettingsPath,
    [string]$JournalDir
)
$ErrorActionPreference = 'Stop'
$explicitJournal = $PSBoundParameters.ContainsKey('JournalDir')
if ($Project -or $SettingsPath) { $LegacyHook = $true }

# --- Resolve locations (never hardcode a clone path — derive from this script) ----------------
$RepoRoot     = Split-Path $PSScriptRoot -Parent
$RecordScript = Join-Path $PSScriptRoot 'record-prompt.ps1'
# Default lives in the user's home, not beside this script — as an installed plugin this script
# runs from Claude Code's managed plugin cache, which is not a stable place for personal data.
if (-not $explicitJournal) { $JournalDir = Join-Path $HOME '.claude\prompt-journal\prompts' }
$JournalDir   = [System.IO.Path]::GetFullPath($JournalDir)

$ok = @(); $fixed = @(); $actions = @(); $optional = @()   # collected for the final report

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
# Default: ~\.claude\prompt-journal\prompts-review-outcomes. Override at analyse time with
# $env:PROMPT_OUTCOMES_DIR. Holds scores/ guides/ suggestions/ reviews/.
$OutcomesDir = if ($env:PROMPT_OUTCOMES_DIR) { $env:PROMPT_OUTCOMES_DIR }
               else { Join-Path $HOME '.claude\prompt-journal\prompts-review-outcomes' }
$OutcomesDir = [System.IO.Path]::GetFullPath($OutcomesDir)
$madeOutcomes = $false
foreach ($sub in 'scores','guides','suggestions','reviews') {
    $p = Join-Path $OutcomesDir $sub
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null; $madeOutcomes = $true }
}
if ($madeOutcomes) { $fixed += "Created outcomes directory (scores/guides/suggestions/reviews): $OutcomesDir" }
else { $ok += "Outcomes directory present: $OutcomesDir" }

# --- Hook registration --------------------------------------------------------------------------
if (-not $LegacyHook) {
    $ok += "Native plugin hook active (hooks/hooks.json) — no settings.json patch needed. Pass -LegacyHook if you're running this repo standalone, not as an installed plugin."
} else {

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
# True when a hook group's command contains any of the given needles (this or a stale one).
function Test-RecorderGroup($group, [string[]]$needles) {
    foreach ($h in @($group.hooks)) {
        if (-not $h.command) { continue }
        foreach ($n in $needles) { if ($h.command -match [regex]::Escape($n)) { return $true } }
    }
    return $false
}
# Merge a hook group into one event array, dropping any prior recorder groups first.
function Merge-Event($settingsObj, [string]$event, [string[]]$needles, $newGroup) {
    $existing = @()
    if ($settingsObj.hooks.PSObject.Properties[$event]) { $existing = @($settingsObj.hooks.$event) }
    $removedCount = @($existing | Where-Object { Test-RecorderGroup $_ $needles }).Count
    $kept = @($existing | Where-Object { -not (Test-RecorderGroup $_ $needles) })
    Set-Prop $settingsObj.hooks $event (@($kept) + $newGroup)
    return $removedCount
}

# --- Build the desired hook commands ------------------------------------------------------------
# Bake -JournalDir into the UserPromptSubmit hook only when the user relocated it; otherwise let
# the recorder use its own default so the command stays path-derived and portable.
$promptHookCommand = '{0} -NoProfile -ExecutionPolicy Bypass -File "{1}"' -f $exe, $RecordScript
if ($explicitJournal) { $promptHookCommand += ' -JournalDir "{0}"' -f $JournalDir }
$toolUseScript = Join-Path $PSScriptRoot 'record-tool-use.ps1'
$turnEndScript = Join-Path $PSScriptRoot 'record-turn-end.ps1'
$toolUseHookCommand = '{0} -NoProfile -ExecutionPolicy Bypass -File "{1}"' -f $exe, $toolUseScript
$turnEndHookCommand = '{0} -NoProfile -ExecutionPolicy Bypass -File "{1}"' -f $exe, $turnEndScript

# --- Merge all three recorder hooks idempotently -------------------------------------------------
# UserPromptSubmit (records the prompt), PostToolUse (buffers asset invocations — matcher scopes
# it to Skill|Task|Read|Edit|Write|NotebookEdit|mcp__.* only), and Stop (flushes the buffer into that
# prompt's assets-used block) — the full asset-use capture pipeline hooks/hooks.json wires
# automatically for a plugin install.
if (-not $settings.PSObject.Properties['hooks']) { Set-Prop $settings 'hooks' ([pscustomobject]@{}) }

$removedPrompt = Merge-Event $settings 'UserPromptSubmit' @('record-prompt', 'log-prompt') `
    ([pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = $promptHookCommand; timeout = 15 }) })
$removedTool = Merge-Event $settings 'PostToolUse' @('record-tool-use') `
    ([pscustomobject]@{ matcher = 'Skill|Task|Read|Edit|Write|NotebookEdit|mcp__.*'
                         hooks   = @([pscustomobject]@{ type = 'command'; command = $toolUseHookCommand; timeout = 10 }) })
$removedStop = Merge-Event $settings 'Stop' @('record-turn-end') `
    ([pscustomobject]@{ hooks = @([pscustomobject]@{ type = 'command'; command = $turnEndHookCommand; timeout = 10 }) })

$removedTotal = $removedPrompt + $removedTool + $removedStop
if ($removedTotal -gt 0) { $fixed += "Replaced $removedTotal stale prompt-journal hook(s) with this clone's recorders" }
else { $ok += "Registered UserPromptSubmit + PostToolUse + Stop hooks -> $PSScriptRoot" }

# --- Write settings back (readable, deep) -----------------------------------------------------
$settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $SettingsPath -Encoding utf8
$ok += "Wrote hooks into $SettingsPath"

}

# --- Self-test: run the recorder against a throwaway journal dir -------------------------------
# Runs regardless of hook mode — this proves the script itself works, independent of how it's wired.
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

# --- Optional: guide-rendering deps (PDF/Word views of the per-user guide) --------------------
# Not required for recording or scoring prompts — only /analyse's PDF/Word render step needs
# these. Best-effort: install the pinned versions (scripts\requirements.txt) so plain `python`
# renders correctly (reportlab must stay <4.2 to work on Python 3.8's hashlib); never block
# configuration on this, and never fail the run because of it.
$reqs = Join-Path $PSScriptRoot 'requirements.txt'
$pythonExe = $null
foreach ($cand in 'python', 'python3', 'py') {
    if (Get-Command $cand -ErrorAction SilentlyContinue) { $pythonExe = $cand; break }
}
if ($pythonExe) {
    & $pythonExe -c "import reportlab, docx" 2>$null
    $depsOk = ($LASTEXITCODE -eq 0)
    if ($depsOk) {
        $ok += "Guide PDF/Word deps present (reportlab, python-docx)"
    } else {
        & $pythonExe -m pip install --quiet -r $reqs 2>$null | Out-Null
        & $pythonExe -c "import reportlab, docx" 2>$null
        $depsOk = ($LASTEXITCODE -eq 0)
        if ($depsOk) { $fixed += "Installed pinned guide-rendering deps (pip install -r $reqs)" }
        else { $optional += "PDF/Word guide views need: $pythonExe -m pip install -r $reqs (Markdown view always works without them)" }
    }
} else {
    $optional += "No python found on PATH — skipping guide PDF/Word deps (Markdown view still works without them)"
}

# --- Report -----------------------------------------------------------------------------------
Write-Host ""
Write-Host "prompt-journal recorder — configuration summary" -ForegroundColor Cyan
foreach ($m in $ok)       { Say 'OK'       $m }
foreach ($m in $fixed)    { Say 'FIXED'    $m }
foreach ($m in $optional) { Say 'OPTIONAL' $m }
foreach ($m in $actions)  { Say 'ACTION'   $m }
Write-Host ""
if ($actions.Count -eq 0 -and $selfTestOk) {
    Write-Host "Done." -ForegroundColor Green
    if ($LegacyHook) { Write-Host "Restart Claude Code (or start a new session) so it reloads settings.json." -ForegroundColor Green }
    Write-Host "  Prompts (input)  -> $JournalDir"
    Write-Host "  Review outputs   -> $OutcomesDir   (scores/ guides/ suggestions/ reviews/)"
    exit 0
} else {
    Write-Host "Configuration finished with actions required — see [ACTION] lines above." -ForegroundColor Yellow
    exit 1
}
