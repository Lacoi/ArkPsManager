param(
    [string]$Key,
    [string]$ConfigJsonPath
)

. (Join-Path $PSScriptRoot "Common.ps1")
Import-Module (Join-Path $PSScriptRoot "ArkRcon") -Force

$actionLock = Enter-ActionLock -Key $Key
if (-not $actionLock) {
    Write-Warning "Another action is already running for '$Key'. Skipping."
    Exit 1
}

try {
    Write-Host "=== Stop: $Key ==="
    $ctx = Get-ActionContext -ConfigJsonPath $ConfigJsonPath -Key $Key

    if (-not $ctx.Pid) {
        Write-Warning "No running process found for '$($ctx.Key)'. Nothing to stop."
        Exit 1
        return
    }

    try {
        $ini = Get-IniValue -FilePath (Join-Path $ctx.ServerPath (Join-Path $ctx.GlobalSettings.Ini.Path $ctx.GlobalSettings.Ini.File)) -Section "ServerSettings" -Key "RCONPort", "ServerAdminPassword"

        $DebugPreference = 'Continue' 

        $session = New-ArkRconSession -ServerIP 127.0.0.1 -Port $ini.RCONPort -Password $ini.ServerAdminPassword -DebugMode

        $shutdownTime = [int]$ctx.GlobalSettings.Shutdown.Time
        $messages = $ctx.GlobalSettings.Shutdown.Messages

        for ($secondsLeft = $shutdownTime; $secondsLeft -ge 0; $secondsLeft--) {
            $match = $messages.PSObject.Properties | Where-Object { $_.Name -eq "$secondsLeft" } | Select-Object -First 1
            if ($match) {
                Write-Host "[$secondsLeft s] Broadcasting: $($match.Value)"
                Invoke-ArkRconCommand -Session $session -Command "broadcast $($match.Value)"
            }

            if ($secondsLeft % 15 -eq 0) {
                $playerList = Invoke-ArkRconCommand -Session $session -Command "listplayers"
                Write-Host "[$secondsLeft s] Players connected: $playerList"
                if ($playerList -match "No Players Connected") {
                    Write-Host "No players connected, ending shutdown wait early."
                    break
                }
            }

            Start-Sleep -Seconds 1
        }

        Write-Host "Sending saveworld command to server..."
        Invoke-ArkRconCommand -Session $session -Command "saveworld"

        # Wait a few seconds to ensure the save completes before shutting down
        Start-Sleep -Seconds 20

        Write-Host "Sending DoExit command to server..."
        Invoke-ArkRconCommand -Session $session -Command "DoExit"

        Close-ArkRconSession -Session $session

        $maxAttempts = 24 # 2 minutes
        $attempt = 0
        $processExited = $false
        while ($attempt -lt $maxAttempts) {
            Write-Host "Waiting for server '$($ctx.Key)' to stop... (attempt $($attempt + 1)/$maxAttempts)"
            if (-not (Get-Process -Id $ctx.Pid -ErrorAction SilentlyContinue)) {
                $processExited = $true
                break
            }
            $attempt++
            Start-Sleep -Seconds 5
        }

        if (-not $processExited) {
            Write-Warning "Process PID $($ctx.Pid) did not exit in time, forcing kill..."
            throw "Process PID $($ctx.Pid) did not exit in time, forcing kill..."
        } else {
            Write-Host "Server '$($ctx.Key)' stopped successfully."
        }
    } catch {
        Write-Warning "Failed to stop process for '$($ctx.Key)': $_"
        Close-ArkRconSession -Session $session

        ## Fallback to killing the process if RCON fails
        $proc = Get-Process -Id $ctx.Pid -ErrorAction Stop
        Write-Host "Stopping server '$($ctx.Key)' (PID $($ctx.Pid)) gracefully..."

        if (-not $proc.CloseMainWindow()) {
            Write-Warning "CloseMainWindow() failed or has no main window; falling back to Stop-Process."
            Stop-Process -Id $ctx.Pid -ErrorAction Stop
        } else {
            $exited = $proc.WaitForExit(10000)
            if (-not $exited) {
                Write-Warning "Process did not exit within timeout after CloseMainWindow()."
            } else {
                Write-Host "Server '$($ctx.Key)' stopped."
            }
        }
    }

    # Backup the server after stopping
    & (Join-Path $PSScriptRoot "Backup.ps1") -Key $Key -ConfigJsonPath $ConfigJsonPath

    Start-Sleep 10
    Exit 0
} finally {
    Exit-ActionLock -Mutex $actionLock
}