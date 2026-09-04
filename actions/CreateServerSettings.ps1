[CmdletBinding(SupportsShouldProcess)]
param()

. (Join-Path $PSScriptRoot "Common.ps1")

$actionsRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'IniMerge') -Force -ErrorAction Stop

$logPath = Join-Path $actionsRoot "logs/CreateServerSettings.log"
Write-ActionLog -LogPath $logPath -Message "=== Create CreateServerSettings Start ==="

$baseGusIniPath = Join-Path $actionsRoot 'config\ini\Base_GameUserSettings.ini'
$baseGameIniPath = Join-Path $actionsRoot 'config\ini\Base_Game.ini'
$appendRoot = Join-Path $actionsRoot 'config\ini'
$baseRunJsonPath = Join-Path $appendRoot 'run.json'

if (-not (Test-Path -LiteralPath $baseGusIniPath -PathType Leaf)) {
	throw "Base INI file not found: $baseGusIniPath"
}
if (-not (Test-Path -LiteralPath $baseGameIniPath -PathType Leaf)) {
	throw "Base INI file not found: $baseGameIniPath"
}
if (-not (Test-Path -LiteralPath $baseRunJsonPath -PathType Leaf)) {
    throw "Base run configuration not found: $baseRunJsonPath"
}

$config = Get-Content -LiteralPath (Join-Path $actionsRoot "config.json") -Raw -ErrorAction Stop | ConvertFrom-Json

# Parse the shared base once, then merge it independently for every server.
$baseGusIni = Read-IniFile -FilePath $baseGusIniPath
$baseGameIni = Read-IniFile -FilePath $baseGameIniPath
$baseRunConfig = Get-Content -LiteralPath $baseRunJsonPath -Raw -ErrorAction Stop | ConvertFrom-Json
$processedCount = 0
$copyCount = 0
$skippedCount = 0
$runFileCount = 0

# Hoisted out of the per-entry loop so they aren't rebuilt on every iteration
$iniFileTypes = @("GameUserSettings", "Game")
$mergeStrategies = @("Append", "Override")

foreach ($entry in $config.Entries) {
    if ([string]::IsNullOrWhiteSpace($entry.Key)) {
        Write-Warning 'Skipping an entry with a missing Key.'
        $skippedCount++
        continue
    }

    foreach ($iniFile in $iniFileTypes) {
        $mergedIni = if ($iniFile -eq "GameUserSettings") { $baseGusIni } else { $baseGameIni }
        $outputPath = Join-Path $actionsRoot (Join-Path "config\maps" (Join-Path $entry.Key "config\$($iniFile).ini"))
        $hasMergeFile = $false

        foreach ($strategy in $mergeStrategies) {
            $mergeIniPath = Join-Path $appendRoot (Join-Path $entry.Key "$($iniFile)_$($strategy).ini")
            if (-not (Test-Path -LiteralPath $mergeIniPath -PathType Leaf)) {
                continue
            }

            $hasMergeFile = $true
            Write-ActionLog -LogPath $logPath -Message "[$($entry.Key)] Merging '$mergeIniPath' using '$strategy'."
            $toMergedIni = Read-IniFile -FilePath $mergeIniPath
            $mergedIni = Merge-IniFiles -FirstIni $mergedIni -SecondIni $toMergedIni -Strategy $strategy
        }

        if ($PSCmdlet.ShouldProcess($outputPath, "$($entry.Key): Write merged '$iniFile.ini' to '$outputPath'.")) {
            Write-IniFile -IniData $mergedIni -FilePath $outputPath
            Write-ActionLog -LogPath $logPath -Message "[$($entry.Key)] Write merged '$iniFile.ini' to '$outputPath'."
        }

        if ($hasMergeFile) {
            $processedCount++
        } else {
            $copyCount++
        }
    }

    $entryRunJsonPath = Join-Path $appendRoot (Join-Path $entry.Key 'run.json')
    if (-not (Test-Path -LiteralPath $entryRunJsonPath -PathType Leaf)) {
        Write-ActionLog -LogPath $logPath -Message "[$($entry.Key)] Skipping RunServer.cmd: run configuration not found at '$entryRunJsonPath'."
        continue
    }

    $entryRunConfig = Get-Content -LiteralPath $entryRunJsonPath -Raw -ErrorAction Stop | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace($entryRunConfig.map)) {
        Write-ActionLog -LogPath $logPath -Message "[$($entry.Key)] Skipping RunServer.cmd: the map property is required."
        continue
    }

    $startOptions = @($baseRunConfig.startOptions) + @($entryRunConfig.startOptions)
    $urlOptions = @($baseRunConfig.urlOptions) + @($entryRunConfig.urlOptions) | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_)
    } | Select-Object -Unique
    $commandLineOptions = @($baseRunConfig.commandLineOptions) + @($entryRunConfig.commandLineOptions) | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_)
    } | Select-Object -Unique
    $mods = @($baseRunConfig.mods) + @($entryRunConfig.mods) | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_)
    } | Select-Object -Unique
    $serverExecutable = Join-Path $entry.ServerPath (Join-Path $config.GlobalSettings.Process.Path "$($config.GlobalSettings.Startup.Name).exe")
    $serverUrl = $entryRunConfig.map + '?' + ($urlOptions -join '?')
    $arguments = @($commandLineOptions)
    if ($mods.Count -gt 0) {
        $arguments += "-mods=$($mods -join ',')"
    }
    $command = "start `"#$($entry.Key)`" $($startOptions -join ' ') `"$serverExecutable`" $serverUrl $($arguments -join ' ')".Trim() -replace ' {2,}', ' '
    $runServerPath = Join-Path $actionsRoot (Join-Path 'config\maps' (Join-Path $entry.Key 'config\RunServer.cmd'))

    $runFileCount++
    if ($PSCmdlet.ShouldProcess($runServerPath, "$($entry.Key): Write RunServer.cmd")) {
        $outputDirectory = Split-Path -Path $runServerPath -Parent
        New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllText($runServerPath, $command + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        Write-ActionLog -LogPath $logPath -Message "[$($entry.Key)] Created RunServer.cmd at '$runServerPath'."
    }
}

Write-ActionLog -LogPath $logPath -Message "INI sync complete: $processedCount merged, $copyCount copied, $skippedCount skipped; $runFileCount RunServer.cmd file(s) generated."
Start-Sleep -Seconds 10