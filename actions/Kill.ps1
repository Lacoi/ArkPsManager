param(
    [string]$Key,
    [string]$ConfigJsonPath
)

. (Join-Path $PSScriptRoot "Common.ps1")

$actionLock = Enter-ActionLock -Key $Key
if (-not $actionLock) {
    Write-Warning "Another action is already running for '$Key'. Skipping."
    Exit 1
}

try {
    Write-Host "=== Kill: $Key ==="
    $ctx = Get-ActionContext -ConfigJsonPath $ConfigJsonPath -Key $Key

    if (-not $ctx.Pid) {
        Write-Warning "No running process found for '$($ctx.Key)'. Nothing to kill."
        Start-Sleep -Seconds 10
        Exit
    }

    try {
        Write-Host "Force killing server '$($ctx.Key)' (PID $($ctx.Pid))..."
        Stop-Process -Id $ctx.Pid -Force -ErrorAction Stop
        Write-Host "Server '$($ctx.Key)' killed."
    } catch {
        Write-Warning "Failed to kill process for '$($ctx.Key)': $_"
    }

    # Backup the server after stopping
    & (Join-Path $PSScriptRoot "Backup.ps1") -Key $Key -ConfigJsonPath $ConfigJsonPath

    Start-Sleep -Seconds 10
    Exit
} finally {
    Exit-ActionLock -Mutex $actionLock
}