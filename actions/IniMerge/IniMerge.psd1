@{
    RootModule        = 'IniMerge.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-47a8-b9c0-d1e2f3a4b5c6'
    Author            = 'ServerManager'
    Description       = 'Module for merging INI files with support for duplicate keys'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Read-IniFile',
        'Merge-IniFiles',
        'Write-IniFile',
        'Get-IniValue',
        'Set-IniValue'
    )
    PrivateData = @{
        PSData = @{
            Tags = @('INI', 'Merge', 'Config')
        }
    }
}
