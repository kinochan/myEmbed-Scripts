# ============================================================
# ELC SERVICES RESTART
#
# Process:
#   1. Elevate to Administrator
#   2. Pre-flight check both Telnet devices
#   3. Telnet into 192.168.101.211 and reboot
#   4. Wait for 192.168.101.211 Telnet service to go offline
#   5. Wait for 192.168.101.211 Telnet service to return
#   6. Telnet into 192.168.101.213 and reboot
#   7. Wait for 192.168.101.213 Telnet service to go offline
#   8. Wait for 192.168.101.213 Telnet service to return
#   9. Restart ECS Game Services
# ============================================================
# ============================================================
# EXTERNAL SOURCE
# ============================================================
# Telnet client based on:
# JohnLBevan / PSTelnetClient.ps1
# Source:
# https://gist.github.com/JohnLBevan/e28fbb6c0dfdd45a21e03c104999c212
# ============================================================
# SELF-ELEVATE TO ADMINISTRATOR
# ============================================================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $currentPrincipal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Start-Process powershell.exe `
        -Verb RunAs `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}
# ============================================================
# WINDOW CONFIGURATION
# ============================================================
$host.UI.RawUI.WindowTitle = "ELC Services Restart"
try {
    $rawUI = $host.UI.RawUI
    $size = $rawUI.WindowSize
    $size.Width = 100
    $size.Height = 50
    $rawUI.WindowSize = $size
}
catch {
    # Window resizing is cosmetic.
    # Continue if this host does not support resizing.
}
# ============================================================
# CONFIGURATION
# ============================================================
# Devices to reboot via Telnet
$TelnetComputers = @(
    '192.168.101.211',
    '192.168.101.213'
)
# Telnet port
$TelnetPort = 23
# TCP connection test timeout in milliseconds
$TcpTestTimeout = 1000
# Maximum time to wait for Telnet to disappear after reboot
$WaitForOfflineTimeout = 60
# Maximum time to wait for Telnet to return after reboot
$WaitForOnlineTimeout = 180
# ECS Game Services
$serviceNames = @(
    'ECS-GAMESERVICE$A1_E11',
    'ECS-GAMESERVICE$B1_E12',
    'ECS-GAMESERVICE$C1_E21',
    'ECS-GAMESERVICE$D1_E23'
)
# ============================================================
# TELNET CLIENT
# ============================================================
Function New-TelnetClient {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,
        [Parameter()]
        [int]$PortNo = 23,
        [Parameter()]
        [System.Text.Encoding]$Encoding = [System.Text.Encoding]::ASCII,
        [Parameter()]
        [int]$BufferSize = 1024
    )
    [System.Net.Sockets.TcpClient]$telnet =
        New-Object 'System.Net.Sockets.TcpClient'
    try {
        $telnet.PSTypeNames.Add(
            'ClearChannel.Net.Sockets.TelnetClient'
        )
        $telnet | Add-Member `
            -MemberType 'NoteProperty' `
            -Name 'Encoding' `
            -Value $Encoding
        $telnet | Add-Member `
            -MemberType 'NoteProperty' `
            -Name 'EndOfCommand' `
            -Value ([System.Environment]::NewLine)
        $telnet | Add-Member `
            -MemberType 'NoteProperty' `
            -Name 'BufferSize' `
            -Value $BufferSize
        # ----------------------------------------------------
        # CONNECT
        # ----------------------------------------------------
        $telnet.Connect(
            $ComputerName,
            $PortNo
        )
        # ----------------------------------------------------
        # CREATE STREAM WRITER
        # ----------------------------------------------------
        $telnet | Add-Member `
            -MemberType 'NoteProperty' `
            -Name 'Writer' `
            -Value (
                New-Object `
                    -TypeName 'System.IO.StreamWriter' `
                    -ArgumentList ($telnet.GetStream())
            )
        $telnet.Writer.AutoFlush = $true
        # ----------------------------------------------------
        # SEND COMMAND
        # ----------------------------------------------------
        $telnet | Add-Member `
            -MemberType 'ScriptMethod' `
            -Name 'SendCommand' `
            -Value ({
                Param(
                    [string]$CommandText
                )
                $this.Writer.WriteLine(
                    $CommandText
                )
                New-Object `
                    -TypeName 'PSObject' `
                    -Property @{
                        Direction = 'Input'
                        Value     = $CommandText
                        When      = (Get-Date).ToUniversalTime()
                    }
            })
        # ----------------------------------------------------
        # HANDLE TELNET IAC
        # ----------------------------------------------------
        $telnet | Add-Member `
            -MemberType 'ScriptMethod' `
            -Name 'HandleIac' `
            -Value ({
                if ($this.Available) {
                    [int]$byte =
                        $this.GetStream().ReadByte()
                    [byte]$defaultResponse = 254
                    switch ($byte) {
                        -1 {
                            Write-Warning `
                                'Unexpected end of stream whilst processing IAC'
                            return
                        }
                        255 {
                            Write-Debug 'IAC Escaped'
                            return $byte
                        }
                        253 {
                            # DO
                            # Respond with WON'T
                            $defaultResponse = 252
                        }
                        {
                            (251,252,253,254) -contains $_
                        } {
                            $byte =
                                $this.GetStream().ReadByte()
                            switch ($byte) {
                                -1 {
                                    Write-Warning `
                                        'Unexpected end of stream whilst processing IAC'
                                }
                                default {
                                    $this.GetStream().WriteByte(
                                        255
                                    )
                                    $this.GetStream().WriteByte(
                                        $defaultResponse
                                    )
                                    $this.GetStream().WriteByte(
                                        $byte
                                    )
                                }
                            }
                            return
                        }
                        default {
                            Write-Warning `
                                "$byte is not a control character, but was received after an IAC character"
                        }
                    }
                }
            })
        # ----------------------------------------------------
        # READ BYTES
        # ----------------------------------------------------
        $telnet | Add-Member `
            -MemberType 'ScriptMethod' `
            -Name 'GetBytes' `
            -Value ({
                # Give the device time to respond to each
                # Telnet command / negotiation.
                Start-Sleep -Milliseconds 500
                while ($this.Available -gt 0) {
                    [int]$byte =
                        $this.GetStream().ReadByte()
                    switch ($byte) {
                        -1 {
                            return
                        }
                        255 {
                            Write-Verbose `
                                'IAC Command Received'
                            $this.HandleIac()
                            break
                        }
                        {
                            ($_ -ge 0) -and
                            ($_ -lt 255)
                        } {
                            [byte]$byte
                            Write-Debug `
                                "found $byte"
                            break
                        }
                        default {
                            throw `
                                "Received value $_ when expecting a byte (0-255)"
                        }
                    }
                }
            })
        # ----------------------------------------------------
        # CONVERT TELNET DATA TO TEXT
        # ----------------------------------------------------
        $telnet | Add-Member `
            -MemberType 'ScriptMethod' `
            -Name 'GetOutput' `
            -Value ({
                [byte[]]$bytes =
                    $this.GetBytes()
                if (
                    ($null -ne $bytes) -and
                    ($bytes.Length -gt 0)
                ) {
                    Write-Verbose `
                        "raw output is $(($bytes | ForEach-Object {"$_"}) -join ', ')"
                    $this.Encoding.GetString(
                        $bytes
                    )
                }
                else {
                    Write-Verbose `
                        'no output this time'
                }
            })
        # ----------------------------------------------------
        # RECEIVE / SEND COMMAND SEQUENCE
        # ----------------------------------------------------
        $telnet | Add-Member `
            -MemberType 'ScriptMethod' `
            -Name 'ReceiveThenSendCommands' `
            -Value ({
                Param(
                    [string[]]$Commands
                )
                foreach ($commandText in $Commands) {
                    $this.GetOutput()
                    $this.SendCommand(
                        $commandText
                    )
                }
                $this.GetOutput()
            })
        # ----------------------------------------------------
        # RETURN CONNECTED TELNET CLIENT
        # ----------------------------------------------------
        if ($telnet.Connected) {
            $telnet
        }
        else {
            throw `
                "Failed to connect to $ComputerName on port $PortNo"
        }
    }
    catch {
        Write-Host ""
        Write-Host `
            "TELNET CONNECTION ERROR:" `
            -ForegroundColor Red
        Write-Host `
            $_.Exception.Message `
            -ForegroundColor Red
        Remove-TelnetClient `
            -TelnetClient $telnet
        throw
    }
}
# ============================================================
# CLOSE TELNET CLIENT
# ============================================================
Function Remove-TelnetClient {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [PSObject]$TelnetClient
    )
    if ($null -ne $TelnetClient) {
        try {
            if ($TelnetClient.Connected) {
                $TelnetClient.GetStream().Close()
                $TelnetClient.Close()
            }
        }
        catch {
            # Ignore cleanup errors
        }
        try {
            if ($TelnetClient.Dispose) {
                $TelnetClient.Dispose()
            }
        }
        catch {
            # Ignore cleanup errors
        }
    }
}
# ============================================================
# FAST TCP / TELNET PORT TEST
# ============================================================
function Test-TelnetPort {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,
        [int]$TimeoutMilliseconds = 1000
    )
    $client =
        New-Object System.Net.Sockets.TcpClient
    try {
        $connectTask =
            $client.ConnectAsync(
                $ComputerName,
                $TelnetPort
            )
        $completed =
            $connectTask.Wait(
                $TimeoutMilliseconds
            )
        if (-not $completed) {
            return $false
        }
        return $client.Connected
    }
    catch {
        return $false
    }
    finally {
        try {
            $client.Close()
        }
        catch {
        }
        try {
            $client.Dispose()
        }
        catch {
        }
    }
}
# ============================================================
# PRE-FLIGHT CONNECTIVITY CHECK
# ============================================================
function Test-PreFlightConnectivity {
    Write-Host ""
    Write-Host `
        "============================================================" `
        -ForegroundColor Cyan
    Write-Host `
        " PRE-FLIGHT CONNECTIVITY CHECK" `
        -ForegroundColor Cyan
    Write-Host `
        "============================================================" `
        -ForegroundColor Cyan
    Write-Host ""
    $allReady = $true
    foreach ($computer in $TelnetComputers) {
        Write-Host `
            "Checking $computer on TCP port $TelnetPort..." `
            -ForegroundColor Yellow
        $reachable = Test-TelnetPort `
            -ComputerName $computer `
            -TimeoutMilliseconds $TcpTestTimeout
        if ($reachable -eq $true) {
            Write-Host `
                " $computer : READY" `
                -ForegroundColor Green
        }
        else {
            Write-Host `
                " $computer : NOT AVAILABLE" `
                -ForegroundColor Red
            $allReady = $false
        }
        Write-Host ""
    }
    if ($allReady -eq $true) {
        Write-Host `
            "------------------------------------------------------------" `
            -ForegroundColor Green
        Write-Host `
            " PRE-FLIGHT CHECK PASSED" `
            -ForegroundColor Green
        Write-Host `
            " Both devices are responding on TCP port $TelnetPort." `
            -ForegroundColor Green
        Write-Host `
            "------------------------------------------------------------" `
            -ForegroundColor Green
        Write-Host ""
        return $true
    }
    Write-Host `
        "============================================================" `
        -ForegroundColor Red
    Write-Host `
        " PRE-FLIGHT CHECK FAILED" `
        -ForegroundColor Red
    Write-Host `
        "============================================================" `
        -ForegroundColor Red
    Write-Host ""
    Write-Host `
        "One or more devices are not responding on TCP port $TelnetPort." `
        -ForegroundColor Red
    Write-Host ""
    Write-Host `
        "No devices have been rebooted." `
        -ForegroundColor Yellow
    Write-Host `
        "ECS services will not be restarted." `
        -ForegroundColor Yellow
    Write-Host ""
    return $false
}
# ============================================================
# WAIT FOR DEVICE TELNET SERVICE TO GO OFFLINE
# ============================================================
function Wait-ForDeviceOffline {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ComputerName
    )
    Write-Host ""
    Write-Host `
        "Waiting for $ComputerName to begin rebooting..." `
        -ForegroundColor Yellow
    $stopwatch =
        [System.Diagnostics.Stopwatch]::StartNew()
    while (
        $stopwatch.Elapsed.TotalSeconds -lt
        $WaitForOfflineTimeout
    ) {
        $portAvailable = Test-TelnetPort `
            -ComputerName $ComputerName `
            -TimeoutMilliseconds $TcpTestTimeout
        if ($portAvailable -ne $true) {
            $stopwatch.Stop()
            Write-Host ""
            Write-Host `
                "$ComputerName Telnet service is now offline." `
                -ForegroundColor Cyan
            return $true
        }
        Write-Host "." `
            -NoNewline `
            -ForegroundColor DarkGray
        Start-Sleep -Seconds 1
    }
    $stopwatch.Stop()
    Write-Host ""
    Write-Host `
        "WARNING: TCP port $TelnetPort on $ComputerName remained available for $WaitForOfflineTimeout seconds." `
        -ForegroundColor Yellow
    return $false
}
# ============================================================
# WAIT FOR DEVICE TELNET SERVICE TO COME BACK ONLINE
# ============================================================
function Wait-ForDeviceOnline {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ComputerName
    )
    Write-Host ""
    Write-Host `
        "Waiting for $ComputerName to come back online..." `
        -ForegroundColor Yellow
    $stopwatch =
        [System.Diagnostics.Stopwatch]::StartNew()
    while (
        $stopwatch.Elapsed.TotalSeconds -lt
        $WaitForOnlineTimeout
    ) {
        $portAvailable = Test-TelnetPort `
            -ComputerName $ComputerName `
            -TimeoutMilliseconds $TcpTestTimeout
        if ($portAvailable -eq $true) {
            $stopwatch.Stop()
            Write-Host ""
            Write-Host `
                "$ComputerName is back online and Telnet port $TelnetPort is responding." `
                -ForegroundColor Green
            return $true
        }
        Write-Host "." `
            -NoNewline `
            -ForegroundColor DarkGray
        Start-Sleep -Seconds 2
    }
    $stopwatch.Stop()
    Write-Host ""
    Write-Host `
        "ERROR: Timed out waiting for Telnet on $ComputerName." `
        -ForegroundColor Red
    return $false
}
# ============================================================
# REBOOT ONE DEVICE VIA TELNET
# ============================================================
function Restart-TelnetDevice {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ComputerName
    )
    Write-Host ""
    Write-Host `
        "------------------------------------------------------------" `
        -ForegroundColor DarkGray
    Write-Host `
        " REBOOTING $ComputerName" `
        -ForegroundColor Yellow
    Write-Host `
        "------------------------------------------------------------" `
        -ForegroundColor DarkGray
    $telnet = $null
    try {
        Write-Host `
            "Connecting to $ComputerName via Telnet..." `
            -ForegroundColor Yellow
        $telnet = New-TelnetClient `
            -ComputerName $ComputerName `
            -PortNo $TelnetPort
        if ($null -eq $telnet) {
            throw `
                "Telnet client was not created for $ComputerName."
        }
        Write-Host `
            "Connected to $ComputerName." `
            -ForegroundColor Green
        Write-Host `
            "Sending login and reboot commands..." `
            -ForegroundColor Yellow
        # ----------------------------------------------------
        # LOGIN AND REBOOT
        #
        # Suppress Telnet output so this function returns
        # only a clean Boolean result.
        # ----------------------------------------------------
        $null = $telnet.ReceiveThenSendCommands(@(
            'root'
            'javasucks'
            'reboot'
            'Y'
        ))
        Write-Host ""
        Write-Host `
            "Reboot command sent to $ComputerName." `
            -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Host `
            "TELNET REBOOT FAILED FOR $ComputerName" `
            -ForegroundColor Red
        Write-Host `
            $_.Exception.Message `
            -ForegroundColor Red
        return $false
    }
    finally {
        Remove-TelnetClient `
            -TelnetClient $telnet
    }
    # --------------------------------------------------------
    # MAKE SURE THE DEVICE'S TELNET SERVICE GOES DOWN
    # --------------------------------------------------------
    $wentOffline = Wait-ForDeviceOffline `
        -ComputerName $ComputerName
    if ($wentOffline -ne $true) {
        Write-Host ""
        Write-Host `
            "Unable to verify that $ComputerName rebooted." `
            -ForegroundColor Red
        return $false
    }
    # --------------------------------------------------------
    # WAIT FOR TELNET TO COME BACK
    # --------------------------------------------------------
    $cameOnline = Wait-ForDeviceOnline `
        -ComputerName $ComputerName
    if ($cameOnline -ne $true) {
        Write-Host ""
        Write-Host `
            "$ComputerName did not return successfully." `
            -ForegroundColor Red
        return $false
    }
    Write-Host ""
    Write-Host `
        "$ComputerName reboot completed successfully." `
        -ForegroundColor Green
    return $true
}
# ============================================================
# RESTART ECS GAME SERVICES
# ============================================================
function Restart-ELCServices {
    $allServicesSuccessful = $true
    foreach ($serviceName in $serviceNames) {
        try {
            Write-Host `
                "Restarting $serviceName..." `
                -ForegroundColor Yellow
            Restart-Service `
                -Name $serviceName `
                -Force `
                -ErrorAction Stop
            Write-Host `
                "$serviceName has been restarted." `
                -ForegroundColor Cyan
        }
        catch {
            $allServicesSuccessful = $false
            Write-Host `
                "Failed to restart $serviceName : $($_.Exception.Message)" `
                -ForegroundColor Red
        }
    }
    return $allServicesSuccessful
}
# ============================================================
# MAIN PROCESS
# ============================================================
Set-Location `
    -Path "C:\Users\emb-ecs\"
Clear-Host
Write-Host ""
Write-Host `
    "============================================================" `
    -ForegroundColor Green
Write-Host `
    " ELC RESTART PROCESS STARTED" `
    -ForegroundColor Green
Write-Host `
    "============================================================" `
    -ForegroundColor Green
Write-Host ""
# ============================================================
# PRE-FLIGHT CONNECTIVITY CHECK
# ============================================================
$preFlightSuccessful =
    Test-PreFlightConnectivity
if ($preFlightSuccessful -ne $true) {
    Write-Host ""
    Write-Host `
        "Restart process aborted." `
        -ForegroundColor Red
    Write-Host ""
    Read-Host `
        "Press Enter to exit"
    exit 1
}
# ============================================================
# REBOOT TELNET DEVICES
# ============================================================
$allDevicesSuccessful = $true
foreach ($computer in $TelnetComputers) {
    $result = Restart-TelnetDevice `
        -ComputerName $computer
    if ($result -ne $true) {
        $allDevicesSuccessful = $false
        Write-Host ""
        Write-Host `
            "Reboot verification failed for $computer." `
            -ForegroundColor Red
        # Do not reboot additional devices if one fails.
        # Do not restart ECS services.
        break
    }
}
# ============================================================
# VERIFY ALL DEVICES REBOOTED SUCCESSFULLY
# ============================================================
if ($allDevicesSuccessful -ne $true) {
    Write-Host ""
    Write-Host `
        "============================================================" `
        -ForegroundColor Red
    Write-Host `
        " DEVICE REBOOT FAILED" `
        -ForegroundColor Red
    Write-Host `
        " ECS SERVICES WILL NOT BE RESTARTED" `
        -ForegroundColor Red
    Write-Host `
        "============================================================" `
        -ForegroundColor Red
    Write-Host ""
    Read-Host `
        "Press Enter to exit"
    exit 1
}
# ============================================================
# BOTH DEVICES ARE BACK ONLINE
# ============================================================
Write-Host ""
Write-Host `
    "============================================================" `
    -ForegroundColor Green
Write-Host `
    " BOTH DEVICES ARE BACK ONLINE" `
    -ForegroundColor Green
Write-Host `
    "============================================================" `
    -ForegroundColor Green
Write-Host ""
# ============================================================
# RESTART ECS SERVICES
# ============================================================
Write-Host `
    "Restarting ELC services..." `
    -ForegroundColor Yellow
Write-Host ""
$servicesSuccessful =
    Restart-ELCServices
# ============================================================
# FINAL STATUS
# ============================================================
Write-Host ""
if ($servicesSuccessful -eq $true) {
    Write-Host `
        "============================================================" `
        -ForegroundColor Green
    Write-Host `
        " ELC RESTART PROCESS COMPLETE" `
        -ForegroundColor Green
    Write-Host ""
    Write-Host `
        " Both devices rebooted successfully." `
        -ForegroundColor Green
    Write-Host `
        " All ECS services restarted successfully." `
        -ForegroundColor Green
    Write-Host `
        "============================================================" `
        -ForegroundColor Green
}
else {
    Write-Host `
        "============================================================" `
        -ForegroundColor Yellow
    Write-Host `
        " ELC RESTART PROCESS COMPLETED WITH SERVICE ERRORS" `
        -ForegroundColor Yellow
    Write-Host ""
    Write-Host `
        " Both devices rebooted successfully." `
        -ForegroundColor Green
    Write-Host `
        " One or more ECS services failed to restart." `
        -ForegroundColor Red
    Write-Host `
        "============================================================" `
        -ForegroundColor Yellow
}
Write-Host ""
Read-Host `
    "Press Enter to exit"
