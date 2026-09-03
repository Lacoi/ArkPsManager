# ServerManager

A Windows PowerShell + WinForms GUI for running and maintaining multiple **ARK: Survival Ascended** dedicated servers from a single machine - start/stop/restart/kill, RCON-based graceful shutdowns, zipped backups, SteamCMD-based caching, and automatic [AsaApi](https://github.com/ArkServerApi/AsaApi) plugin-loader updates.

## Features

- **Multi-server dashboard** ([App.ps1](App.ps1)) - add any number of server entries (map/instance), see live PID, session name, RAM usage and start time, and act on one or many selected entries at once.
- **Shared local cache** ([actions/UpdateCache.ps1](actions/UpdateCache.ps1)) - installs SteamCMD on first run and keeps a single cached copy of the ARK server files (app `2430930`), so every server instance updates from disk instead of re-downloading from Steam.
  - Detects the SteamCMD build id from `appmanifest_2430930.acf` and snapshots the cache into a versioned `Cache\Server_<buildid>` folder, automatically pruning old snapshots (keeps the latest 3).
  - Downloads the latest [AsaApi](https://github.com/ArkServerApi/AsaApi) release from GitHub, but only when the tagged version differs from the cached one (checked via a local `version.txt`).
- **Build pinning** - drop a `<buildid>.build` marker file in `Cache\` to pin server updates to a specific cached build snapshot instead of the latest one.
- **Per-map INI merging** ([CreateServerSettings.ps1](CreateServerSettings.ps1), [actions/IniMerge](actions/IniMerge)) - maintain one shared `Base_Game.ini` / `Base_GameUserSettings.ini`, then layer per-map `*_Append.ini` / `*_Override.ini` overrides from `config/ini/<Key>/` to produce each server's final `config/maps/<Key>/config/*.ini`.
- **Generated launch scripts** - per-map `run.json` (start options, URL options, command-line options, mods) is merged with a shared base `run.json` to generate each server's `RunServer.cmd`.
- **Graceful shutdown** ([actions/Stop.ps1](actions/Stop.ps1), [actions/ArkRcon](actions/ArkRcon)) - broadcasts countdown warnings over RCON, ends early once no players are connected, saves the world, then shuts the server down.
- **Zipped backups** ([actions/Backup.ps1](actions/Backup.ps1), [actions/ServerBackup](actions/ServerBackup)) - archives server config and save-game files (`.arkprofile`, `.arktribe`, etc.) to a timestamped zip.
- **Auto-restart** - optionally restarts a server automatically if it has been stopped for longer than a configurable time.
- **Action log per server** - every action writes to `logs/<Key>/<Action>.log`, in addition to the live output shown in each action's own PowerShell window.

## Requirements

- Windows with **PowerShell 7+** (`pwsh`) available on `PATH`
- .NET Windows Forms (bundled with Windows; used for the GUI)
- [SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD) - installed automatically into `Cache\SteamCMD` on first cache update
- Enough disk space for one shared server cache (plus up to 3 versioned snapshots) and one copy per configured server instance

## Getting Started

1. Clone/copy this repository somewhere on the host machine.
2. Run [start.bat](start.bat) (or `pwsh -File App.ps1`) to launch the GUI.
3. Click **Settings** to configure `GlobalSettings` (process name/path, ini path, startup script, backup path, shutdown timings/messages).
4. Click **Add Entry**, give it a `Key` (used as the folder name under `config/maps/<Key>`) and the target `ServerPath` for that instance, then **Add Entry**.
5. Click **UpdateCache** to install SteamCMD and download the ARK server files into the shared cache.
6. Click **Create Server Settings** to generate each entry's merged INI files and `RunServer.cmd` from `config/ini`.
7. Use the per-row **Start** / **Restart** / **Stop** / **Kill** / **Backup** / **Update** buttons (or the bulk-action buttons for multiple selected rows) to manage servers.

## Project Structure

```
App.ps1                   Main WinForms dashboard (entry point)
Settings.ps1              GlobalSettings editor dialog
CreateServerSettings.ps1  Generates per-map INI files + RunServer.cmd from config/ini
config.json               Persisted GlobalSettings + server Entries (Key/ServerPath)
start.bat                 Launches App.ps1 hidden

actions/
  Common.ps1              Shared helpers: config/context loading, process matching, logging, action locks
  Start.ps1 / Stop.ps1 / Restart.ps1 / Kill.ps1
  Backup.ps1               Zips server config + save files
  Update.ps1               Syncs server files/AsaApi/plugins from the shared cache
  UpdateCache.ps1           Installs SteamCMD, updates the shared server cache, downloads AsaApi
  ArkRcon/                 Minimal ARK RCON client module
  IniMerge/                INI read/merge/write module (duplicate-key aware)
  ServerBackup/             Zip-backup module
  ServerSync/               Folder-diff sync module used by Update.ps1

config/
  ini/                     Base_Game.ini, Base_GameUserSettings.ini, base run.json, per-map overrides
  maps/                    Generated per-map config output (config/maps/<Key>/config, RunServer.cmd)

cache/                     Shared SteamCMD + server file cache (created automatically)
logs/                      Per-server action logs (logs/<Key>/<Action>.log)
```

## Configuration (`config.json`)

```jsonc
{
  "GlobalSettings": {
    "Process": { "Name": "ArkAscendedServer", "Path": "ShooterGame\\Binaries\\Win64", "RestartTime": 300, "RestartEnabled": true },
    "Ini":     { "Path": "ShooterGame\\Saved\\Config\\WindowsServer", "File": "GameUserSettings.ini" },
    "Startup": { "Name": "ArkAscendedServer", "Path": "ShooterGame\\Saved\\Config\\WindowsServer", "File": "RunServer.cmd", "Delay": 5 },
    "Backup":  { "Path": "C:\\Backup\\ArkAsaNew" },
    "Shutdown": { "Time": 900, "ExitDelay": 5, "Messages": { "900": "...", "0": "..." } }
  },
  "Entries": [
    { "Key": "TheIsland", "ServerPath": "C:\\ArkServer\\Server1" }
  ]
}
```

`GlobalSettings` is only ever written via the **Settings** dialog; `App.ps1` never overwrites it when saving `Entries`. Runtime-only fields (PID, RAM, start time, session name, etc.) are tracked in memory and never persisted.

## Per-Map INI Overrides

For a map with `Key = "TheIsland"`, place any of the following under `config/ini/TheIsland/`:

- `GameUserSettings_Append.ini` / `GameUserSettings_Override.ini`
- `Game_Append.ini` / `Game_Override.ini`
- `run.json` (map name + per-map `startOptions`/`urlOptions`/`commandLineOptions`/`mods`)

Running **Create Server Settings** merges these on top of the shared `config/ini/Base_*.ini` and `config/ini/run.json`, writing the result to `config/maps/TheIsland/config/*.ini` and `config/maps/TheIsland/config/RunServer.cmd`.

## Scheduling Actions with Task Scheduler

Every script under `actions/` is a standalone entry point, so any action (`Start`, `Stop`, `Restart`, `Kill`, `Backup`, `Update`) can be scheduled to run unattended, without the GUI open. `UpdateCache.ps1` and `CreateServerSettings.ps1` take no parameters; the rest require `-Key` (the server's entry key). `-ConfigJsonPath` is optional and defaults to `config.json` next to the `actions` folder, so it only needs to be passed if `config.json` lives somewhere else.

### Using the Task Scheduler GUI

1. Open **Task Scheduler** and choose **Create Task...** (not "Create Basic Task", so you get the "Actions" tab with an "Add arguments" field).
2. On the **General** tab, name the task (e.g. `ServerManager - Backup TheIsland`) and select **Run whether user is logged on or not** if it should run unattended.
3. On the **Triggers** tab, add a schedule (e.g. daily at 04:00, or "At log on" for `UpdateCache`).
4. On the **Actions** tab, click **New...** and set:
   - **Program/script**: `pwsh.exe`
   - **Add arguments**: `-ExecutionPolicy Bypass -File "C:\ArkPsManager\ServerManager\actions\Backup.ps1" -Key "TheIsland"`
   - **Start in**: `C:\ArkPsManager\ServerManager\actions`
5. On the **Conditions**/**Settings** tabs, uncheck "Start the task only if the computer is on AC power" if this runs on a server, and consider enabling "If the task fails, restart every..." for critical actions.
6. Save the task (enter credentials if prompted for "Run whether user is logged on or not").

For `UpdateCache.ps1` or `CreateServerSettings.ps1`, use the same steps but drop `-Key`/`-ConfigJsonPath` from **Add arguments**, e.g. `-ExecutionPolicy Bypass -File "C:\ArkPsManager\actions\UpdateCache.ps1"`.

### Using PowerShell (`Register-ScheduledTask`)

```powershell
$root = "C:\ArkPsManager"
$key  = "TheIsland"

# -ConfigJsonPath is omitted here since config.json lives next to actions\ (its default location)
$action = New-ScheduledTaskAction -Execute "pwsh.exe" `
    -Argument "-ExecutionPolicy Bypass -File `"$root\actions\Backup.ps1`" -Key `"$key`"" `
    -WorkingDirectory (Join-Path $root "actions")

$trigger    = New-ScheduledTaskTrigger -Daily -At 4am
$principal  = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U -RunLevel Highest

Register-ScheduledTask -TaskName "ServerManager - Backup $key" -Action $action -Trigger $trigger -Principal $principal
```

Repeat with a different `-TaskName`, `$action` script/args and `$trigger` for other actions (e.g. a nightly `UpdateCache.ps1` run, or a periodic `Restart.ps1` per server). Each run still writes to `logs/<Key>/<ActionName>.log`, so scheduled runs are auditable the same way as GUI-triggered ones.

## Logs

Each action logs to `logs/<Key>/<ActionName>.log` via `Write-ActionLog` in [actions/Common.ps1](actions/Common.ps1), in addition to writing to the console of the action's own PowerShell window.
