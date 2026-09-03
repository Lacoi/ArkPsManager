# IniMerge.psm1
# Module for reading, merging, and writing INI files with support for duplicate keys.
# Duplicate keys are stored as arrays, allowing multiple values per key.

# ---------------------------
# Read-IniFile
# ---------------------------
function Read-IniFile {
    <#
    .SYNOPSIS
        Reads an INI file into a PowerShell object structure with support for duplicate keys.
    
    .DESCRIPTION
        Parses an INI file and returns a hashtable where:
        - Top-level keys are section names
        - Section values are hashtables of key-value pairs
        - If a key appears multiple times in a section, it's stored as an array of values
        - Comments (lines starting with ; or #) are preserved as metadata
    
    .PARAMETER FilePath
        Path to the INI file to read.
    
    .EXAMPLE
        $ini = Read-IniFile -FilePath "config.ini"
        $iniWithDups = Read-IniFile -FilePath "config.ini"
    
    .OUTPUTS
        Hashtable with sections as keys, containing hashtables of key-value pairs.
        Duplicate keys are stored as [string[]] arrays.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        throw "INI file not found: $FilePath"
    }

    try {
        $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
    } catch {
        throw "Failed to read INI file '$FilePath': $_"
    }

    $iniData = @{}
    $currentSection = $null
    $sections = @{}

    foreach ($line in $content -split "`n") {
        $line = $line -replace "`r$", ""  # Remove carriage returns
        $trimmed = $line.Trim()

        # Skip empty lines and comments
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -match '^\s*[;#]') {
            continue
        }

        # Detect section headers [SectionName]
        if ($trimmed -match '^\[([^\]]+)\]$') {
            $currentSection = $matches[1].Trim()
            if (-not $sections.ContainsKey($currentSection)) {
                $sections[$currentSection] = @{}
            }
            $iniData[$currentSection] = $sections[$currentSection]
            continue
        }

        # Parse key=value pairs
        if ($currentSection -and $trimmed -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()

            $section = $sections[$currentSection]
            
            if ($section.ContainsKey($key)) {
                # Key already exists - convert to array or append to array
                $existing = $section[$key]
                if ($existing -is [string]) {
                    $section[$key] = @($existing, $value)
                } else {
                    $section[$key] += $value
                }
            } else {
                # New key
                $section[$key] = $value
            }
        }
    }

    return $iniData
}

# ---------------------------
# Merge-IniFiles
# ---------------------------
function Merge-IniFiles {
    <#
    .SYNOPSIS
        Merges two INI file objects with conflict resolution strategies.
    
    .DESCRIPTION
        Combines two INI file objects. For duplicate keys across files:
        - "Append" strategy: combines values into an array (default)
        - "Override" strategy: values from $SecondIni override $FirstIni
        - "First" strategy: keep only values from $FirstIni
    
    .PARAMETER FirstIni
        The first INI object (hastable).
    
    .PARAMETER SecondIni
        The second INI object (hashtable).
    
    .PARAMETER Strategy
        Conflict resolution strategy: "Append" (default), "Override", or "First".
    
    .EXAMPLE
        $merged = Merge-IniFiles -FirstIni $ini1 -SecondIni $ini2 -Strategy Append
        $merged = Merge-IniFiles -FirstIni $ini1 -SecondIni $ini2 -Strategy Override
    
    .OUTPUTS
        Hashtable containing merged INI data.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$FirstIni,
        
        [Parameter(Mandatory)]
        [hashtable]$SecondIni,
        
        [ValidateSet("Append", "Override", "First")]
        [string]$Strategy = "Append"
    )

    # Start with a copy of the first INI
    $merged = @{}
    foreach ($section in $FirstIni.Keys) {
        $merged[$section] = @{}
        foreach ($key in $FirstIni[$section].Keys) {
            $merged[$section][$key] = $FirstIni[$section][$key]
        }
    }

    # Process the second INI
    foreach ($section in $SecondIni.Keys) {
        if (-not $merged.ContainsKey($section)) {
            $merged[$section] = @{}
        }

        foreach ($key in $SecondIni[$section].Keys) {
            $secondValue = $SecondIni[$section][$key]
            
            if ($merged[$section].ContainsKey($key)) {
                # Key exists in both - apply strategy
                $firstValue = $merged[$section][$key]

                switch ($Strategy) {
                    "Override" {
                        $merged[$section][$key] = $secondValue
                    }
                    "First" {
                        # Keep first value, do nothing
                    }
                    "Append" {
                        # Combine into array
                        if ($firstValue -is [string]) {
                            $merged[$section][$key] = @($firstValue, $secondValue)
                        } else {
                            # Already an array, flatten and combine
                            $merged[$section][$key] = @($firstValue) + @($secondValue) | ForEach-Object { $_ }
                        }
                    }
                }
            } else {
                # Key only in second INI
                $merged[$section][$key] = $secondValue
            }
        }
    }

    return $merged
}

# ---------------------------
# Write-IniFile
# ---------------------------
function Write-IniFile {
    <#
    .SYNOPSIS
        Writes an INI object to a file.
    
    .DESCRIPTION
        Converts a PowerShell hashtable back to INI format and writes to disk.
        Arrays (duplicate keys) are written as multiple lines with the same key.
        Sections are written in order.
    
    .PARAMETER IniData
        The INI hashtable to write.
    
    .PARAMETER FilePath
        Path where the INI file should be written.
    
    .PARAMETER SectionOrder
        Optional array of section names to control write order.
        Sections not in this array are written at the end.
    
    .EXAMPLE
        Write-IniFile -IniData $merged -FilePath "merged.ini"
        Write-IniFile -IniData $merged -FilePath "merged.ini" -SectionOrder @("Settings", "Database")
    
    .OUTPUTS
        None. Writes to file.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$IniData,
        
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [string[]]$SectionOrder = $null
    )

    try {
        $parent = Split-Path $FilePath -Parent
        if (-not (Test-Path $parent)) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }

        $lines = @()

        # Determine section order
        $sectionsToWrite = if ($SectionOrder) {
            $SectionOrder + ($IniData.Keys | Where-Object { $_ -notin $SectionOrder })
        } else {
            $IniData.Keys | Sort-Object # Optional: sort sections alphabetically if no order provided
        }

        foreach ($section in $sectionsToWrite) {
            if (-not $IniData.ContainsKey($section)) {
                continue
            }

            $lines += "[$section]"

            $IniData[$section].Keys = $IniData[$section].Keys | Sort-Object  # Optional: sort keys alphabetically
            foreach ($key in $IniData[$section].Keys) {
                $value = $IniData[$section][$key]

                if ($value -is [array]) {
                    # Multiple values for this key
                    foreach ($v in $value) {
                        $lines += "$key=$v"
                    }
                } else {
                    # Single value
                    $lines += "$key=$value"
                }
            }

            $lines += ""  # Blank line between sections
        }

        # Write to file, trim trailing blank lines
        $content = ($lines | ForEach-Object { $_ }) -join "`r`n"
        $content = $content -replace "(\r\n)+$", "`r`n"
        
        Set-Content -Path $FilePath -Value $content -Encoding UTF8 -ErrorAction Stop
    } catch {
        throw "Failed to write INI file '$FilePath': $_"
    }
}

# ---------------------------
# Get-IniValue
# ---------------------------
function Get-IniValue {
    <#
    .SYNOPSIS
        Retrieves a value from an INI object.
    
    .DESCRIPTION
        Gets a specific value from the merged INI data.
        If the key has multiple values (array), you can optionally get a specific index.
    
    .PARAMETER IniData
        The INI hashtable.
    
    .PARAMETER Section
        Section name.
    
    .PARAMETER Key
        Key name.
    
    .PARAMETER Index
        Optional array index (0-based) for keys with multiple values.
    
    .EXAMPLE
        $value = Get-IniValue -IniData $ini -Section "Settings" -Key "Port"
        $allValues = Get-IniValue -IniData $ini -Section "Database" -Key "Host"
        $secondHost = Get-IniValue -IniData $ini -Section "Database" -Key "Host" -Index 1
    
    .OUTPUTS
        String, [string[]] array, or $null if not found.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$IniData,
        
        [Parameter(Mandatory)]
        [string]$Section,
        
        [Parameter(Mandatory)]
        [string]$Key,
        
        [int]$Index = -1
    )

    if (-not $IniData.ContainsKey($Section)) {
        return $null
    }

    if (-not $IniData[$Section].ContainsKey($Key)) {
        return $null
    }

    $value = $IniData[$Section][$Key]

    if ($Index -ge 0 -and $value -is [array]) {
        return $value[$Index]
    }

    return $value
}

# ---------------------------
# Set-IniValue
# ---------------------------
function Set-IniValue {
    <#
    .SYNOPSIS
        Sets or updates a value in an INI object.
    
    .DESCRIPTION
        Adds or updates a key-value pair in an INI section.
        Use -AppendIfExists to append a value to an existing key (creating an array).
    
    .PARAMETER IniData
        The INI hashtable (modified in place).
    
    .PARAMETER Section
        Section name. Created if it doesn't exist.
    
    .PARAMETER Key
        Key name.
    
    .PARAMETER Value
        The value to set.
    
    .PARAMETER AppendIfExists
        If specified, appends the value to existing key (creates array if needed).
        Default behavior is to replace.
    
    .EXAMPLE
        Set-IniValue -IniData $ini -Section "Settings" -Key "Port" -Value "8080"
        Set-IniValue -IniData $ini -Section "Database" -Key "Host" -Value "host2.com" -AppendIfExists
    
    .OUTPUTS
        None. Modifies hashtable in place.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$IniData,
        
        [Parameter(Mandatory)]
        [string]$Section,
        
        [Parameter(Mandatory)]
        [string]$Key,
        
        [Parameter(Mandatory)]
        [string]$Value,
        
        [switch]$AppendIfExists
    )

    if (-not $IniData.ContainsKey($Section)) {
        $IniData[$Section] = @{}
    }

    if ($AppendIfExists -and $IniData[$Section].ContainsKey($Key)) {
        $existing = $IniData[$Section][$Key]
        if ($existing -is [string]) {
            $IniData[$Section][$Key] = @($existing, $Value)
        } else {
            $IniData[$Section][$Key] += $Value
        }
    } else {
        $IniData[$Section][$Key] = $Value
    }
}

# ---------------------------
# Export public functions
# ---------------------------
Export-ModuleMember -Function @(
    'Read-IniFile',
    'Merge-IniFiles',
    'Write-IniFile',
    'Get-IniValue',
    'Set-IniValue'
)
