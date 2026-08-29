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
    Write-Host "=== Restart: $Key ==="
    $ctx = Get-ActionContext -ConfigJsonPath $ConfigJsonPath -Key $Key

    if ($ctx.Pid) {
        Write-Host "Stopping PID $($ctx.Pid) first..."
        & (Join-Path $PSScriptRoot "Stop.ps1") -Key $Key -ConfigJsonPath $ConfigJsonPath

        $waited = 0
        while ((Get-Process -Id $ctx.Pid -ErrorAction SilentlyContinue) -and $waited -lt 30) {
            Start-Sleep -Seconds 1
            $waited++
        }

        if (Get-Process -Id $ctx.Pid -ErrorAction SilentlyContinue) {
            Write-Warning "Process did not stop in time, forcing kill..."
            & (Join-Path $PSScriptRoot "Kill.ps1") -Key $Key -ConfigJsonPath $ConfigJsonPath
            Start-Sleep -Seconds 2
        }
    } else {
        Write-Host "No running process found for '$($ctx.Key)', proceeding to start."
    }

    # Backup the server after stopping
    & (Join-Path $PSScriptRoot "Backup.ps1") -Key $Key -ConfigJsonPath $ConfigJsonPath

    Write-Host "Starting '$($ctx.Key)'..."
    & (Join-Path $PSScriptRoot "Start.ps1") -Key $Key -ConfigJsonPath $ConfigJsonPath
    Read-Host "Press Enter to close"
} finally {
    Exit-ActionLock -Mutex $actionLock
}