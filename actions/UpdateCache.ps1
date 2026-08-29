# UpdateCache.ps1
# Standalone action script - takes no parameters.

Write-Host "=== UpdateCache ==="
Write-Host "Running cache update at $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')..."

$steamCmdDir = Join-Path $PSScriptRoot "..\cache\SteamCMD"
$steamCmdExe = Join-Path $steamCmdDir "steamcmd.exe"

if ((-not (Test-Path $steamCmdExe)) -or (-not (Test-Path $steamCmdExe -PathType Leaf))) {
    Write-Host "SteamCMD not found. Installing to $steamCmdDir..."

    New-Item -Path $steamCmdDir -ItemType Directory -Force | Out-Null
    $zipPath = Join-Path $steamCmdDir "steamcmd.zip"

    try {
        Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $steamCmdDir -Force
        Remove-Item $zipPath -Force

        # First run lets steamcmd self-update/bootstrap before it's used elsewhere
        & $steamCmdExe +quit
        Write-Host "SteamCMD installed successfully."
    } catch {
        Write-Warning "Failed to install SteamCMD: $_"
    }
} else {
    Write-Host "SteamCMD already installed at $steamCmdDir."
}

$installDir = Join-Path $PSScriptRoot "..\Cache\Server"

Write-Host "Installing/updating app 2430930 to $installDir..."
& $steamCmdExe +force_install_dir $installDir +login anonymous +app_update 2430930 validate +quit

Write-Host "Cache update completed."
Start-Sleep -Seconds 10
Exit 0
