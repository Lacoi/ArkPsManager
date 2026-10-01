#Requires -Version 7.0
<#
.SYNOPSIS
    Example: run multiple actions for multiple servers from an external script while
    the App.ps1 dashboard is open, without it auto-restarting servers mid-maintenance.

.DESCRIPTION
    App.ps1's dashboard auto-restarts any server that has been stopped longer than
    GlobalSettings.Process.RestartTime. If an external script (e.g. a scheduled task)
    stops several servers, updates them, then starts them back up, that window of
    "stopped" time can be long enough for the dashboard to jump in and start a server
    itself - racing with this script.

    To prevent that, the dashboard skips auto-restart entirely while a flag file named
    "AutoRestartPaused.flag" exists directly in the repo root (next to config.json).
    Create it before starting a batch of actions, and make sure it's removed afterwards
    (even on failure) with try/finally.

    Stop/Update/Start are each run for all Keys via actions/RunAction.ps1 (Sequential
    mode), the same proxy script the dashboard's bulk-action buttons use.

.EXAMPLE
    pwsh -File examples/BulkMaintenance.ps1 -Keys TheIsland,Ragnarok
#>
param(
    [Parameter(Mandatory)]
    [string[]]$Keys,

    [string]$ConfigJsonPath = (Join-Path (Get-Item $PSScriptRoot).Parent.FullName "config.json")
)

$repoRoot = (Get-Item $PSScriptRoot).Parent.FullName
$actionsFolder = Join-Path $repoRoot "actions"
$pauseFlagPath = Join-Path $repoRoot "AutoRestartPaused.flag"

# Create the flag so App.ps1 (if it's running) skips auto-restart until we're done
New-Item -Path $pauseFlagPath -ItemType File -Force | Out-Null
Write-Host "Auto-restart paused (created '$pauseFlagPath')."

try {
    $keysArg = $Keys -join ','
    $runActionPath = Join-Path $actionsFolder "RunAction.ps1"

    Write-Host "Stopping [$keysArg]..."
    & $runActionPath -ActionName Stop -Keys $keysArg -Mode Parallel -ConfigJsonPath $ConfigJsonPath

    Write-Host "Updating [$keysArg]..."
    & $runActionPath -ActionName Update -Keys $keysArg -Mode Sequential -ConfigJsonPath $ConfigJsonPath

    Write-Host "Starting [$keysArg]..."
    & $runActionPath -ActionName Start -Keys $keysArg -Mode Sequential -ConfigJsonPath $ConfigJsonPath
} finally {
    # Always remove the flag, even if a step above throws, so the dashboard resumes normal auto-restart
    Remove-Item -Path $pauseFlagPath -Force -ErrorAction SilentlyContinue
    Write-Host "Auto-restart resumed (removed '$pauseFlagPath')."
}
