param(
    [string]$Key,
    [string]$ConfigJsonPath=(Get-Item $PSScriptRoot ).Parent.FullName + "\config.json"
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
        Start-Sleep -Seconds 10
        Exit 1
    }

    # A '<buildid>.build' marker file pins updates to a specific cached build, if that build's folder still exists
    $cacheDir = Join-Path $actionsRoot "Cache"
    $serverCachePath = Join-Path $cacheDir "Server"
    $buildFile = Get-ChildItem -Path $cacheDir -Filter "*.build" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName -match '^\d+$' } |
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

    # Check emptiness of the cache path that will actually be used (default or pinned), not always the default
    $items = Get-ChildItem -Path $serverCachePath -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $items) {
        Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Cache is empty. Please run the 'UpdateCache' action first."
        Start-Sleep -Seconds 10
        Exit 1
    }

    Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Updating cache..."
    Update-Server -TargetPath $ctx.ServerPath -CachePath $serverCachePath -LogAction {
        param([string]$Message)
        Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message $Message
    }

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
        }
    } catch {
        Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "ArkApi Update failed: $_"
    }

    try {
        $pluginCachePath = Join-Path $actionsRoot "Cache\AsaApiPlugins"
        $items = Get-ChildItem -Path $pluginCachePath -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $items) {
            Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Plugin cache is empty. Skipping update. Please run the 'UpdateCache' action first."
        } else {
            Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Updating plugins..."

            $pluginPath = Join-Path $ctx.ServerPath (Join-Path $ctx.ProcessPath "ArkApi\Plugins")
            Sync-Folder -Source $pluginCachePath -Target $pluginPath -Verbose -LogAction {
                param([string]$Message)
                Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message $Message
            }
        }
    } catch {
        Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Plugin Update failed: $_"
    }

    try {
        $pluginCachePath = Join-Path $actionsRoot (Join-Path "config\maps" (Join-Path $ctx.Key "plugins"))
        $items = Get-ChildItem -Path $pluginCachePath -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $items) {
            Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "PluginConfig cache is empty. Skipping update. Please run the 'UpdateCache' action first."
        } else {
            Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "Updating PluginConfig..."

            $pluginPath = Join-Path $ctx.ServerPath (Join-Path $ctx.ProcessPath "ArkApi\Plugins")
            Sync-Folder -Source $pluginCachePath -Target $pluginPath -Verbose -LogAction {
                param([string]$Message)
                Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message $Message
            }
        }
    } catch {
        Write-ActionMessage -Ctx $ctx -ActionName "Update" -Message "PluginConfig Update failed: $_"
    }

    Start-Sleep -Seconds 10
    Exit 0
} finally {
    Exit-ActionLock -Mutex $actionLock
}