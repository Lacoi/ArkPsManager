# Example: Using the IniMerge module
# This demonstrates how to merge INI files with duplicate key support.

# Import the module
Import-Module (Join-Path $PSScriptRoot "IniMerge") -Force

# Example 1: Read two INI files
$ini1 = Read-IniFile -FilePath ".\config1.ini"
$ini2 = Read-IniFile -FilePath ".\config2.ini"

# Example 2: Merge with different strategies

# Strategy 1: Append (default) - duplicate keys become arrays
$mergedAppend = Merge-IniFiles -FirstIni $ini1 -SecondIni $ini2 -Strategy Append
Write-Host "Merged (Append strategy):"
Write-Host $mergedAppend

# Strategy 2: Override - second file wins conflicts
$mergedOverride = Merge-IniFiles -FirstIni $ini1 -SecondIni $ini2 -Strategy Override
Write-Host "Merged (Override strategy):"
Write-Host $mergedOverride

# Strategy 3: First - first file wins conflicts
$mergedFirst = Merge-IniFiles -FirstIni $ini1 -SecondIni $ini2 -Strategy First
Write-Host "Merged (First strategy):"
Write-Host $mergedFirst

# Example 3: Get values from merged INI
$singleValue = Get-IniValue -IniData $mergedAppend -Section "Settings" -Key "Port"
$allValues = Get-IniValue -IniData $mergedAppend -Section "Database" -Key "Host"  # May be array
$secondValue = Get-IniValue -IniData $mergedAppend -Section "Database" -Key "Host" -Index 1

Write-Host "Port value: $singleValue"
Write-Host "Host values: $allValues"
Write-Host "Second host: $secondValue"

# Example 4: Modify merged data and write back
Set-IniValue -IniData $mergedAppend -Section "Settings" -Key "Debug" -Value "true"
Set-IniValue -IniData $mergedAppend -Section "Logging" -Key "Path" -Value "C:\Logs" -AppendIfExists

# Example 5: Write merged INI to file
Write-IniFile -IniData $mergedAppend -FilePath ".\merged_output.ini" -SectionOrder @("Settings", "Database", "Logging")

Write-Host "Merged INI written to merged_output.ini"
