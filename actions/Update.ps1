param(
    [string]$Key,
    [string]$ConfigJsonPath
)

. (Join-Path $PSScriptRoot "Common.ps1")
Import-Module (Join-Path $PSScriptRoot "ServerSync") -Force

$ctx = Get-ActionContext -ConfigJsonPath $ConfigJsonPath -Key $Key
Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "=== Update: $Key ==="

$actionLock = Enter-ActionLock -Key $Key
if (-not $actionLock) {
    Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Another action is already running for '$Key'. Skipping."
    Exit 1
}

try {
    if ($null -ne $ctx.Pid) {
        Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Server '$($ctx.Key)' is running with PID $($ctx.Pid)."
        Start-Sleep -Seconds 10
        Exit 1
    }

    $items = Get-ChildItem -Path (Join-Path $PSScriptRoot "..\Cache\Server")
    if ($items.Count -eq 0) {
        Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Cache is empty. Please run the 'UpdateCache' action first."
        Start-Sleep -Seconds 10
        Exit 1
    }

    Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Updating cache..."
    Update-Server -TargetPath $ctx.ServerPath -LogAction {
        param([string]$Message)
        Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message $Message
    }

    Start-Sleep -Seconds 10
    Exit 0
} finally {
    Exit-ActionLock -Mutex $actionLock
}