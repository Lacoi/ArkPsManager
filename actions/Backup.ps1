param(
    [string]$Key,
    [string]$ConfigJsonPath
)

. (Join-Path $PSScriptRoot "Common.ps1")
Import-Module (Join-Path $PSScriptRoot "ServerBackup") -Force

$actionLock = Enter-ActionLock -Key $Key
if (-not $actionLock) {
    Write-Warning "Another action is already running for '$Key'. Skipping."
    Exit 1
}

try {
    Write-Host "=== Backup: $Key ==="
    $ctx = Get-ActionContext -ConfigJsonPath $ConfigJsonPath -Key $Key

    Backup-ArkServer -SourcePath $ctx.ServerPath -DestinationPath $ctx.BackupPath -ArkExtensions @('.arkprofile', '.arktribe', '.arktributetribe', '.profilebak', '.tribebak')
    Write-Host "Backup completed"
    Start-Sleep -Seconds 10
    Exit 0
} finally {
    Exit-ActionLock -Mutex $actionLock
}