# UpdateCache.ps1
# Standalone action script - takes no parameters.

. (Join-Path $PSScriptRoot "Common.ps1")

$actionsRoot = Split-Path $PSScriptRoot -Parent
$cacheRoot = Join-Path $actionsRoot "cache"
if (-not (Test-Path $cacheRoot)) {
    New-Item -Path $cacheRoot -ItemType Directory -Force | Out-Null
}
$logPath = Join-Path $actionsRoot "logs\UpdateCache.log"

$installDir = Join-Path $cacheRoot "\Server"
if (-not (Test-Path $installDir)) {
    New-Item -Path $installDir -ItemType Directory -Force | Out-Null
}

Write-ActionLog -LogPath $logPath -Message "=== UpdateCache ==="
Write-ActionLog -LogPath $logPath -Message "Running cache update at $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')..."

# ---------------------------
# AsaApi (ArkServerApi/AsaApi) cache update - only downloads when a newer release is published
# ---------------------------
function Update-AsaApiCache {
    param(
        [Parameter(Mandatory)][string]$CacheRoot,
        [Parameter(Mandatory)][string]$LogPath
    )

    $asaApiDir = Join-Path $CacheRoot "AsaApi"
    $versionFile = Join-Path $asaApiDir "version.txt"

    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/ArkServerApi/AsaApi/releases/latest" -Headers @{ "User-Agent" = "ServerManager" } -ErrorAction Stop
    } catch {
        Write-ActionLog -LogPath $LogPath -Message "Failed to check the latest AsaApi release: $_"
        return
    }

    $latestVersion = $release.tag_name
    if ([string]::IsNullOrWhiteSpace($latestVersion)) {
        Write-ActionLog -LogPath $LogPath -Message "Could not determine the latest AsaApi version from the GitHub API response."
        return
    }

    $currentVersion = $null
    if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
        $currentVersion = (Get-Content -LiteralPath $versionFile -Raw -ErrorAction SilentlyContinue).Trim()
    }

    if ($currentVersion -eq $latestVersion) {
        Write-ActionLog -LogPath $LogPath -Message "AsaApi is already up to date (version $currentVersion)."
        return
    }

    $asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
    if (-not $asset) {
        Write-ActionLog -LogPath $LogPath -Message "No zip asset found in the latest AsaApi release ($latestVersion)."
        return
    }

    Write-ActionLog -LogPath $LogPath -Message "AsaApi update available: '$currentVersion' -> '$latestVersion'. Downloading '$($asset.name)'..."

    if (-not (Test-Path $asaApiDir)) {
        New-Item -Path $asaApiDir -ItemType Directory -Force | Out-Null
    }

    $zipPath = Join-Path $asaApiDir $asset.name
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $asaApiDir -Force
        Remove-Item $zipPath -Force
        Set-Content -LiteralPath $versionFile -Value $latestVersion -Encoding UTF8
        Write-ActionLog -LogPath $LogPath -Message "AsaApi updated to version $latestVersion."

        # No need for the Plugins folder from the release, as it will be managed by the server manager and not by AsaApi itself.
        Remove-Item -Path (Join-Path $asaApiDir "ArkApi\Plugins") -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Write-ActionLog -LogPath $LogPath -Message "Failed to download/extract AsaApi release '$latestVersion': $_"
    }
}

$steamCmdDir = Join-Path $cacheRoot "SteamCMD"
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
        Start-Sleep -Seconds 5
    } catch {
        Write-ActionLog -LogPath $logPath -Message "Failed to install SteamCMD: $_"
    }
} else {
    Write-ActionLog -LogPath $logPath -Message "SteamCMD already installed at $steamCmdDir."
}

Write-ActionLog -LogPath $logPath -Message "Installing/updating app 2430930 to $installDir..."
& $steamCmdExe +force_install_dir $installDir +login anonymous +app_update 2430930 validate +quit | Tee-Object -FilePath $logPath -Append -Encoding utf8
if ($LASTEXITCODE -ne 0) {
    Write-ActionLog -LogPath $logPath -Message "Cache update failed with exit code $LASTEXITCODE. Let's delete steamapps\appmanifest_2430930.acf and try again."
    Remove-Item -Path (Join-Path $installDir "steamapps\appmanifest_2430930.acf") -Force -ErrorAction SilentlyContinue
    & $steamCmdExe +force_install_dir $installDir +login anonymous +app_update 2430930 validate +quit | Tee-Object -FilePath $logPath -Append -Encoding utf8
} else {
    # Cache update succeeded, let's check the buildid and copy the cache to a versioned folder for future use (RIP AsaApi).
    $acfPath = Join-Path $installDir "steamapps\appmanifest_2430930.acf"
    $buildId = $null
    if (Test-Path -LiteralPath $acfPath -PathType Leaf) {
        $acfContent = Get-Content -LiteralPath $acfPath -Raw -ErrorAction SilentlyContinue
        # Match only the top-level "buildid" key, not "TargetBuildID"
        if ($acfContent -match '(?m)^\s*"buildid"\s+"(\d+)"') {
            $buildId = $Matches[1]
        }
    }

    if (-not $buildId) {
        Write-ActionLog -LogPath $logPath -Message "Could not determine buildid from '$acfPath'. Skipping versioned cache copy."
    } else {
        $buildCachePath = "${installDir}_$buildId"
        if (Test-Path -LiteralPath $buildCachePath) {
            Write-ActionLog -LogPath $logPath -Message "Versioned cache '$buildCachePath' already exists. Skipping copy."
        } else {
            Write-ActionLog -LogPath $logPath -Message "Copying '$installDir' to '$buildCachePath' (build $buildId)..."
            Copy-Item -LiteralPath $installDir -Destination $buildCachePath -Recurse -Force
        }

        # Keep only the 3 most recent versioned cache copies (by buildid)
        $installDirName = Split-Path $installDir -Leaf
        $installDirParent = Split-Path $installDir -Parent
        $versionedDirs = Get-ChildItem -Path $installDirParent -Directory -Filter "$installDirName`_*" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "^$([regex]::Escape($installDirName))_(\d+)$" } |
            ForEach-Object { [PSCustomObject]@{ Path = $_.FullName; BuildId = [int64]$Matches[1] } } |
            Sort-Object BuildId -Descending

        foreach ($old in ($versionedDirs | Select-Object -Skip 3)) {
            Write-ActionLog -LogPath $logPath -Message "Removing old versioned cache '$($old.Path)' (build $($old.BuildId))..."
            Remove-Item -LiteralPath $old.Path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Update-AsaApiCache -CacheRoot $cacheRoot -LogPath $logPath

Write-ActionLog -LogPath $logPath -Message "Cache update completed with exit code $LASTEXITCODE."
Start-Sleep -Seconds 10
Exit 0
