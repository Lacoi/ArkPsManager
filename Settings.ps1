Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------------------
# Settings.ps1
# Standalone module for editing GlobalSettings.
# Dot-sourced by App.ps1: . (Join-Path $PSScriptRoot "Settings.ps1")
# Exposes Show-SettingsDialog -ConfigJsonPath <path>
# The dialog reads/writes GlobalSettings directly in config.json,
# leaving Entries untouched.
# ---------------------------

function Show-SettingsDialog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigJsonPath
    )

    if (-not (Test-Path $ConfigJsonPath)) {
        [System.Windows.Forms.MessageBox]::Show("Config file not found:`n$ConfigJsonPath", "Error") | Out-Null
        return
    }

    $json = Get-Content $ConfigJsonPath -Raw | ConvertFrom-Json
    $gs = $json.GlobalSettings

    # ---- Dialog form ----
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Global Settings"
    $dlg.Size = New-Object System.Drawing.Size(700, 885)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false

    # ---- Process settings ----
    $grpProcess = New-Object System.Windows.Forms.GroupBox
    $grpProcess.Text = "Process"
    $grpProcess.Location = New-Object System.Drawing.Point(15, 15)
    $grpProcess.Size = New-Object System.Drawing.Size(645, 135)
    $dlg.Controls.Add($grpProcess)

    $lblProcName = New-Object System.Windows.Forms.Label
    $lblProcName.Text = "Name:"
    $lblProcName.Location = New-Object System.Drawing.Point(15, 25)
    $lblProcName.Size = New-Object System.Drawing.Size(120, 20)
    $grpProcess.Controls.Add($lblProcName)

    $txtProcName = New-Object System.Windows.Forms.TextBox
    $txtProcName.Location = New-Object System.Drawing.Point(150, 22)
    $txtProcName.Size = New-Object System.Drawing.Size(480, 24)
    $txtProcName.Text = $gs.Process.Name
    $grpProcess.Controls.Add($txtProcName)

    $lblProcPath = New-Object System.Windows.Forms.Label
    $lblProcPath.Text = "Path:"
    $lblProcPath.Location = New-Object System.Drawing.Point(15, 55)
    $lblProcPath.Size = New-Object System.Drawing.Size(120, 20)
    $grpProcess.Controls.Add($lblProcPath)

    $txtProcPath = New-Object System.Windows.Forms.TextBox
    $txtProcPath.Location = New-Object System.Drawing.Point(150, 52)
    $txtProcPath.Size = New-Object System.Drawing.Size(480, 24)
    $txtProcPath.Text = $gs.Process.Path
    $grpProcess.Controls.Add($txtProcPath)

    $lblProcRestartTime = New-Object System.Windows.Forms.Label
    $lblProcRestartTime.Text = "RestartTime (s):"
    $lblProcRestartTime.Location = New-Object System.Drawing.Point(15, 85)
    $lblProcRestartTime.Size = New-Object System.Drawing.Size(130, 20)
    $grpProcess.Controls.Add($lblProcRestartTime)

    $numProcRestartTime = New-Object System.Windows.Forms.NumericUpDown
    $numProcRestartTime.Location = New-Object System.Drawing.Point(150, 82)
    $numProcRestartTime.Size = New-Object System.Drawing.Size(120, 24)
    $numProcRestartTime.Minimum = 0
    $numProcRestartTime.Maximum = 86400
    $numProcRestartTime.Value = [Math]::Max(0, [Math]::Min(86400, [int]$gs.Process.RestartTime))
    $grpProcess.Controls.Add($numProcRestartTime)

    # ---- Ini settings ----
    $grpIni = New-Object System.Windows.Forms.GroupBox
    $grpIni.Text = "Ini"
    $grpIni.Location = New-Object System.Drawing.Point(15, 160)
    $grpIni.Size = New-Object System.Drawing.Size(645, 95)
    $dlg.Controls.Add($grpIni)

    $lblIniPath = New-Object System.Windows.Forms.Label
    $lblIniPath.Text = "Path:"
    $lblIniPath.Location = New-Object System.Drawing.Point(15, 25)
    $lblIniPath.Size = New-Object System.Drawing.Size(120, 20)
    $grpIni.Controls.Add($lblIniPath)

    $txtIniPath = New-Object System.Windows.Forms.TextBox
    $txtIniPath.Location = New-Object System.Drawing.Point(150, 22)
    $txtIniPath.Size = New-Object System.Drawing.Size(480, 24)
    $txtIniPath.Text = $gs.Ini.Path
    $grpIni.Controls.Add($txtIniPath)

    $lblIniFile = New-Object System.Windows.Forms.Label
    $lblIniFile.Text = "File:"
    $lblIniFile.Location = New-Object System.Drawing.Point(15, 55)
    $lblIniFile.Size = New-Object System.Drawing.Size(120, 20)
    $grpIni.Controls.Add($lblIniFile)

    $txtIniFile = New-Object System.Windows.Forms.TextBox
    $txtIniFile.Location = New-Object System.Drawing.Point(150, 52)
    $txtIniFile.Size = New-Object System.Drawing.Size(480, 24)
    $txtIniFile.Text = $gs.Ini.File
    $grpIni.Controls.Add($txtIniFile)

    # ---- Startup settings ----
    $grpStartup = New-Object System.Windows.Forms.GroupBox
    $grpStartup.Text = "Startup"
    $grpStartup.Location = New-Object System.Drawing.Point(15, 265)
    $grpStartup.Size = New-Object System.Drawing.Size(645, 100)
    $dlg.Controls.Add($grpStartup)

    $lblStartupName = New-Object System.Windows.Forms.Label
    $lblStartupName.Text = "Name:"
    $lblStartupName.Location = New-Object System.Drawing.Point(15, 25)
    $lblStartupName.Size = New-Object System.Drawing.Size(120, 20)
    $grpStartup.Controls.Add($lblStartupName)

    $txtStartupName = New-Object System.Windows.Forms.TextBox
    $txtStartupName.Location = New-Object System.Drawing.Point(150, 22)
    $txtStartupName.Size = New-Object System.Drawing.Size(480, 24)
    $txtStartupName.Text = $gs.Startup.Name
    $grpStartup.Controls.Add($txtStartupName)

    $lblStartupFile = New-Object System.Windows.Forms.Label
    $lblStartupFile.Text = "File:"
    $lblStartupFile.Location = New-Object System.Drawing.Point(15, 55)
    $lblStartupFile.Size = New-Object System.Drawing.Size(120, 20)
    $grpStartup.Controls.Add($lblStartupFile)

    $txtStartupFile = New-Object System.Windows.Forms.TextBox
    $txtStartupFile.Location = New-Object System.Drawing.Point(150, 52)
    $txtStartupFile.Size = New-Object System.Drawing.Size(220, 24)
    $txtStartupFile.Text = $gs.Startup.File
    $grpStartup.Controls.Add($txtStartupFile)

    $lblStartupDelay = New-Object System.Windows.Forms.Label
    $lblStartupDelay.Text = "Delay (s):"
    $lblStartupDelay.Location = New-Object System.Drawing.Point(390, 55)
    $lblStartupDelay.Size = New-Object System.Drawing.Size(120, 20)
    $grpStartup.Controls.Add($lblStartupDelay)

    $numStartupDelay = New-Object System.Windows.Forms.NumericUpDown
    $numStartupDelay.Location = New-Object System.Drawing.Point(520, 52)
    $numStartupDelay.Size = New-Object System.Drawing.Size(110, 24)
    $numStartupDelay.Minimum = 0
    $numStartupDelay.Maximum = 3600
    $numStartupDelay.Value = [Math]::Max(0, [Math]::Min(3600, [int]$gs.Startup.Delay))
    $grpStartup.Controls.Add($numStartupDelay)

    # ---- Backup settings ----
    $grpBackup = New-Object System.Windows.Forms.GroupBox
    $grpBackup.Text = "Backup"
    $grpBackup.Location = New-Object System.Drawing.Point(15, 365)
    $grpBackup.Size = New-Object System.Drawing.Size(645, 95)
    $dlg.Controls.Add($grpBackup)

    $lblBackupPath = New-Object System.Windows.Forms.Label
    $lblBackupPath.Text = "Path:"
    $lblBackupPath.Location = New-Object System.Drawing.Point(15, 25)
    $lblBackupPath.Size = New-Object System.Drawing.Size(120, 20)
    $grpBackup.Controls.Add($lblBackupPath)

    $txtBackupPath = New-Object System.Windows.Forms.TextBox
    $txtBackupPath.Location = New-Object System.Drawing.Point(150, 22)
    $txtBackupPath.Size = New-Object System.Drawing.Size(480, 24)
    $txtBackupPath.Text = $gs.Backup.Path
    $grpBackup.Controls.Add($txtBackupPath)

    $lblBackupDailyToKeep = New-Object System.Windows.Forms.Label
    $lblBackupDailyToKeep.Text = "DailyToKeep:"
    $lblBackupDailyToKeep.Location = New-Object System.Drawing.Point(15, 55)
    $lblBackupDailyToKeep.Size = New-Object System.Drawing.Size(120, 20)
    $grpBackup.Controls.Add($lblBackupDailyToKeep)

    $numBackupDailyToKeep = New-Object System.Windows.Forms.NumericUpDown
    $numBackupDailyToKeep.Location = New-Object System.Drawing.Point(150, 52)
    $numBackupDailyToKeep.Size = New-Object System.Drawing.Size(110, 24)
    $numBackupDailyToKeep.Minimum = 0
    $numBackupDailyToKeep.Maximum = 3650
    $numBackupDailyToKeep.Value = [Math]::Max(0, [Math]::Min(3650, [int]$gs.Backup.DailyToKeep))
    $grpBackup.Controls.Add($numBackupDailyToKeep)

    $lblBackupWeeklyToKeep = New-Object System.Windows.Forms.Label
    $lblBackupWeeklyToKeep.Text = "WeeklyToKeep:"
    $lblBackupWeeklyToKeep.Location = New-Object System.Drawing.Point(280, 55)
    $lblBackupWeeklyToKeep.Size = New-Object System.Drawing.Size(120, 20)
    $grpBackup.Controls.Add($lblBackupWeeklyToKeep)

    $numBackupWeeklyToKeep = New-Object System.Windows.Forms.NumericUpDown
    $numBackupWeeklyToKeep.Location = New-Object System.Drawing.Point(410, 52)
    $numBackupWeeklyToKeep.Size = New-Object System.Drawing.Size(110, 24)
    $numBackupWeeklyToKeep.Minimum = 0
    $numBackupWeeklyToKeep.Maximum = 520
    $numBackupWeeklyToKeep.Value = [Math]::Max(0, [Math]::Min(520, [int]$gs.Backup.WeeklyToKeep))
    $grpBackup.Controls.Add($numBackupWeeklyToKeep)

    # ---- Shutdown settings ----
    $grpShutdown = New-Object System.Windows.Forms.GroupBox
    $grpShutdown.Text = "Shutdown"
    $grpShutdown.Location = New-Object System.Drawing.Point(15, 470)
    $grpShutdown.Size = New-Object System.Drawing.Size(645, 330)
    $dlg.Controls.Add($grpShutdown)

    $lblShutdownTime = New-Object System.Windows.Forms.Label
    $lblShutdownTime.Text = "Time (s):"
    $lblShutdownTime.Location = New-Object System.Drawing.Point(15, 25)
    $lblShutdownTime.Size = New-Object System.Drawing.Size(100, 20)
    $grpShutdown.Controls.Add($lblShutdownTime)

    $numShutdownTime = New-Object System.Windows.Forms.NumericUpDown
    $numShutdownTime.Location = New-Object System.Drawing.Point(120, 22)
    $numShutdownTime.Size = New-Object System.Drawing.Size(120, 24)
    $numShutdownTime.Minimum = 0
    $numShutdownTime.Maximum = 999999
    $numShutdownTime.Value = [Math]::Max(0, [Math]::Min(999999, [int]$gs.Shutdown.Time))
    $grpShutdown.Controls.Add($numShutdownTime)

    $lblShutdownExitDelay = New-Object System.Windows.Forms.Label
    $lblShutdownExitDelay.Text = "ExitDelay (s):"
    $lblShutdownExitDelay.Location = New-Object System.Drawing.Point(260, 25)
    $lblShutdownExitDelay.Size = New-Object System.Drawing.Size(110, 20)
    $grpShutdown.Controls.Add($lblShutdownExitDelay)

    $numShutdownExitDelay = New-Object System.Windows.Forms.NumericUpDown
    $numShutdownExitDelay.Location = New-Object System.Drawing.Point(375, 22)
    $numShutdownExitDelay.Size = New-Object System.Drawing.Size(120, 24)
    $numShutdownExitDelay.Minimum = 0
    $numShutdownExitDelay.Maximum = 999999
    $numShutdownExitDelay.Value = [Math]::Max(0, [Math]::Min(999999, [int]$gs.Shutdown.ExitDelay))
    $grpShutdown.Controls.Add($numShutdownExitDelay)

    $lblMessages = New-Object System.Windows.Forms.Label
    $lblMessages.Text = "Messages (seconds before shutdown -> message):"
    $lblMessages.Location = New-Object System.Drawing.Point(15, 55)
    $lblMessages.Size = New-Object System.Drawing.Size(400, 20)
    $grpShutdown.Controls.Add($lblMessages)

    $lvMessages = New-Object System.Windows.Forms.ListView
    $lvMessages.Location = New-Object System.Drawing.Point(15, 80)
    $lvMessages.Size = New-Object System.Drawing.Size(615, 150)
    $lvMessages.View = [System.Windows.Forms.View]::Details
    $lvMessages.FullRowSelect = $true
    $lvMessages.GridLines = $true
    $lvMessages.MultiSelect = $false
    [void]$lvMessages.Columns.Add("Seconds", 100)
    [void]$lvMessages.Columns.Add("Message", 490)
    $grpShutdown.Controls.Add($lvMessages)

    if ($gs.Shutdown.Messages) {
        foreach ($prop in ($gs.Shutdown.Messages.PSObject.Properties | Sort-Object { [int]$_.Name } -Descending)) {
            $item = New-Object System.Windows.Forms.ListViewItem($prop.Name)
            [void]$item.SubItems.Add("$($prop.Value)")
            [void]$lvMessages.Items.Add($item)
        }
    }

    $lblNewSeconds = New-Object System.Windows.Forms.Label
    $lblNewSeconds.Text = "Seconds:"
    $lblNewSeconds.Location = New-Object System.Drawing.Point(15, 240)
    $lblNewSeconds.Size = New-Object System.Drawing.Size(70, 20)
    $grpShutdown.Controls.Add($lblNewSeconds)

    $numNewSeconds = New-Object System.Windows.Forms.NumericUpDown
    $numNewSeconds.Location = New-Object System.Drawing.Point(90, 237)
    $numNewSeconds.Size = New-Object System.Drawing.Size(90, 24)
    $numNewSeconds.Minimum = 0
    $numNewSeconds.Maximum = 999999
    $grpShutdown.Controls.Add($numNewSeconds)

    $lblNewMessage = New-Object System.Windows.Forms.Label
    $lblNewMessage.Text = "Message:"
    $lblNewMessage.Location = New-Object System.Drawing.Point(190, 240)
    $lblNewMessage.Size = New-Object System.Drawing.Size(70, 20)
    $grpShutdown.Controls.Add($lblNewMessage)

    $txtNewMessage = New-Object System.Windows.Forms.TextBox
    $txtNewMessage.Location = New-Object System.Drawing.Point(260, 237)
    $txtNewMessage.Size = New-Object System.Drawing.Size(300, 24)
    $grpShutdown.Controls.Add($txtNewMessage)

    $btnAddMessage = New-Object System.Windows.Forms.Button
    $btnAddMessage.Text = "Add"
    $btnAddMessage.Location = New-Object System.Drawing.Point(570, 235)
    $btnAddMessage.Size = New-Object System.Drawing.Size(60, 28)
    $grpShutdown.Controls.Add($btnAddMessage)

    $btnAddMessage.Add_Click({
        $secs = [int]$numNewSeconds.Value
        $msg = $txtNewMessage.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($msg)) {
            [System.Windows.Forms.MessageBox]::Show("Message text is required.", "Info") | Out-Null
            return
        }

        $existing = $lvMessages.Items | Where-Object { $_.Text -eq "$secs" } | Select-Object -First 1
        if ($existing) {
            $existing.SubItems[1].Text = $msg
        } else {
            $item = New-Object System.Windows.Forms.ListViewItem("$secs")
            [void]$item.SubItems.Add($msg)
            [void]$lvMessages.Items.Add($item)
        }

        $txtNewMessage.Clear()
    })

    $btnRemoveMessage = New-Object System.Windows.Forms.Button
    $btnRemoveMessage.Text = "Remove Selected"
    $btnRemoveMessage.Location = New-Object System.Drawing.Point(15, 270)
    $btnRemoveMessage.Size = New-Object System.Drawing.Size(150, 28)
    $grpShutdown.Controls.Add($btnRemoveMessage)

    $btnRemoveMessage.Add_Click({
        if ($lvMessages.SelectedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Select a message to remove.", "Info") | Out-Null
            return
        }
        foreach ($sel in @($lvMessages.SelectedItems)) {
            $lvMessages.Items.Remove($sel)
        }
    })

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Save"
    $btnOk.Location = New-Object System.Drawing.Point(490, 810)
    $btnOk.Size = New-Object System.Drawing.Size(80, 30)
    $dlg.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(580, 810)
    $btnCancel.Size = New-Object System.Drawing.Size(80, 30)
    $dlg.Controls.Add($btnCancel)

    $btnCancel.Add_Click({ $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.Close() })

    $btnOk.Add_Click({
        # Re-read the current file (to avoid clobbering Entries changed elsewhere in the meantime)
        $latest = Get-Content $ConfigJsonPath -Raw | ConvertFrom-Json

        $latest.GlobalSettings.Process.Name = $txtProcName.Text.Trim()
        $latest.GlobalSettings.Process.Path = $txtProcPath.Text.Trim()
        $latest.GlobalSettings.Process.RestartTime = [int]$numProcRestartTime.Value
        $latest.GlobalSettings.Ini.Path = $txtIniPath.Text.Trim()
        $latest.GlobalSettings.Ini.File = $txtIniFile.Text.Trim()
        $latest.GlobalSettings.Startup.Name = $txtStartupName.Text.Trim()
        $latest.GlobalSettings.Startup.File = $txtStartupFile.Text.Trim()
        $latest.GlobalSettings.Startup.Delay = [int]$numStartupDelay.Value
        $latest.GlobalSettings.Backup.Path = $txtBackupPath.Text.Trim()
        $latest.GlobalSettings.Backup.DailyToKeep = [int]$numBackupDailyToKeep.Value
        $latest.GlobalSettings.Backup.WeeklyToKeep = [int]$numBackupWeeklyToKeep.Value

        $messages = [ordered]@{}
        foreach ($item in $lvMessages.Items) {
            $messages[$item.Text] = $item.SubItems[1].Text
        }
        $latest.GlobalSettings.Shutdown.Time = [int]$numShutdownTime.Value
        $latest.GlobalSettings.Shutdown.ExitDelay = [int]$numShutdownExitDelay.Value
        $latest.GlobalSettings.Shutdown.Messages = [PSCustomObject]$messages

        $latest | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigJsonPath -Encoding UTF8

        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    })

    [void]$dlg.ShowDialog()
}