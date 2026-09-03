param(
    [string]$Key,
    [string]$ConfigJsonPath=(Get-Item $PSScriptRoot ).Parent.FullName + "\config.json"
)

. (Join-Path $PSScriptRoot "Common.ps1")

$ctx = Get-ActionContext -ConfigJsonPath $ConfigJsonPath -Key $Key
Write-ActionMessage -Ctx $ctx -ActionName "Kill" -Message "=== Kill: $Key ==="

$actionLock = Enter-ActionLock -Key $Key
if (-not $actionLock) {
    Write-ActionMessage -Ctx $ctx -ActionName "Kill" -Message "Another action is already running for '$Key'. Skipping."
    Exit 1
}

try {
    if (-not $ctx.Pid) {
        Write-ActionMessage -Ctx $ctx -ActionName "Kill" -Message "No running process found for '$($ctx.Key)'. Nothing to kill."
        Start-Sleep -Seconds 10
        Exit 0
    }

    try {
        Write-ActionMessage -Ctx $ctx -ActionName "Kill" -Message "Force killing server '$($ctx.Key)' (PID $($ctx.Pid))..."
        Stop-Process -Id $ctx.Pid -Force -ErrorAction Stop
        Write-ActionMessage -Ctx $ctx -ActionName "Kill" -Message "Server '$($ctx.Key)' killed."
    } catch {
        Write-ActionMessage -Ctx $ctx -ActionName "Kill" -Message "Failed to kill process for '$($ctx.Key)': $_"
    }

    # Backup the server after stopping
    & (Join-Path $PSScriptRoot "Backup.ps1") -Key $Key -ConfigJsonPath $ConfigJsonPath

    Start-Sleep -Seconds 10
    Exit 0
} finally {
    Exit-ActionLock -Mutex $actionLock
}