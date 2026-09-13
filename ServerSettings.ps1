Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------------------
# ServerSettings.ps1
# Standalone WinForms editor for the Game.ini / GameUserSettings.ini / run.json sources under config/ini:
#   - (Global): config/ini/Base_Game.ini, config/ini/Base_GameUserSettings.ini (no Append/Override), config/ini/run.json
#   - Per server (config.json Entries[].Key): config/ini/<Key>/Game_Append.ini, Game_Override.ini,
#     GameUserSettings_Append.ini, GameUserSettings_Override.ini, config/ini/<Key>/run.json
# These are the same files CreateServerSettings.ps1 merges into config/maps/<Key>/config/*.ini and RunServer.cmd.
# Run directly: pwsh -File ServerSettings.ps1
# ---------------------------

$root = $PSScriptRoot
$iniRoot = Join-Path $root 'config\ini'
$configJsonPath = Join-Path $root 'config.json'

function Get-EntryKeys {
    if (-not (Test-Path -LiteralPath $configJsonPath -PathType Leaf)) {
        return @()
    }
    try {
        $config = Get-Content -LiteralPath $configJsonPath -Raw -ErrorAction Stop | ConvertFrom-Json
        return @($config.Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Key) } | ForEach-Object { $_.Key } | Sort-Object)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to read config.json:`n$_", "Error") | Out-Null
        return @()
    }
}

# path -> file content, populated on first access and written back on Save
$script:iniCache = @{}

function Get-IniContent {
    param([string]$Path)

    if ($script:iniCache.ContainsKey($Path)) {
        return $script:iniCache[$Path]
    }

    $content = if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    } else {
        ''
    }
    if ($null -eq $content) { $content = '' }

    $script:iniCache[$Path] = $content
    return $content
}

function Save-IniCache {
    $saved = 0
    $deleted = 0
    $errors = 0
    foreach ($path in @($script:iniCache.Keys)) {
        try {
            if ([string]::IsNullOrWhiteSpace($script:iniCache[$path])) {
                # don't create empty override/append files; remove them if they already exist
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    Remove-Item -LiteralPath $path -Force -ErrorAction Stop
                    $deleted++
                }
                continue
            }

            $parent = Split-Path -Path $path -Parent
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -Path $parent -ItemType Directory -Force | Out-Null
            }
            Set-Content -LiteralPath $path -Value $script:iniCache[$path] -Encoding UTF8 -NoNewline -ErrorAction Stop
            $saved++
        } catch {
            $errors++
            Write-Warning "Failed to save '$path': $_"
        }
    }
    return [pscustomobject]@{ Saved = $saved; Deleted = $deleted; Errors = $errors }
}

function New-IniTextBox {
    param([string]$Path)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true
    $txt.Dock = 'Fill'
    $txt.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $txt.AcceptsTab = $true
    $txt.WordWrap = $false
    $txt.Font = New-Object System.Drawing.Font('Consolas', 10)
    $txt.Tag = $Path
    $txt.Text = Get-IniContent -Path $Path
    $txt.Add_TextChanged({
        param($s, $e)
        $script:iniCache[[string]$s.Tag] = $s.Text
    })
    return $txt
}

function Add-IniTabPage {
    param(
        [System.Windows.Forms.TabControl]$TabControl,
        [string]$Title,
        [string]$Path
    )

    $page = New-Object System.Windows.Forms.TabPage
    $page.Text = $Title
    $page.Controls.Add((New-IniTextBox -Path $Path))
    $TabControl.TabPages.Add($page)
}

function Update-Editor {
    param(
        [System.Windows.Forms.TabControl]$TabControl,
        [string]$Target
    )

    $TabControl.TabPages.Clear()

    if ($Target -eq '(Global)') {
        Add-IniTabPage -TabControl $TabControl -Title 'Game.ini' -Path (Join-Path $iniRoot 'Base_Game.ini')
        Add-IniTabPage -TabControl $TabControl -Title 'GameUserSettings.ini' -Path (Join-Path $iniRoot 'Base_GameUserSettings.ini')
        Add-IniTabPage -TabControl $TabControl -Title 'run.json' -Path (Join-Path $iniRoot 'run.json')
    } else {
        $entryIniRoot = Join-Path $iniRoot $Target
        Add-IniTabPage -TabControl $TabControl -Title 'Game_Append' -Path (Join-Path $entryIniRoot 'Game_Append.ini')
        Add-IniTabPage -TabControl $TabControl -Title 'Game_Override' -Path (Join-Path $entryIniRoot 'Game_Override.ini')
        Add-IniTabPage -TabControl $TabControl -Title 'GameUserSettings_Append' -Path (Join-Path $entryIniRoot 'GameUserSettings_Append.ini')
        Add-IniTabPage -TabControl $TabControl -Title 'GameUserSettings_Override' -Path (Join-Path $entryIniRoot 'GameUserSettings_Override.ini')
        Add-IniTabPage -TabControl $TabControl -Title 'run.json' -Path (Join-Path $entryIniRoot 'run.json')
    }
}

# ---- Form ----
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Server Ini Settings'
$form.Size = New-Object System.Drawing.Size(900, 700)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(700, 500)

$lstTargets = New-Object System.Windows.Forms.ListBox
$lstTargets.Dock = 'Left'
$lstTargets.Width = 180

$pnlBottom = New-Object System.Windows.Forms.Panel
$pnlBottom.Dock = 'Bottom'
$pnlBottom.Height = 40

# WinForms docks controls in reverse of add order (last added claims its edge first), so
# Dock=Fill must be added before the Left/Bottom controls for them to carve out its space.
$tabIni = New-Object System.Windows.Forms.TabControl
$tabIni.Dock = 'Fill'
$form.Controls.Add($tabIni)
$form.Controls.Add($lstTargets)
$form.Controls.Add($pnlBottom)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(15, 10)
$lblStatus.Size = New-Object System.Drawing.Size(650, 20)
$lblStatus.Text = ''
$pnlBottom.Controls.Add($lblStatus)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = 'Refresh Entries'
$btnRefresh.Location = New-Object System.Drawing.Point(680, 5)
$btnRefresh.Size = New-Object System.Drawing.Size(100, 28)
$pnlBottom.Controls.Add($btnRefresh)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = 'Save'
$btnSave.Location = New-Object System.Drawing.Point(785, 5)
$btnSave.Size = New-Object System.Drawing.Size(90, 28)
$pnlBottom.Controls.Add($btnSave)

function Update-Targets {
    $selected = $lstTargets.SelectedItem
    $lstTargets.Items.Clear()
    [void]$lstTargets.Items.Add('(Global)')
    foreach ($key in (Get-EntryKeys)) {
        [void]$lstTargets.Items.Add($key)
    }
    if ($selected -and $lstTargets.Items.Contains($selected)) {
        $lstTargets.SelectedItem = $selected
    } else {
        $lstTargets.SelectedIndex = 0
    }
}

$lstTargets.Add_SelectedIndexChanged({
    if ($lstTargets.SelectedItem) {
        Update-Editor -TabControl $tabIni -Target $lstTargets.SelectedItem
    }
})

$btnRefresh.Add_Click({ Update-Targets })

$btnSave.Add_Click({
    $result = Save-IniCache
    $lblStatus.Text = "Saved at $(Get-Date -Format 'HH:mm:ss') - $($result.Saved) file(s) saved, $($result.Deleted) empty file(s) removed, $($result.Errors) error(s)."
})

Update-Targets
[void]$form.ShowDialog()
