param(
    [string]$Key,
    [string]$ConfigJsonPath=(Get-Item $PSScriptRoot ).Parent.FullName + "\config.json"
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

    # Update the server cache and plugins before starting the server
    & (Join-Path $PSScriptRoot "Update.ps1") -Key $Key -FastExit
    if ($LASTEXITCODE -ne 0) {
        Write-ActionMessage -Ctx $ctx -ActionName "Start" -Message "Update action failed, but we hope, that everything is working. :)"
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
    Get-ChildItem -LiteralPath $iniConfigPath -Filter "*.ini" -File -Force | Copy-Item -Destination $iniDestPath -Force

    # little break, after file copy, to avoid file locks when starting the server
    Write-ActionMessage -Ctx $ctx -ActionName "Start" -Message "Waiting 5 seconds before starting the server to avoid file locks..."
    Start-Sleep -Seconds 5

    #$runscriptPath = Join-Path (Join-Path $ctx.ServerPath $ctx.GlobalSettings.Startup.Path) "$($ctx.GlobalSettings.Startup.File)"
    $runscriptPath = Join-Path (Join-Path $ctx.ConfigPath "config") "$($ctx.GlobalSettings.Startup.File)"
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