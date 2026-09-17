# Proxy action: runs one of the per-key action scripts (Start/Stop/Restart/Kill/Backup/Update)
# for a list of server Keys, either Sequential (one after another) or Parallel (all at once).
# Intended for Task Scheduler / CLI use, e.g. running "Backup" for every server in one scheduled task.
param(
    [Parameter(Mandatory)]
    [ValidateSet("Start", "Stop", "Restart", "Kill", "Backup", "Update")]
    [string]$ActionName,

    [Parameter(Mandatory)]
    [string[]]$Keys,

    [ValidateSet("Sequential", "Parallel")]
    [string]$Mode = "Sequential",

    [string]$ConfigJsonPath = (Get-Item $PSScriptRoot ).Parent.FullName + "\config.json"
)

$scriptPath = Join-Path $PSScriptRoot "$ActionName.ps1"
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    Write-Error "Action script not found: $scriptPath"
    exit 1
}

# Start actions are staggered by GlobalSettings.Startup.Delay to avoid every server starting at once
$startupDelay = 0
if ($ActionName -eq "Start") {
    $config = Get-Content $ConfigJsonPath -Raw | ConvertFrom-Json
    $startupDelay = [Math]::Max(0, [int]$config.GlobalSettings.Startup.Delay)
}

Write-Host "=== RunAction: $ActionName for [$($Keys -join ', ')] ($Mode) ==="

$failedKeys = @()

if ($Mode -eq "Sequential") {
    for ($i = 0; $i -lt $Keys.Count; $i++) {
        $key = $Keys[$i]
        Write-Host "--- $ActionName : $key ---"
        try {
            & $scriptPath -Key $key -ConfigJsonPath $ConfigJsonPath
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "$ActionName failed for '$key' (exit code $LASTEXITCODE)."
                $failedKeys += $key
            }
        } catch {
            Write-Warning "$ActionName failed for '$key': $_"
            $failedKeys += $key
        }
        if ($startupDelay -gt 0 -and $i -lt $Keys.Count - 1) {
            Write-Host "Waiting $startupDelay second(s) (Startup.Delay) before starting the next server..."
            Start-Sleep -Seconds $startupDelay
        }
    }
} else {
    $procsByKey = @{}
    for ($i = 0; $i -lt $Keys.Count; $i++) {
        $key = $Keys[$i]
        $argList = @(
            "-ExecutionPolicy", "Bypass"
            "-File", "`"$scriptPath`""
            "-Key", "`"$key`""
            "-ConfigJsonPath", "`"$ConfigJsonPath`""
        )
        Write-Host "--- Launching $ActionName : $key ---"
        $procsByKey[$key] = Start-Process -FilePath "pwsh.exe" -ArgumentList $argList -WindowStyle Hidden -PassThru
        if ($startupDelay -gt 0 -and $i -lt $Keys.Count - 1) {
            Write-Host "Waiting $startupDelay second(s) (Startup.Delay) before launching the next server..."
            Start-Sleep -Seconds $startupDelay
        }
    }

    Write-Host "Waiting for $($procsByKey.Count) '$ActionName' process(es) to finish..."
    $procsByKey.Values | Wait-Process

    foreach ($key in $procsByKey.Keys) {
        $exitCode = $procsByKey[$key].ExitCode
        if ($exitCode -ne 0) {
            Write-Warning "$ActionName failed for '$key' (exit code $exitCode)."
            $failedKeys += $key
        }
    }
}

if ($failedKeys.Count -gt 0) {
    Write-Host "=== RunAction: $ActionName complete - failed for: $($failedKeys -join ', ') ==="
    exit 1
}

Write-Host "=== RunAction: $ActionName complete - all $($Keys.Count) key(s) succeeded ==="
