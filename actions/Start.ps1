param(
    [string]$Key,
    [string]$ConfigJsonPath
)

. (Join-Path $PSScriptRoot "Common.ps1")
Import-Module (Join-Path $PSScriptRoot "ServerSync") -Force

$actionLock = Enter-ActionLock -Key $Key
if (-not $actionLock) {
    Write-Warning "Another action is already running for '$Key'. Skipping."
    Exit 1
}

try {

Write-Host "=== Start: $Key ==="
$ctx = Get-ActionContext -ConfigJsonPath $ConfigJsonPath -Key $Key

if ($null -ne $ctx.Pid) {
    Write-Warning "Server '$($ctx.Key)' is already running with PID $($ctx.Pid)."
    #Read-Host "Press Enter to close"
    Start-Sleep -Seconds 10
    Exit 1
}

Write-Host "Updating cache before starting the server..."
Update-Server -TargetPath $ctx.ServerPath

$runscriptPath = Join-Path (Join-Path $ctx.ServerPath $ctx.GlobalSettings.Startup.Path) "$($ctx.GlobalSettings.Startup.File)"
if (-not (Test-Path $runscriptPath -PathType Leaf)) {
    Write-Warning "Executable not found: $runscriptPath"
    #Read-Host "Press Enter to close"
    Start-Sleep -Seconds 10
    Exit 1
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
Write-Host "Copying ini files from $($ctx.ConfigPath) to $iniDestPath..."
#Copy-Item -Path (Join-Path $iniConfigPath "*.ini") -Destination $iniDestPath -Force
Copy-Item -Path $iniConfigPath -Destination $iniDestPath -Force

# Copy plugin files from config to server path
$pluginPath = Join-Path $ctx.ConfigPath "plugin"
if (Test-Path $pluginPath) {
    Write-Host "Copying plugin files from $pluginPath to $(Join-Path $ctx.ServerPath "ShooterGame\Binaries\Win64\ArkApi")..."
    Copy-Item -Path $pluginPath -Destination (Join-Path $ctx.ServerPath "ShooterGame\Binaries\Win64\ArkApi") -Recurse -Force
}

# little break, after file copy, to avoid file locks when starting the server
Start-Sleep -Seconds 2

Write-Host "Starting server '$($ctx.Key)' -> $runscriptPath"
Start-Process -FilePath $runscriptPath -WorkingDirectory (Split-Path $runscriptPath -Parent)

$maxAttempts = 10
$attempt = 0
$started = $false
while ($attempt -lt $maxAttempts) {
    Start-Sleep -Seconds 5
    $attempt++
    $proc = Test-ProcessRunning $ctx
    if ($false -ne $proc) {
        Write-Host "Server '$($ctx.Key)' started successfully with PID $proc."
        $started = $true
        break
    }
    Write-Host "Waiting for server '$($ctx.Key)' to start... (attempt $attempt/$maxAttempts)"
}
if (-not $started) {
    Write-Warning "Server '$($ctx.Key)' did not start within $maxAttempts attempts."
}
Start-Sleep -Seconds 10
Exit

} finally {
    Exit-ActionLock -Mutex $actionLock
}