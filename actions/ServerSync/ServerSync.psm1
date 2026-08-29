# ServerSync.psm1
# Folder-sync helpers, imported via: Import-Module (Join-Path $PSScriptRoot "ServerSync") -Force

function Sync-Folder {
    <#
    .SYNOPSIS
        Copies new and changed files from a source folder to a target folder.

    .DESCRIPTION
        Sync-Folder walks -SourcePath and copies any file that is new or has
        changed onto -TargetPath, creating folders as needed.

        -ExcludeFilter protects matching items on the TARGET side: anything
        that matches is never overwritten, and (with -Mirror) never deleted,
        even if it no longer exists in the source. Use it for target-only
        content - logs, local config, a .git folder - that should survive
        the sync untouched.

    .PARAMETER SourcePath
        Folder to copy from. Must already exist.

    .PARAMETER TargetPath
        Folder to copy to. Created automatically if it doesn't exist.

    .PARAMETER ExcludeFilter
        Wildcard patterns (e.g. '*.log', '.git', 'cache\temp') describing
        files/folders on the target to leave alone. Each pattern is checked
        against the item's full relative path, its own name, and every
        individual path segment - so 'node_modules' protects that folder
        wherever it sits, while 'cache\temp' only protects that one path.

    .PARAMETER Mirror
        After copying, also delete anything in the target that no longer
        exists in the source - except items matched by -ExcludeFilter.
        Without -Mirror, the target only ever gains or updates files.

    .PARAMETER CompareMethod
        'DateSize' (default) flags a file as changed when its LastWriteTime
        or Length differs - fast, fine for most cases.
        'Hash' compares SHA256 content hashes instead - slower, but also
        catches edits that don't change size or land in the same second.

    .EXAMPLE
        Sync-Folder -SourcePath C:\Data\Source -TargetPath D:\Backup\Target `
            -ExcludeFilter '*.log', '.git', 'cache\temp' -Mirror -WhatIf

        Previews a mirrored sync without changing anything.

    .EXAMPLE
        Sync-Folder C:\Projects\App D:\Deploy\App `
            -ExcludeFilter 'appsettings.local.json', 'logs' -Mirror -Verbose

        Syncs App into Deploy\App and removes orphaned files, but always
        leaves appsettings.local.json and the logs folder untouched.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$SourcePath,

        [Parameter(Mandatory, Position = 1)]
        [string]$TargetPath,

        [string[]]$ExcludeFilter = @(),

        [switch]$Mirror,

        [ValidateSet('DateSize', 'Hash')]
        [string]$CompareMethod = 'DateSize'
    )

    # --- Resolve paths -----------------------------------------------------
    $Source = (Resolve-Path -LiteralPath $SourcePath).ProviderPath.TrimEnd('\', '/')

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($TargetPath, 'Create target folder')) {
            New-Item -Path $TargetPath -ItemType Directory -Force | Out-Null
        }
    }
    $Target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TargetPath).TrimEnd('\', '/')

    $sep = [System.IO.Path]::DirectorySeparatorChar
    if ($Target.Equals($Source, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'SourcePath and TargetPath resolve to the same folder.'
    }
    if ($Target.StartsWith("$Source$sep", [System.StringComparison]::OrdinalIgnoreCase) -or
        $Source.StartsWith("$Target$sep", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'TargetPath cannot be nested inside SourcePath, or vice versa.'
    }

    # --- Helper: does a target-relative path match the exclude filter? -----
    function Test-SyncExcluded {
        param([string]$RelativePath, [string[]]$Patterns)

        if (-not $Patterns -or $Patterns.Count -eq 0) { return $false }

        $leaf = Split-Path -Path $RelativePath -Leaf
        $segments = $RelativePath -split '[\\/]'

        foreach ($pattern in $Patterns) {
            if ($RelativePath -like $pattern) { return $true }
            if ($leaf -like $pattern) { return $true }
            foreach ($segment in $segments) {
                if ($segment -like $pattern) { return $true }
            }
        }
        return $false
    }

    $result = [ordered]@{
        Copied    = 0
        Updated   = 0
        Unchanged = 0
        Excluded  = 0
        Deleted   = 0
        Errors    = 0
    }

    # --- Recreate the source's folder structure on the target --------------
    $sourceDirs = Get-ChildItem -LiteralPath $Source -Recurse -Directory -Force -ErrorAction SilentlyContinue
    foreach ($dir in $sourceDirs) {
        $relativePath = $dir.FullName.Substring($Source.Length).TrimStart('\', '/')
        if (Test-SyncExcluded -RelativePath $relativePath -Patterns $ExcludeFilter) { continue }

        $destDir = Join-Path $Target $relativePath
        if (-not (Test-Path -LiteralPath $destDir)) {
            if ($PSCmdlet.ShouldProcess($destDir, 'Create folder')) {
                New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            }
        }
    }

    # --- Copy new / changed files --------------------------------------------
    $sourceFiles = Get-ChildItem -LiteralPath $Source -Recurse -File -Force -ErrorAction SilentlyContinue
    $sourceRelativePaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($file in $sourceFiles) {
        $relativePath = $file.FullName.Substring($Source.Length).TrimStart('\', '/')
        [void]$sourceRelativePaths.Add($relativePath)

        if (Test-SyncExcluded -RelativePath $relativePath -Patterns $ExcludeFilter) {
            $result.Excluded++
            Write-Verbose "Excluded (protected on target): $relativePath"
            continue
        }

        $destPath = Join-Path $Target $relativePath
        $needsCopy = $false
        $reason = $null

        if (-not (Test-Path -LiteralPath $destPath)) {
            $needsCopy = $true
            $reason = 'new'
        }
        else {
            $destItem = Get-Item -LiteralPath $destPath
            if ($CompareMethod -eq 'Hash') {
                $sourceHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
                $destHash = (Get-FileHash -LiteralPath $destPath -Algorithm SHA256).Hash
                if ($sourceHash -ne $destHash) {
                    $needsCopy = $true
                    $reason = 'changed'
                }
            }
            elseif ($file.LastWriteTimeUtc -gt $destItem.LastWriteTimeUtc -or $file.Length -ne $destItem.Length) {
                $needsCopy = $true
                $reason = 'changed'
            }
        }

        if ($needsCopy) {
            if ($PSCmdlet.ShouldProcess($destPath, "Copy ($reason)")) {
                try {
                    Copy-Item -LiteralPath $file.FullName -Destination $destPath -Force
                    Write-Verbose "Synced ($reason): $relativePath"
                    if ($reason -eq 'new') { $result.Copied++ } else { $result.Updated++ }
                }
                catch {
                    Write-Warning "Failed to copy '$relativePath': $($_.Exception.Message)"
                    $result.Errors++
                }
            }
        }
        else {
            $result.Unchanged++
        }
    }

    # --- Mirror: remove target items no longer present in source -----------
    if ($Mirror) {
        $targetFiles = Get-ChildItem -LiteralPath $Target -Recurse -File -Force -ErrorAction SilentlyContinue
        foreach ($file in $targetFiles) {
            $relativePath = $file.FullName.Substring($Target.Length).TrimStart('\', '/')

            if (Test-SyncExcluded -RelativePath $relativePath -Patterns $ExcludeFilter) { continue }
            if ($sourceRelativePaths.Contains($relativePath)) { continue }

            if ($PSCmdlet.ShouldProcess($file.FullName, 'Delete (not present in source)')) {
                try {
                    Remove-Item -LiteralPath $file.FullName -Force
                    Write-Verbose "Deleted (orphaned): $relativePath"
                    $result.Deleted++
                }
                catch {
                    Write-Warning "Failed to delete '$relativePath': $($_.Exception.Message)"
                    $result.Errors++
                }
            }
        }

        # Remove folders left empty by the deletions above (deepest first).
        #$targetDirs = Get-ChildItem -LiteralPath $Target -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        #    Sort-Object { $_.FullName.Length } -Descending

        #foreach ($dir in $targetDirs) {
        #    $relativePath = $dir.FullName.Substring($Target.Length).TrimStart('\', '/')
        #    if (Test-SyncExcluded -RelativePath $relativePath -Patterns $ExcludeFilter) { continue }

        #    $hasContent = Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue |
        #        Select-Object -First 1
        #    if (-not $hasContent) {
        #        if ($PSCmdlet.ShouldProcess($dir.FullName, 'Remove empty folder')) {
        #            Remove-Item -LiteralPath $dir.FullName -Force
        #        }
        #    }
        #}
    }

    [PSCustomObject]@{
        Source    = $Source
        Target    = $Target
        Copied    = $result.Copied
        Updated   = $result.Updated
        Unchanged = $result.Unchanged
        Excluded  = $result.Excluded
        Deleted   = $result.Deleted
        Errors    = $result.Errors
    }
}

Function Update-Server {
    param
    (
        [Parameter(Mandatory=$true)][string]$TargetPath
    )

    $toIgnore = @(
        "Engine\Saved\*"
        "Engine\Programs\CrashReportClient\Saved\*",
        "ShooterGame\.sentry-native\*",
        "ShooterGame\Binaries\Win64\ArkApi\*",
        "ShooterGame\Binaries\Win64\config\config.vdf",
        "ShooterGame\Binaries\Win64\logs\*",
        "ShooterGame\Binaries\Win64\ShooterGame\*",
        "ShooterGame\Binaries\Win64\PlayersExclusiveJoinList.txt",
        "ShooterGame\Binaries\Win64\PlayersJoinNoCheckList.txt",
        "ShooterGame\Saved\*",
        "ShooterGame\Binaries\Win64\AsaApiLoader.exe",
        "ShooterGame\Binaries\Win64\AsaApiLoader.pdb",
        "ShooterGame\Binaries\Win64\config.json",
        "ShooterGame\Binaries\Win64\libcrypto-3-x64.dll",
        "ShooterGame\Binaries\Win64\libssl-3-x64.dll",
        "ShooterGame\Binaries\Win64\msdia140.dll"
    )

    if (Test-Path (Join-Path $PSScriptRoot "..\..\Cache\Server")) {
        Sync-Folder -SourcePath (Join-Path $PSScriptRoot "..\..\Cache\Server") -TargetPath $TargetPath -ExcludeFilter $toIgnore -Mirror -CompareMethod "DateSize" -Verbose #-WhatIf
    } else {
        Write-Warning "Cache folder not found. Please run the 'UpdateCache' action first."
    }
}