param(
    [string]$Key,
    [string]$ConfigJsonPath=(Get-Item $PSScriptRoot ).Parent.FullName + "\config.json"
)

. (Join-Path $PSScriptRoot "Common.ps1")

$ctx = Get-ActionContext -ConfigJsonPath $ConfigJsonPath -Key $Key
Write-ActionMessage -Ctx $ctx -ActionName "Restart" -Message "=== Restart: $Key ==="

$actionLock = Enter-ActionLock -Key $Key
if (-not $actionLock) {
    Write-ActionMessage -Ctx $ctx -ActionName "Restart" -Message "Another action is already running for '$Key'. Skipping."
    Exit 1
}

try {
    if ($ctx.Pid) {
        Write-ActionMessage -Ctx $ctx -ActionName "Restart" -Message "Stopping PID $($ctx.Pid) first..."
        & (Join-Path $PSScriptRoot "Stop.ps1") -Key $Key -ConfigJsonPath $ConfigJsonPath

        $waited = 0
        while ((Get-Process -Id $ctx.Pid -ErrorAction SilentlyContinue) -and $waited -lt 30) {
            Start-Sleep -Seconds 1
            $waited++
        }

        if (Get-Process -Id $ctx.Pid -ErrorAction SilentlyContinue) {
            Write-ActionMessage -Ctx $ctx -ActionName "Restart" -Message "Process did not stop in time, forcing kill..."
            & (Join-Path $PSScriptRoot "Kill.ps1") -Key $Key -ConfigJsonPath $ConfigJsonPath
            Start-Sleep -Seconds 2
        }
    } else {
        Write-ActionMessage -Ctx $ctx -ActionName "Restart" -Message "No running process found for '$($ctx.Key)', proceeding to start."
    }

    # Backup the server after stopping
    & (Join-Path $PSScriptRoot "Backup.ps1") -Key $Key -ConfigJsonPath $ConfigJsonPath

    Write-ActionMessage -Ctx $ctx -ActionName "Restart" -Message "Starting '$($ctx.Key)'..."
    & (Join-Path $PSScriptRoot "Start.ps1") -Key $Key -ConfigJsonPath $ConfigJsonPath
    Exit 0
} finally {
    Exit-ActionLock -Mutex $actionLock
}