param(
    [string]$Key,
    [string]$ConfigJsonPath=(Get-Item $PSScriptRoot ).Parent.FullName + "\config.json",
    [switch]$SkipServerUpdate,
    [switch]$FastExit
)

. (Join-Path $PSScriptRoot "Common.ps1")
Import-Module (Join-Path $PSScriptRoot "ServerSync") -Force

$actionsRoot = (Get-Item $PSScriptRoot).Parent.FullName
$ctx = Get-ActionContext -ConfigJsonPath $ConfigJsonPath -Key $Key
Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "=== Update: $Key ==="

$actionLock = Enter-ActionLock -Key $Key
if (-not $actionLock) {
    Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Another action is already running for '$Key'. Skipping."
    Exit 1
}

try {
    if ($null -ne $ctx.Pid) {
        Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Server '$($ctx.Key)' is running with PID $($ctx.Pid)."
        if (-not $FastExit) { Start-Sleep -Seconds 10 }
        Exit 1
    }

    # A '<buildid>.build' marker file pins updates to a specific cached build, if that build's folder still exists.
    # Entries with UseLatestBuild set skip this and always use the default (latest) cache.
    if ($SkipServerUpdate) {
        Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "SkipServerUpdate is set; skipping the server cache update."
    } else {
        $cacheDir = Join-Path $actionsRoot "Cache"
        $serverCachePath = Join-Path $cacheDir "Server"
        if ($ctx.UseLatestBuild) {
            Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "UseLatestBuild is enabled for '$Key'; ignoring any pinned build."
        } else {
            $buildFile = Get-ChildItem -Path $cacheDir -Filter "*.build" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.BaseName -match '^\d+$' } |
                Sort-Object { [int64]$_.BaseName } -Descending |
                Select-Object -First 1
            if ($buildFile) {
                $pinnedCachePath = Join-Path $cacheDir "Server_$($buildFile.BaseName)"
                if (Test-Path -LiteralPath $pinnedCachePath -PathType Container) {
                    Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Pinned build '$($buildFile.BaseName)' found ($($buildFile.Name)). Using '$pinnedCachePath' as the server cache."
                    $serverCachePath = $pinnedCachePath
                } else {
                    Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Pinned build file '$($buildFile.Name)' found, but '$pinnedCachePath' does not exist. Falling back to the default cache."
                }
            }
        }

        # Check emptiness of the cache path that will actually be used (default or pinned), not always the default
        $items = Get-ChildItem -Path $serverCachePath -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $items) {
            Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Cache is empty. Please run the 'UpdateCache' action first."
            if (-not $FastExit) { Start-Sleep -Seconds 10 }
            Exit 1
        }

        Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Updating cache..."
        Update-Server -TargetPath $ctx.ServerPath -CachePath $serverCachePath -LogAction {
            param([string]$Message)
            Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message $Message
        }
    }

    ## sync the ArkApi cache to the server path, excluding certain files that are not needed or should not be overwritten
    try {
        $apiCachePath = Join-Path $actionsRoot "Cache\AsaApi"
        $items = Get-ChildItem -Path $apiCachePath -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $items) {
            Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "ArkApi cache is empty. Skipping update. Please run the 'UpdateCache' action first."
        } else {
            Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Updating ArkApi..."

            $apiPath = Join-Path $ctx.ServerPath $ctx.ProcessPath
            Sync-Folder -Source $apiCachePath -Target $apiPath -ExcludeFilter 'config.json', 'Lib\AsaApi.lib', 'msvcp140.dll', 'version.txt' -Verbose -LogAction {
                param([string]$Message)
                Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message $Message
            }

            # Copy the config.json file from the config api folder to the server path, overwriting any existing file
            Copy-Item -Path (Join-Path $actionsRoot 'config\api\config.json') -Destination (Join-Path $apiPath 'config.json') -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "ArkApi Update failed: $_"
    }

    # Update plugins: copy new/changed files from the default and map-specific plugin caches
    # (map-specific wins on name conflicts, since it's applied second), then remove anything from
    # PluginPath that's no longer in either source - one combined diff instead of two independent
    # mirrors, which would delete and re-copy each other's files on every run.
    $pluginPath = Join-Path $ctx.ServerPath (Join-Path $ctx.ProcessPath "ArkApi\Plugins")
    $defaultPluginCache = Join-Path $actionsRoot "Cache\AsaApiPlugins"
    $mapPluginCache = Join-Path $actionsRoot (Join-Path "config\maps" (Join-Path $ctx.Key "plugins"))
    $defaultPluginCacheExists = Test-Path -LiteralPath $defaultPluginCache -PathType Container
    $mapPluginCacheExists = Test-Path -LiteralPath $mapPluginCache -PathType Container

    try {
        if (-not $defaultPluginCacheExists -and -not $mapPluginCacheExists) {
            Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Plugin caches not found. Skipping update. Please run the 'UpdateCache' action first."
        } else {
            if ($defaultPluginCacheExists) {
                Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Updating plugins..."
                Sync-Folder -Source $defaultPluginCache -Target $pluginPath -Verbose -LogAction {
                    param([string]$Message)
                    Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message $Message
                }
            }

            # map-specific plugins layer on top of, and take precedence over, the default cache
            if ($mapPluginCacheExists) {
                Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Updating PluginConfig..."
                Sync-Folder -Source $mapPluginCache -Target $pluginPath -Verbose -LogAction {
                    param([string]$Message)
                    Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message $Message
                }
            }

            # build the combined set of relative paths that should exist, from both sources
            $expectedRelativePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($cachePath in @($defaultPluginCache, $mapPluginCache)) {
                if (-not (Test-Path -LiteralPath $cachePath -PathType Container)) { continue }
                $resolvedCache = (Resolve-Path -LiteralPath $cachePath).ProviderPath.TrimEnd('\', '/')
                Get-ChildItem -LiteralPath $resolvedCache -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    [void]$expectedRelativePaths.Add($_.FullName.Substring($resolvedCache.Length).TrimStart('\', '/'))
                }
            }

            # delete anything in PluginPath that's not present in either source
            if (Test-Path -LiteralPath $pluginPath -PathType Container) {
                $resolvedTarget = (Resolve-Path -LiteralPath $pluginPath).ProviderPath.TrimEnd('\', '/')
                Get-ChildItem -LiteralPath $resolvedTarget -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    $relativePath = $_.FullName.Substring($resolvedTarget.Length).TrimStart('\', '/')
                    if (-not $expectedRelativePaths.Contains($relativePath)) {
                        Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Removing orphaned plugin file: $relativePath"
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                    }
                }

                # clean up any folders left empty by the deletions above (deepest first)
                Get-ChildItem -LiteralPath $resolvedTarget -Recurse -Directory -Force -ErrorAction SilentlyContinue |
                    Sort-Object { $_.FullName.Length } -Descending |
                    Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1) } |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Plugin Update failed: $_"
    }

    if (-not $FastExit) { Start-Sleep -Seconds 10 }
    Exit 0
} finally {
    Exit-ActionLock -Mutex $actionLock
}