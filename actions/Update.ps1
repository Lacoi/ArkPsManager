param(
    [string]$Key,
    [string]$ConfigJsonPath
)

. (Join-Path $PSScriptRoot "Common.ps1")
Import-Module (Join-Path $PSScriptRoot "ServerSync") -Force

$actionLock = Enter-ActionLock -Key $Key
if (-not $actionLock) {
    Write-Warning "Another action is already running for '$Key'. Skipping."
    Exit 1
}

try {
    Write-Host "=== Update: $Key ==="
    $ctx = Get-ActionContext -ConfigJsonPath $ConfigJsonPath -Key $Key

    if ($null -ne $ctx.Pid) {
        Write-Warning "Server '$($ctx.Key)' is running with PID $($ctx.Pid)."
        #Read-Host "Press Enter to close"
        Start-Sleep -Seconds 10
        Exit 1
    }

    $items = Get-ChildItem -Path (Join-Path $PSScriptRoot "..\Cache\Server")
    if ($items.Count -eq 0) {
        Write-Warning "Cache is empty. Please run the 'UpdateCache' action first."
        #Read-Host "Press Enter to close"
        Start-Sleep -Seconds 10
        Exit 1
    }

    Write-Host "Updating cache..."
    Update-Server -TargetPath $ctx.ServerPath
    Start-Sleep -Seconds 10
    Exit 0
} finally {
    Exit-ActionLock -Mutex $actionLock
}