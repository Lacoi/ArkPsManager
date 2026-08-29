# ServerBackup.psm1
# Server Backup helpers, imported via: Import-Module (Join-Path $PSScriptRoot "ServerBackup") -Force

function Backup-ArkServer {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,          # Root folder containing "ShooterGame\..."

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,     # Where the final zip should be placed

        [Parameter(Mandatory = $false)]
        [string[]]$ArkExtensions = @('.arkprofile', '.arktribe'),  # Extensions to grab from SavedArks subfolder

        [Parameter(Mandatory = $false)]
        [switch]$ShowProgress         # Display a Write-Progress bar while archiving
    )

    if (-not (Test-Path $SourcePath)) {
        throw "Source path '$SourcePath' does not exist."
    }
    if (-not (Test-Path $DestinationPath)) {
        if ($PSCmdlet.ShouldProcess($DestinationPath, "Create destination directory")) {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        }
    }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

    # ---------------------------------------------------------
    # Build the full list of (SourceFile, EntryName) pairs up front
    # so -WhatIf and progress reporting can work against a known total.
    # ---------------------------------------------------------
    $filePlan = New-Object System.Collections.Generic.List[object]
    $mapName  = $null

    $configSrc = Join-Path $SourcePath "ShooterGame\Saved\Config\WindowsServer"
    if (Test-Path $configSrc) {
        Get-ChildItem -Path $configSrc -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring($configSrc.Length).TrimStart('\', '/')
            $filePlan.Add([pscustomobject]@{
                SourceFile = $_.FullName
                EntryName  = Join-Path "Config\WindowsServer" $relative
            })
        }
    }
    else {
        Write-Warning "WindowsServer config path not found: $configSrc"
    }

    $savedArksSrc = Join-Path $SourcePath "ShooterGame\Saved\SavedArks"
    if (Test-Path $savedArksSrc) {
        $mapSubFolder = Get-ChildItem -Path $savedArksSrc -Directory | Select-Object -First 1

        if ($null -ne $mapSubFolder) {
            $mapName   = $mapSubFolder.Name
            $entryRoot = "SavedArks\$mapName"

            foreach ($ext in $ArkExtensions) {
                Get-ChildItem -Path $mapSubFolder.FullName -Filter "*$ext" -File -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        $filePlan.Add([pscustomobject]@{
                            SourceFile = $_.FullName
                            EntryName  = Join-Path $entryRoot $_.Name
                        })
                    }
            }

            # Locate the .ark save file matching the subfolder name (inside the subfolder)
            $arkFile = Join-Path $mapSubFolder.FullName "$mapName.ark"

            if (Test-Path $arkFile) {
                $destArkName = if ($mapName -match '_wp$') { "$mapName.ark" } else { "${mapName}_wp.ark" }
                $filePlan.Add([pscustomobject]@{
                    SourceFile = $arkFile
                    EntryName  = Join-Path $entryRoot $destArkName
                })
            }
            else {
                Write-Warning "Expected .ark file not found: $arkFile"
            }
        }
        else {
            Write-Warning "No subfolder found under SavedArks: $savedArksSrc"
        }
    }
    else {
        Write-Warning "SavedArks path not found: $savedArksSrc"
    }

    $saveGamesSrc = Join-Path $SourcePath "ShooterGame\Saved\SaveGames"
    if (Test-Path $saveGamesSrc) {
        Get-ChildItem -Path $saveGamesSrc -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring($saveGamesSrc.Length).TrimStart('\', '/')
            $filePlan.Add([pscustomobject]@{
                SourceFile = $_.FullName
                EntryName  = Join-Path "SaveGames" $relative
            })
        }
    }
    else {
        Write-Warning "SaveGames path not found: $saveGamesSrc"
    }

    if ($filePlan.Count -eq 0) {
        Write-Warning "No files found to back up. Aborting."
        return
    }

    if (-not $mapName) {
        Write-Warning "No map subfolder name available for zip naming. Falling back to source folder name."
        $mapName = Split-Path -Path (Resolve-Path $SourcePath) -Leaf
    }

    $zipName = "${mapName}_${timestamp}.zip"
    $zipPath = Join-Path $DestinationPath $zipName

    # ---------------------------------------------------------
    # -WhatIf: report what would happen, then stop
    # ---------------------------------------------------------
    if (-not $PSCmdlet.ShouldProcess($zipPath, "Create zip archive with $($filePlan.Count) file(s)")) {
        foreach ($item in $filePlan) {
            Write-Host "What if: Add '$($item.SourceFile)' as '$($item.EntryName)'"
        }
        return
    }

    $zipStream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::Create)
    $archive   = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)

    $total = $filePlan.Count
    $count = 0

    try {
        foreach ($item in $filePlan) {
            $count++

            if ($ShowProgress) {
                $percent = [int](($count / $total) * 100)
                Write-Progress -Activity "Backing up Ark server files" `
                    -Status "[$count / $total] $($item.EntryName)" `
                    -PercentComplete $percent
            }

            Write-Verbose "Archiving: $($item.SourceFile) -> $($item.EntryName)"

            $entryName = $item.EntryName -replace '\\', '/'
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $item.SourceFile, $entryName, [System.IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    }
    finally {
        $archive.Dispose()
        $zipStream.Dispose()

        if ($ShowProgress) {
            Write-Progress -Activity "Backing up Ark server files" -Completed
        }
    }

    Write-Host "Backup created: $zipPath ($total files)" -ForegroundColor Green
    return $zipPath
}