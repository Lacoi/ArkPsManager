<#
.SYNOPSIS
    ArkRcon module - PowerShell RCON client for ARK: Survival Evolved
    (Source RCON Protocol) with persistent multi-command session support.

.DESCRIPTION
    Exposes cmdlets to open a persistent RCON session and send multiple
    commands over it. Before every command, the socket is verified as
    still connected. If it isn't, the session automatically reconnects
    and retries up to 5 times with a 10 second delay between attempts.

.EXAMPLE
    Import-Module ArkRcon

    $session = New-ArkRconSession -ServerIP 127.0.0.1 -Port 27020 -Password "MyAdminPass" -DebugMode

    Invoke-ArkRconCommand -Session $session -Command "listplayers"
    Invoke-ArkRconCommand -Session $session -Command "broadcast Server restarting soon"
    Invoke-ArkRconCommand -Session $session -Command "saveworld"

    Close-ArkRconSession -Session $session
#>

# --- Protocol constants ---
$Script:SERVERDATA_AUTH          = 3
$Script:SERVERDATA_AUTH_RESPONSE = 2
$Script:SERVERDATA_EXECCOMMAND   = 2

# --- Retry configuration ---
$Script:MaxRetries    = 5
$Script:RetryDelaySec = 10

function Write-ArkRconDebug {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][switch]$DebugMode
    )
    if ($DebugMode) {
        Write-Host "[DEBUG] $Message" -ForegroundColor Cyan
    }
}

function New-ArkRconSession {
    <#
    .SYNOPSIS
        Creates a new RCON session object. Does NOT connect immediately —
        connection is established (and re-established as needed) on first
        use of Invoke-ArkRconCommand.

    .PARAMETER ServerIP
        IP address or hostname of the ARK server.

    .PARAMETER Port
        RCON port (commonly 27020).

    .PARAMETER Password
        RCON admin password (ServerAdminPassword).

    .PARAMETER DebugMode
        Enables verbose debug output for connection/auth/command flow.

    .EXAMPLE
        $session = New-ArkRconSession -ServerIP 127.0.0.1 -Port 27020 -Password "MyAdminPass"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)][string]$ServerIP,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Password,
        [switch]$DebugMode
    )

    return [PSCustomObject]@{
        PSTypeName = 'ArkRcon.Session'
        ServerIP   = $ServerIP
        Port       = $Port
        Password   = $Password
        DebugMode  = [bool]$DebugMode
        TcpClient  = $null
        Stream     = $null
        RequestId  = 0
        Connected  = $false
    }
}

function Test-ArkRconSocketConnected {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Session
    )

    if ($null -eq $Session.TcpClient) {
        return $false
    }

    try {
        $client = $Session.TcpClient.Client

        if (-not $client.Connected) {
            return $false
        }

        $blockingState = $client.Blocking
        $client.Blocking = $false

        try {
            $poll = $client.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead)
            if ($poll -and ($client.Available -eq 0)) {
                # Remote closed the connection.
                return $false
            }
            return $true
        }
        finally {
            $client.Blocking = $blockingState
        }
    }
    catch {
        Write-ArkRconDebug -DebugMode:$Session.DebugMode -Message "Socket check threw exception: $($_.Exception.Message)"
        return $false
    }
}

function Get-ArkRconNextRequestId {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][PSCustomObject]$Session)
    $Session.RequestId++
    return $Session.RequestId
}

function Send-ArkRconPacket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Session,
        [int]$Type,
        [string]$Body,
        [int]$Id
    )

    $bodyBytes = [System.Text.Encoding]::ASCII.GetBytes($Body)
    $packetSize = 4 + 4 + $bodyBytes.Length + 1 + 1 # id + type + body + null + null

    $writer = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($writer)

    $bw.Write([int32]$packetSize)
    $bw.Write([int32]$Id)
    $bw.Write([int32]$Type)
    $bw.Write($bodyBytes)
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Flush()

    $bytes = $writer.ToArray()
    $Session.Stream.Write($bytes, 0, $bytes.Length)
    $Session.Stream.Flush()

    $bw.Dispose()
    $writer.Dispose()
}

function Read-ArkRconExactBytes {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Session,
        [byte[]]$Buffer,
        [int]$Count
    )

    $offset = 0
    while ($offset -lt $Count) {
        $bytesRead = $Session.Stream.Read($Buffer, $offset, $Count - $offset)
        if ($bytesRead -le 0) {
            return $false
        }
        $offset += $bytesRead
    }
    return $true
}

function Receive-ArkRconPacket {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Session
    )

    $sizeBuffer = New-Object byte[] 4
    $read = Read-ArkRconExactBytes -Session $Session -Buffer $sizeBuffer -Count 4
    if (-not $read) { return $null }

    $size = [BitConverter]::ToInt32($sizeBuffer, 0)

    $payload = New-Object byte[] $size
    $read = Read-ArkRconExactBytes -Session $Session -Buffer $payload -Count $size
    if (-not $read) { return $null }

    $id   = [BitConverter]::ToInt32($payload, 0)
    $type = [BitConverter]::ToInt32($payload, 4)
    $bodyLength = $size - 4 - 4 - 2
    $body = [System.Text.Encoding]::ASCII.GetString($payload, 8, [Math]::Max($bodyLength, 0))

    return [PSCustomObject]@{
        Id   = $id
        Type = $type
        Body = $body
    }
}

function Connect-ArkRconInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Session
    )

    Write-ArkRconDebug -DebugMode:$Session.DebugMode -Message "Attempting TCP connection to $($Session.ServerIP):$($Session.Port) ..."

    $client = New-Object System.Net.Sockets.TcpClient
    $connectTask = $client.BeginConnect($Session.ServerIP, $Session.Port, $null, $null)
    $connected = $connectTask.AsyncWaitHandle.WaitOne(5000, $false)

    if (-not $connected) {
        $client.Close()
        throw "Connection attempt timed out after 5 seconds."
    }

    $client.EndConnect($connectTask)
    $client.ReceiveTimeout = 5000
    $client.SendTimeout = 5000

    $Session.TcpClient = $client
    $Session.Stream    = $client.GetStream()

    Write-ArkRconDebug -DebugMode:$Session.DebugMode -Message "TCP connection established. Sending SERVERDATA_AUTH..."

    $authId = Get-ArkRconNextRequestId -Session $Session
    Send-ArkRconPacket -Session $Session -Type $Script:SERVERDATA_AUTH -Body $Session.Password -Id $authId

    $authSucceeded = $false
    for ($i = 0; $i -lt 2; $i++) {
        $resp = Receive-ArkRconPacket -Session $Session
        if ($null -eq $resp) { break }

        Write-ArkRconDebug -DebugMode:$Session.DebugMode -Message "Received packet Type=$($resp.Type) Id=$($resp.Id) Body='$($resp.Body)'"

        if ($resp.Type -eq $Script:SERVERDATA_AUTH_RESPONSE) {
            $authSucceeded = ($resp.Id -ne -1)
            break
        }
    }

    if (-not $authSucceeded) {
        Close-ArkRconSocketOnly -Session $Session
        throw "RCON authentication failed. Check the password."
    }

    $Session.Connected = $true
    Write-ArkRconDebug -DebugMode:$Session.DebugMode -Message "Authentication succeeded. Session ready for multiple commands."
}

function Close-ArkRconSocketOnly {
    # Internal helper: tears down the socket without clearing session config,
    # so the session object can be reused/reconnected.
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][PSCustomObject]$Session)

    try {
        if ($Session.Stream) { $Session.Stream.Close() }
        if ($Session.TcpClient) { $Session.TcpClient.Close() }
    }
    catch {
        Write-ArkRconDebug -DebugMode:$Session.DebugMode -Message "Error while closing connection: $($_.Exception.Message)"
    }
    finally {
        $Session.Stream    = $null
        $Session.TcpClient = $null
        $Session.Connected = $false
    }
}

function Close-ArkRconSession {
    <#
    .SYNOPSIS
        Closes the underlying connection for a session. The session object
        can still be reused afterwards; it will simply reconnect on next use.

    .PARAMETER Session
        The session object returned by New-ArkRconSession.

    .EXAMPLE
        Close-ArkRconSession -Session $session
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)][PSCustomObject]$Session
    )
    process {
        Write-ArkRconDebug -DebugMode:$Session.DebugMode -Message "Closing RCON session."
        Close-ArkRconSocketOnly -Session $Session
    }
}

function Invoke-ArkRconCommand {
    <#
    .SYNOPSIS
        Executes a single RCON command on an existing session, reusing the
        connection. Verifies the socket is alive first; if not, reconnects
        and retries up to 5 times with a 10 second delay between attempts.

    .PARAMETER Session
        The session object returned by New-ArkRconSession.

    .PARAMETER Command
        The RCON command to execute (e.g. "listplayers", "broadcast Hello").

    .EXAMPLE
        Invoke-ArkRconCommand -Session $session -Command "listplayers"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Session,
        [Parameter(Mandatory = $true)][string]$Command
    )

    $attempt = 0

    while ($attempt -le $Script:MaxRetries) {

        if (-not (Test-ArkRconSocketConnected -Session $Session)) {
            if (-not $Session.Connected) {
                Write-ArkRconDebug -DebugMode:$Session.DebugMode -Message "No active connection. Establishing connection."
            }
            else {
                Write-ArkRconDebug -DebugMode:$Session.DebugMode -Message "Socket not connected. Retry attempt $attempt of $Script:MaxRetries."
            }

            try {
                Close-ArkRconSocketOnly -Session $Session
                Connect-ArkRconInternal -Session $Session
            }
            catch {
                Write-Warning "Connection attempt failed: $($_.Exception.Message)"
                $attempt++
                if ($attempt -gt $Script:MaxRetries) {
                    throw "Failed to establish RCON connection after $Script:MaxRetries retries."
                }
                Write-Host "Retrying in $Script:RetryDelaySec seconds... ($attempt/$Script:MaxRetries)"
                Start-Sleep -Seconds $Script:RetryDelaySec
                continue
            }
        }

        try {
            Write-ArkRconDebug -DebugMode:$Session.DebugMode -Message "Socket connected. Sending command: $Command"

            $cmdId = Get-ArkRconNextRequestId -Session $Session
            Send-ArkRconPacket -Session $Session -Type $Script:SERVERDATA_EXECCOMMAND -Body $Command -Id $cmdId

            $response = $null
            $maxReads = 50   # guard against endless loop on stray/keep-alive packets

            for ($i = 0; $i -lt $maxReads; $i++) {
                $packet = Receive-ArkRconPacket -Session $Session
                if ($null -eq $packet) {
                    throw "Connection closed by remote host while waiting for response."
                }

                Write-ArkRconDebug -DebugMode:$Session.DebugMode -Message "Received packet Id=$($packet.Id) Type=$($packet.Type) Body='$($packet.Body)'"

                if ($packet.Id -eq $cmdId) {
                    $response = $packet
                    break
                }
                else {
                    # Stray/keep-alive packet (often Id=0, empty body or "Keep Alive").
                    # Discard and keep waiting for the packet matching our request Id.
                    Write-ArkRconDebug -DebugMode:$Session.DebugMode -Message "Ignoring unmatched packet (expected Id=$cmdId)."
                }
            }

            if ($null -eq $response) {
                throw "Did not receive a matching response for command '$Command' after $maxReads reads."
            }

            return $response.Body
        }
        catch {
            Write-Warning "Command execution failed: $($_.Exception.Message)"
            Close-ArkRconSocketOnly -Session $Session
            $attempt++

            if ($attempt -gt $Script:MaxRetries) {
                throw "Failed to execute command '$Command' after $Script:MaxRetries retries."
            }

            Write-Host "Socket lost during command execution. Retrying in $Script:RetryDelaySec seconds... ($attempt/$Script:MaxRetries)"
            Start-Sleep -Seconds $Script:RetryDelaySec
        }
    }
}

Export-ModuleMember -Function `
    New-ArkRconSession, `
    Invoke-ArkRconCommand, `
    Close-ArkRconSession