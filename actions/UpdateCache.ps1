# UpdateCache.ps1
# Standalone action script - takes no parameters.

. (Join-Path $PSScriptRoot "Common.ps1")

$cacheRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "cache"
if (-not (Test-Path $cacheRoot)) {
    New-Item -Path $cacheRoot -ItemType Directory -Force | Out-Null
}
$logPath = Join-Path $cacheRoot "update.log"

$installDir = Join-Path $cacheRoot "\Server"
if (-not (Test-Path $installDir)) {
    New-Item -Path $installDir -ItemType Directory -Force | Out-Null
}

Write-ActionLog -LogPath $logPath -Message "=== UpdateCache ==="
Write-ActionLog -LogPath $logPath -Message "Running cache update at $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')..."

$steamCmdDir = Join-Path $PSScriptRoot "..\cache\SteamCMD"
$steamCmdExe = Join-Path $steamCmdDir "steamcmd.exe"

if ((-not (Test-Path $steamCmdExe)) -or (-not (Test-Path $steamCmdExe -PathType Leaf))) {
    Write-ActionLog -LogPath $logPath -Message "SteamCMD not found. Installing to $steamCmdDir..."

    New-Item -Path $steamCmdDir -ItemType Directory -Force | Out-Null
    $zipPath = Join-Path $steamCmdDir "steamcmd.zip"

    try {
        Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $steamCmdDir -Force
        Remove-Item $zipPath -Force

        # First run lets steamcmd self-update/bootstrap before it's used elsewhere
        & $steamCmdExe +quit
        Write-ActionLog -LogPath $logPath -Message "SteamCMD installed successfully."
    } catch {
        Write-ActionLog -LogPath $logPath -Message "Failed to install SteamCMD: $_"
    }
} else {
    Write-ActionLog -LogPath $logPath -Message "SteamCMD already installed at $steamCmdDir."
}

Write-ActionLog -LogPath $logPath -Message "Installing/updating app 2430930 to $installDir..."
& $steamCmdExe +force_install_dir $installDir +login anonymous +app_update 2430930 validate +quit | Tee-Object -FilePath $logPath -Append -Encoding utf8

Write-ActionLog -LogPath $logPath -Message "Cache update completed."
Start-Sleep -Seconds 10
Exit 0
