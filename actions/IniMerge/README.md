# IniMerge Module

A PowerShell module for reading, merging, and writing INI files with full support for duplicate keys.

## Features

- **Read INI files** with automatic duplicate key detection and array storage
- **Merge INI files** with three conflict resolution strategies:
  - `Append`: Combine duplicate keys into arrays (default)
  - `Override`: Second file's values win conflicts
  - `First`: First file's values win conflicts
- **Write merged INI** back to disk with optional section ordering
- **Modify INI data** programmatically with `Get-IniValue` and `Set-IniValue`
- **Duplicate key support**: Keys with multiple values stored as `[string[]]` arrays

## Installation

The module is located in `actions/IniMerge/` directory:
```powershell
Import-Module (Join-Path $PSScriptRoot "IniMerge") -Force
```

## Usage

### Read an INI File

```powershell
$ini = Read-IniFile -FilePath "config.ini"
```

The returned object is a hashtable where:
- Top-level keys = section names
- Section values = hashtables of key-value pairs
- **Duplicate keys** = stored as `[string[]]` arrays

**Example file:**
```ini
[Settings]
Port=8080
Host=localhost
Host=127.0.0.1

[Database]
ConnectionString=Server=db1;Database=main
ConnectionString=Server=db2;Database=backup
```

**Read result:**
```powershell
@{
    Settings = @{
        Port = "8080"
        Host = @("localhost", "127.0.0.1")  # Array due to duplicate keys
    }
    Database = @{
        ConnectionString = @("Server=db1;...", "Server=db2;...")  # Array
    }
}
```

### Merge Two INI Files

```powershell
$ini1 = Read-IniFile -FilePath "config1.ini"
$ini2 = Read-IniFile -FilePath "config2.ini"

# Strategy 1: Append (default) - duplicates become arrays
$merged = Merge-IniFiles -FirstIni $ini1 -SecondIni $ini2 -Strategy Append

# Strategy 2: Override - second file wins
$merged = Merge-IniFiles -FirstIni $ini1 -SecondIni $ini2 -Strategy Override

# Strategy 3: First - first file wins
$merged = Merge-IniFiles -FirstIni $ini1 -SecondIni $ini2 -Strategy First
```

**Example with conflicts:**

config1.ini:
```ini
[Settings]
Port=8080
Debug=false
```

config2.ini:
```ini
[Settings]
Port=9000
Timeout=30
```

**Result (Append strategy):**
```
@{
    Settings = @{
        Port = @("8080", "9000")    # Both values!
        Debug = "false"
        Timeout = "30"
    }
}
```

**Result (Override strategy):**
```
@{
    Settings = @{
        Port = "9000"               # config2 wins
        Debug = "false"
        Timeout = "30"
    }
}
```

### Get Values

```powershell
# Get single value
$port = Get-IniValue -IniData $ini -Section "Settings" -Key "Port"
# Result: "8080"

# Get all values (may be array)
$hosts = Get-IniValue -IniData $ini -Section "Settings" -Key "Host"
# Result: @("localhost", "127.0.0.1")

# Get specific array index
$secondHost = Get-IniValue -IniData $ini -Section "Settings" -Key "Host" -Index 1
# Result: "127.0.0.1"
```

### Set Values

```powershell
# Set a new value (or replace existing)
Set-IniValue -IniData $ini -Section "Settings" -Key "Port" -Value "8080"

# Append to a key (creates array if needed)
Set-IniValue -IniData $ini -Section "Settings" -Key "Host" -Value "192.168.1.1" -AppendIfExists
# If Host was "localhost", becomes @("localhost", "192.168.1.1")
```

### Write Merged INI

```powershell
# Write to file
Write-IniFile -IniData $merged -FilePath "merged.ini"

# Write with specific section order
Write-IniFile -IniData $merged -FilePath "merged.ini" -SectionOrder @("Settings", "Database", "Logging")
```

**Output format** (merged.ini):
```ini
[Settings]
Port=8080
Port=9000
Debug=false
Timeout=30

[Database]
Host=localhost
Host=127.0.0.1

```

Note: Duplicate keys appear as separate lines, maintaining the multi-value nature.

## API Reference

### Read-IniFile
```powershell
Read-IniFile -FilePath <string>
```
Reads an INI file and returns a hashtable with duplicate key support.

### Merge-IniFiles
```powershell
Merge-IniFiles -FirstIni <hashtable> -SecondIni <hashtable> [-Strategy <"Append"|"Override"|"First">]
```
Merges two INI objects. Default strategy is "Append".

### Write-IniFile
```powershell
Write-IniFile -IniData <hashtable> -FilePath <string> [-SectionOrder <string[]>]
```
Writes INI data to a file. Optional section order controls output order.

### Get-IniValue
```powershell
Get-IniValue -IniData <hashtable> -Section <string> -Key <string> [-Index <int>]
```
Retrieves a value. Optional -Index for array values.

### Set-IniValue
```powershell
Set-IniValue -IniData <hashtable> -Section <string> -Key <string> -Value <string> [-AppendIfExists]
```
Sets/updates a value. Use -AppendIfExists to create arrays.

## Duplicate Key Behavior

When reading an INI file:
- **First occurrence** of a key: stored as a string
- **Second occurrence** of the same key: converted to a `[string[]]` array
- **Subsequent occurrences**: appended to the array

Example:
```ini
[Section]
Key=Value1
Key=Value2
Key=Value3
```

Result: `Key = @("Value1", "Value2", "Value3")`

This allows seamless handling of configuration files where multiple values for the same key are valid (e.g., multiple connection strings, multiple servers, etc.).

## Examples

See `Example.ps1` for complete working examples.

## Error Handling

All functions include try-catch blocks with descriptive error messages:

```powershell
try {
    $ini = Read-IniFile -FilePath "nonexistent.ini"
} catch {
    Write-Error $_  # "INI file not found: ..."
}
```

## Notes

- INI files are read with UTF-8 encoding
- Comments (lines starting with `;` or `#`) are automatically skipped
- Empty lines are ignored during read
- Output files use `\r\n` (CRLF) line endings for Windows compatibility
- Sections and keys are case-sensitive (as per INI standard)
