param(
    [string]$Key,
    [string]$ConfigJsonPath=(Get-Item $PSScriptRoot ).Parent.FullName + "\config.json"
)

. (Join-Path $PSScriptRoot "Common.ps1")
Import-Module (Join-Path $PSScriptRoot "ServerBackup") -Force

$ctx = Get-ActionContext -ConfigJsonPath $ConfigJsonPath -Key $Key
Write-ActionMessage -Ctx $ctx -ActionName "Backup" -Message "=== Backup: $Key ==="

$actionLock = Enter-ActionLock -Key $Key
if (-not $actionLock) {
    Write-ActionMessage -Ctx $ctx -ActionName "Backup" -Message "Another action is already running for '$Key'. Skipping."
    Exit 1
}

try {

    Backup-ArkServer -SourcePath $ctx.ServerPath -DestinationPath $ctx.BackupPath -ArkExtensions @('.arkprofile', '.arktribe', '.arktributetribe', '.profilebak', '.tribebak') -LogAction {
        param([string]$Message)
        Write-ActionMessage -Ctx $ctx -ActionName "Backup" -Message $Message
    }

    Invoke-BackupRetention -BackupPath $ctx.BackupPath -DailyRetentionDays $(if ($ctx.GlobalSettings.Backup.DailyToKeep) { [int]$ctx.GlobalSettings.Backup.DailyToKeep } else { 7 }) -WeeklyBackupsToKeep $(if ($ctx.GlobalSettings.Backup.WeeklyToKeep) { [int]$ctx.GlobalSettings.Backup.WeeklyToKeep } else { 4 }) -LogAction {
        param([string]$Message)
        Write-ActionMessage -Ctx $ctx -ActionName "Backup" -Message $Message
    }

    Write-ActionMessage -Ctx $ctx -ActionName "Backup" -Message "Backup completed"
    Start-Sleep -Seconds 10
    Exit 0
} finally {
    Exit-ActionLock -Mutex $actionLock
}