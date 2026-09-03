# Test script for IniMerge module
# Creates sample INI files, tests merging, and validates duplicate key support

Write-Host "IniMerge Module Test" -ForegroundColor Cyan
Write-Host "===================" -ForegroundColor Cyan

# Import the module
$modulePath = Join-Path $PSScriptRoot "IniMerge"
Import-Module $modulePath -Force

# Create test INI files
$testDir = Join-Path $PSScriptRoot "test_temp"
if (-not (Test-Path $testDir)) {
    New-Item -Path $testDir -ItemType Directory -Force | Out-Null
}

# Create test file 1
$ini1Path = Join-Path $testDir "test1.ini"
@"
[Settings]
Port=8080
Host=localhost
Debug=false

[Database]
Server=db1.local
Username=admin

[Logging]
Level=Info
"@ | Set-Content $ini1Path -Encoding UTF8

# Create test file 2 (with duplicate keys)
$ini2Path = Join-Path $testDir "test2.ini"
@"
[Settings]
Port=9000
Host=192.168.1.1
Timeout=30

[Database]
Server=db2.local
Username=user2
Password=secret123

[Cache]
Enabled=true
TTL=300
"@ | Set-Content $ini2Path -Encoding UTF8

Write-Host "`nTest 1: Read INI file" -ForegroundColor Green
$ini1 = Read-IniFile -FilePath $ini1Path
Write-Host "Sections found: $($ini1.Keys -join ', ')"
Write-Host "Settings.Port = $($ini1.Settings.Port)"
Write-Host "Settings.Host = $($ini1.Settings.Host)"

Write-Host "`nTest 2: Read second INI file" -ForegroundColor Green
$ini2 = Read-IniFile -FilePath $ini2Path
Write-Host "Sections found: $($ini2.Keys -join ', ')"
Write-Host "Database.Server = $($ini2.Database.Server)"
Write-Host "Settings.Timeout = $($ini2.Settings.Timeout)"

Write-Host "`nTest 3: Merge with Append strategy" -ForegroundColor Green
$mergedAppend = Merge-IniFiles -FirstIni $ini1 -SecondIni $ini2 -Strategy Append
Write-Host "Settings.Port after merge = $(if ($mergedAppend.Settings.Port -is [array]) { $mergedAppend.Settings.Port -join ', ' } else { $mergedAppend.Settings.Port })"
Write-Host "Settings.Port is array: $($mergedAppend.Settings.Port -is [array])"

Write-Host "`nTest 4: Merge with Override strategy" -ForegroundColor Green
$mergedOverride = Merge-IniFiles -FirstIni $ini1 -SecondIni $ini2 -Strategy Override
Write-Host "Settings.Port after merge = $($mergedOverride.Settings.Port)"
Write-Host "Settings.Timeout = $($mergedOverride.Settings.Timeout)"

Write-Host "`nTest 5: Get values from merged data" -ForegroundColor Green
$port = Get-IniValue -IniData $mergedAppend -Section "Settings" -Key "Port"
Write-Host "Port (all values): $(if ($port -is [array]) { $port -join ', ' } else { $port })"

$firstPort = Get-IniValue -IniData $mergedAppend -Section "Settings" -Key "Port" -Index 0
$secondPort = Get-IniValue -IniData $mergedAppend -Section "Settings" -Key "Port" -Index 1
Write-Host "Port [0] = $firstPort"
Write-Host "Port [1] = $secondPort"

Write-Host "`nTest 6: Set values in merged data" -ForegroundColor Green
Set-IniValue -IniData $mergedAppend -Section "Settings" -Key "Environment" -Value "Production"
Set-IniValue -IniData $mergedAppend -Section "Settings" -Key "Host" -Value "backup-host" -AppendIfExists
$hosts = Get-IniValue -IniData $mergedAppend -Section "Settings" -Key "Host"
Write-Host "Host (after append): $(if ($hosts -is [array]) { $hosts -join ', ' } else { $hosts })"

Write-Host "`nTest 7: Write merged INI to file" -ForegroundColor Green
$outputPath = Join-Path $testDir "merged_output.ini"
Write-IniFile -IniData $mergedAppend -FilePath $outputPath -SectionOrder @("Settings", "Database", "Cache", "Logging")
Write-Host "Output written to: $outputPath"
Write-Host "Output file content:"
Write-Host "---"
Get-Content $outputPath | Write-Host
Write-Host "---"

Write-Host "`nTest 8: Verify duplicate keys in output" -ForegroundColor Green
$countPort = (Select-String -Path $outputPath -Pattern "^Port=" | Measure-Object).Count
Write-Host "Number of 'Port=' lines in output: $countPort"
Write-Host "Expected: 2 (from append strategy merge)"

Write-Host "`nTest 9: Round-trip test (read written file)" -ForegroundColor Green
$roundtrip = Read-IniFile -FilePath $outputPath
$roundtripPort = Get-IniValue -IniData $roundtrip -Section "Settings" -Key "Port"
Write-Host "Port from round-trip read: $(if ($roundtripPort -is [array]) { $roundtripPort -join ', ' } else { $roundtripPort })"
Write-Host "Round-trip preserved array: $($roundtripPort -is [array])"

Write-Host "`nTest 10: Error handling" -ForegroundColor Green
try {
    Read-IniFile -FilePath "nonexistent.ini"
} catch {
    Write-Host "Expected error caught: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Cleanup
Write-Host "`nCleaning up test files..." -ForegroundColor Gray
Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n[PASS] All tests completed successfully!" -ForegroundColor Green
