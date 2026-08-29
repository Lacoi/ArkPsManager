param(
    [string]$Key,
    [string]$ConfigJsonPath
)

. (Join-Path $PSScriptRoot "Common.ps1")
Import-Module (Join-Path $PSScriptRoot "ServerSync") -Force

$ctx = Get-ActionContext -ConfigJsonPath $ConfigJsonPath -Key $Key
Write-ActionMessage -Ctx $ctx -ActionName "Start" -Message "=== Start: $Key ==="

$actionLock = Enter-ActionLock -Key $Key
if (-not $actionLock) {
    Write-ActionMessage -Ctx $ctx -ActionName "Start" -Message "Another action is already running for '$Key'. Skipping."
    Exit 1
}

try {
    if ($null -ne $ctx.Pid) {
        Write-ActionMessage -Ctx $ctx -ActionName "Start" -Message "Server '$($ctx.Key)' is already running with PID $($ctx.Pid)."
        Start-Sleep -Seconds 10
        Exit 1
    }

    Write-ActionMessage -Ctx $ctx -ActionName "Start" -Message "Updating cache before starting the server..."
    Update-Server -TargetPath $ctx.ServerPath -LogAction {
        param([string]$Message)
        Write-ActionMessage -Ctx $ctx -ActionName "Start" -Message $Message
    }

    # Copy ini files from config to server path
    $iniConfigPath = Join-Path $ctx.ConfigPath "config"
    if (-not (Test-Path $iniConfigPath)) {
        New-Item -Path $iniConfigPath -ItemType Directory -Force | Out-Null
    }
    $iniDestPath = Join-Path $ctx.ServerPath $ctx.GlobalSettings.Ini.Path
    if (-not (Test-Path $iniDestPath)) {
        New-Item -Path $iniDestPath -ItemType Directory -Force | Out-Null
    }
    Write-ActionMessage -Ctx $ctx -ActionName "Start" -Message "Copying ini files from $iniConfigPath to $iniDestPath..."
    Get-ChildItem -LiteralPath $iniConfigPath -Force | Copy-Item -Destination $iniDestPath -Recurse -Force

    # Copy plugin files from config to server path
    $pluginPath = Join-Path $ctx.ConfigPath "plugin"
    if (Test-Path $pluginPath) {
        Write-ActionMessage -Ctx $ctx -ActionName "Start" -Message "Copying plugin files from $pluginPath to $(Join-Path $ctx.ServerPath "ShooterGame\Binaries\Win64\ArkApi")..."
        Copy-Item -Path $pluginPath -Destination (Join-Path $ctx.ServerPath "ShooterGame\Binaries\Win64\ArkApi") -Recurse -Force
    }

    # little break, after file copy, to avoid file locks when starting the server
    Start-Sleep -Seconds 2

    $runscriptPath = Join-Path (Join-Path $ctx.ServerPath $ctx.GlobalSettings.Startup.Path) "$($ctx.GlobalSettings.Startup.File)"
    if (-not (Test-Path $runscriptPath -PathType Leaf)) {
        Write-ActionMessage -Ctx $ctx -ActionName "Start" -Message "Executable not found: $runscriptPath"
        Start-Sleep -Seconds 10
        Exit 1
    }

    Write-ActionMessage -Ctx $ctx -ActionName "Start" -Message "Starting server '$($ctx.Key)' -> $runscriptPath"
    Start-Process -FilePath $runscriptPath -WorkingDirectory (Split-Path $runscriptPath -Parent)

    $maxAttempts = 10
    $attempt = 0
    $started = $false
    while ($attempt -lt $maxAttempts) {
        Start-Sleep -Seconds 5
        $attempt++
        $proc = Test-ProcessRunning $ctx
        if ($false -ne $proc) {
            Write-ActionMessage -Ctx $ctx -ActionName "Start" -Message "Server '$($ctx.Key)' started successfully with PID $proc."
            $started = $true
            break
        }
        Write-ActionMessage -Ctx $ctx -ActionName "Start" -Message "Waiting for server '$($ctx.Key)' to start... (attempt $attempt/$maxAttempts)"
    }
    if (-not $started) {
        Write-ActionMessage -Ctx $ctx -ActionName "Start" -Message "Server '$($ctx.Key)' did not start within $maxAttempts attempts."
    }
    Start-Sleep -Seconds 10
    Exit

} finally {
    Exit-ActionLock -Mutex $actionLock
}