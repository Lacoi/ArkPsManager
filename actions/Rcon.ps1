param(
    [string]$Key,
    [string]$Command,
    [string]$ConfigJsonPath=(Get-Item $PSScriptRoot ).Parent.FullName + "\config.json"
)

. (Join-Path $PSScriptRoot "Common.ps1")
Import-Module (Join-Path $PSScriptRoot "ArkRcon") -Force

$ctx = Get-ActionContext -ConfigJsonPath $ConfigJsonPath -Key $Key
Write-ActionMessage -Ctx $ctx -ActionName "Rcon" -Message "=== Rcon: $Key : $Command ==="

if ([string]::IsNullOrWhiteSpace($Command)) {
    Write-ActionMessage -Ctx $ctx -ActionName "Rcon" -Message "No Command was provided."
    Exit 1
}

if (-not $ctx.Pid) {
    Write-ActionMessage -Ctx $ctx -ActionName "Rcon" -Message "No running process found for '$($ctx.Key)'. Server must be running to send RCON commands."
    Exit 1
}

try {
    $ini = Get-IniValue -FilePath (Join-Path $ctx.ServerPath (Join-Path $ctx.GlobalSettings.Ini.Path $ctx.GlobalSettings.Ini.File)) -Section "ServerSettings" -Key "RCONPort", "ServerAdminPassword"

    $session = New-ArkRconSession -ServerIP 127.0.0.1 -Port $ini.RCONPort -Password $ini.ServerAdminPassword -LogAction {
        param([string]$Message)
        Write-ActionMessage -Ctx $ctx -ActionName "Rcon" -Message $Message
    }

    $response = Invoke-ArkRconCommand -Session $session -Command $Command
    Write-ActionMessage -Ctx $ctx -ActionName "Rcon" -Message "Response: $response"

    Close-ArkRconSession -Session $session
} catch {
    Write-ActionMessage -Ctx $ctx -ActionName "Rcon" -Message "Failed to send RCON command '$Command' to '$($ctx.Key)': $_"
    if ($session) { Close-ArkRconSession -Session $session }
    Exit 1
}

Start-Sleep -Seconds 10