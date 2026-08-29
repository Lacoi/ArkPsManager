@{
    RootModule        = 'ArkRcon.psm1'
    ModuleVersion      = '1.0.0'
    GUID               = 'b3f2c1a4-6e2d-4b7a-9f1c-2d4e5f6a7b8c'
    Author             = 'Lacoi'
    CompanyName        = 'Unknown'
    Copyright          = '(c) Lacoi. All rights reserved.'
    Description        = 'PowerShell RCON client for ARK: Survival Evolved (Source RCON protocol) with persistent multi-command session support, connection-liveness checking, and retry logic.'
    PowerShellVersion  = '5.1'

    FunctionsToExport  = @(
        'New-ArkRconSession',
        'Invoke-ArkRconCommand',
        'Close-ArkRconSession'
    )
    CmdletsToExport    = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('ARK', 'RCON', 'GameServer', 'SourceRCON')
            ProjectUri = ''
        }
    }
}