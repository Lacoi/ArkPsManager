# ServerBackup.psm1
# Server Backup helpers, imported via: Import-Module (Join-Path $PSScriptRoot "ServerBackup") -Force

function Invoke-BackupLog {
    param(
        [scriptblock]$LogAction,
        [string]$Message
    )

    if ($null -ne $LogAction) {
        & $LogAction $Message
    }
}

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
        [switch]$ShowProgress,        # Display a Write-Progress bar while archiving

        [Parameter(Mandatory = $false)]
        [scriptblock]$LogAction
    )

    if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
        throw "Destination path is not specified."
    }

    if (-not (Test-Path $SourcePath)) {
        throw "Source path '$SourcePath' does not exist."
    }

    Invoke-BackupLog -LogAction $LogAction -Message "Starting backup from '$SourcePath' to '$DestinationPath'."

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
        $message = "WindowsServer config path not found: $configSrc"
        Write-Warning $message
        Invoke-BackupLog -LogAction $LogAction -Message $message
    }

    $savedArksSrc = Join-Path $SourcePath "ShooterGame\Saved\SavedArks"
    if (Test-Path $savedArksSrc) {
        $mapSubFolder = Get-ChildItem -Path $savedArksSrc -Directory | Select-Object -First 1

        if ($null -ne $mapSubFolder) {
            $mapName   = $mapSubFolder.Name
            $entryRoot = "SavedArks\$mapName"

            # -Include only takes effect when -Path points at a container's contents (trailing '\*')
            $extensionPatterns = $ArkExtensions | ForEach-Object { "*$_" }
            Get-ChildItem -Path (Join-Path $mapSubFolder.FullName '*') -Include $extensionPatterns -File -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $filePlan.Add([pscustomobject]@{
                        SourceFile = $_.FullName
                        EntryName  = Join-Path $entryRoot $_.Name
                    })
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
                $message = "Expected .ark file not found: $arkFile"
                Write-Warning $message
                Invoke-BackupLog -LogAction $LogAction -Message $message
            }
        }
        else {
            $message = "No subfolder found under SavedArks: $savedArksSrc"
            Write-Warning $message
            Invoke-BackupLog -LogAction $LogAction -Message $message
        }
    }
    else {
        $message = "SavedArks path not found: $savedArksSrc"
        Write-Warning $message
        Invoke-BackupLog -LogAction $LogAction -Message $message
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
        $message = "SaveGames path not found: $saveGamesSrc"
        Write-Warning $message
        Invoke-BackupLog -LogAction $LogAction -Message $message
    }

    if ($filePlan.Count -eq 0) {
        $message = "No files found to back up. Aborting."
        Write-Warning $message
        Invoke-BackupLog -LogAction $LogAction -Message $message
        return
    }

    if (-not $mapName) {
        Write-Warning "No map subfolder name available for zip naming. Falling back to source folder name."
        $mapName = Split-Path -Path (Resolve-Path $SourcePath) -Leaf
    }

    $zipName = "${mapName}_${timestamp}.zip"
    $zipPath = Join-Path $DestinationPath $zipName
    Invoke-BackupLog -LogAction $LogAction -Message "Creating backup archive '$zipPath' with $($filePlan.Count) file(s)."

    # ---------------------------------------------------------
    # -WhatIf: report what would happen, then stop
    # ---------------------------------------------------------
    if (-not $PSCmdlet.ShouldProcess($zipPath, "Create zip archive with $($filePlan.Count) file(s)")) {
        foreach ($item in $filePlan) {
            Write-Host "What if: Add '$($item.SourceFile)' as '$($item.EntryName)'"
            Invoke-BackupLog -LogAction $LogAction -Message "What if: Add '$($item.SourceFile)' as '$($item.EntryName)'"
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

    $message = "Backup created: $zipPath ($total files)"
    Write-Host $message -ForegroundColor Green
    Invoke-BackupLog -LogAction $LogAction -Message $message
    return $zipPath
}

# ---------------------------
# Invoke-BackupRetention
# ---------------------------
function Invoke-BackupRetention {
    <#
    .SYNOPSIS
        Prunes old Backup-ArkServer zip files using a daily + weekly retention policy.

    .DESCRIPTION
        Keeps every backup created within the last -DailyRetentionDays days. Beyond that
        window, keeps only the most recent -WeeklyBackupsToKeep Sunday backups (one per
        week, using the latest backup of each Sunday if there's more than one). Everything
        else is deleted.

        Backups are matched by the "..._yyyyMMdd_HHmmss.zip" naming used by Backup-ArkServer;
        files that don't match this pattern are left untouched.

    .PARAMETER BackupPath
        Folder containing the zip backups for a single server.

    .PARAMETER DailyRetentionDays
        Number of days of daily backups to keep (default 7).

    .PARAMETER WeeklyBackupsToKeep
        Number of additional weekly (Sunday) backups to keep beyond the daily window (default 4).

    .PARAMETER LogAction
        Optional scriptblock invoked with a single string message for logging.

    .EXAMPLE
        Invoke-BackupRetention -BackupPath 'C:\Backup\ArkAsaNew\TheIsland' -DailyRetentionDays 7 -WeeklyBackupsToKeep 4
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BackupPath,

        [Parameter(Mandatory = $false)]
        [int]$DailyRetentionDays = 7,

        [Parameter(Mandatory = $false)]
        [int]$WeeklyBackupsToKeep = 4,

        [Parameter(Mandatory = $false)]
        [scriptblock]$LogAction
    )

    if (-not (Test-Path -LiteralPath $BackupPath)) {
        Invoke-BackupLog -LogAction $LogAction -Message "Backup path not found, nothing to prune: '$BackupPath'."
        return
    }

    $backups = Get-ChildItem -LiteralPath $BackupPath -Filter '*.zip' -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            if ($_.BaseName -match '_(\d{8}_\d{6})$') {
                [pscustomobject]@{
                    File      = $_
                    Timestamp = [datetime]::ParseExact($Matches[1], 'yyyyMMdd_HHmmss', $null)
                }
            }
        } |
        Where-Object { $_ } |
        Sort-Object Timestamp -Descending

    if ($backups.Count -eq 0) {
        Invoke-BackupLog -LogAction $LogAction -Message "No timestamped backups found in '$BackupPath'."
        return
    }

    $dailyCutoff = (Get-Date).Date.AddDays(-$DailyRetentionDays)
    $keep = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Keep everything inside the daily retention window
    foreach ($backup in $backups) {
        if ($backup.Timestamp -ge $dailyCutoff) {
            [void]$keep.Add($backup.File.FullName)
        }
    }

    # Keep the N most recent distinct Sunday backups (one per week), even outside the daily window
    $weeklyCandidates = $backups |
        Where-Object { $_.Timestamp.DayOfWeek -eq [DayOfWeek]::Sunday } |
        Group-Object { $_.Timestamp.Date } |
        ForEach-Object { $_.Group | Sort-Object Timestamp -Descending | Select-Object -First 1 } |
        Sort-Object Timestamp -Descending |
        Select-Object -First $WeeklyBackupsToKeep

    foreach ($backup in $weeklyCandidates) {
        [void]$keep.Add($backup.File.FullName)
    }

    $removed = 0
    foreach ($backup in $backups) {
        if ($keep.Contains($backup.File.FullName)) { continue }

        if ($PSCmdlet.ShouldProcess($backup.File.FullName, "Remove old backup")) {
            try {
                Remove-Item -LiteralPath $backup.File.FullName -Force
                Invoke-BackupLog -LogAction $LogAction -Message "Removed old backup: $($backup.File.FullName)"
                $removed++
            } catch {
                $message = "Failed to remove old backup '$($backup.File.FullName)': $($_.Exception.Message)"
                Write-Warning $message
                Invoke-BackupLog -LogAction $LogAction -Message $message
            }
        }
    }

    Invoke-BackupLog -LogAction $LogAction -Message "Backup retention complete: kept $($keep.Count), removed $removed."
}