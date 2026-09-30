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
    foreach ($key in $Keys) {
        Write-Host "=== Maintenance for '$key' ==="

        Write-Host "Stopping '$key'..."
        & (Join-Path $actionsFolder "Stop.ps1") -Key $key -ConfigJsonPath $ConfigJsonPath

        Write-Host "Updating '$key'..."
        & (Join-Path $actionsFolder "Update.ps1") -Key $key -ConfigJsonPath $ConfigJsonPath -FastExit

        Write-Host "Starting '$key'..."
        & (Join-Path $actionsFolder "Start.ps1") -Key $key -ConfigJsonPath $ConfigJsonPath
    }
} finally {
    # Always remove the flag, even if a step above throws, so the dashboard resumes normal auto-restart
    Remove-Item -Path $pauseFlagPath -Force -ErrorAction SilentlyContinue
    Write-Host "Auto-restart resumed (removed '$pauseFlagPath')."
}
