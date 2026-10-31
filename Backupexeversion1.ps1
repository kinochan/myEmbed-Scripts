Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

# ============================================
# Robust AppRoot detection
# ============================================
$AppRoot = $null

if ($PSScriptRoot -and $PSScriptRoot.Trim() -ne "") {
    $AppRoot = $PSScriptRoot
}
elseif ($MyInvocation.MyCommand.Path -and $MyInvocation.MyCommand.Path.Trim() -ne "") {
    $AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $AppRoot = Split-Path -Parent $exePath
}

if (-not $AppRoot -or $AppRoot.Trim() -eq "") {
    throw "AppRoot could not be determined. Aborting to avoid null Path errors."
}

# ============================================
# Core paths
# ============================================
$ConfigFile  = Join-Path $AppRoot "backup.config"
$ProfilesDir = Join-Path $AppRoot "Profiles"
$SitesDir    = Join-Path $AppRoot "Sites"
$LogDir      = Join-Path $AppRoot "Logs"
$LogFile     = Join-Path $LogDir "backup_log.txt"

if (-not (Test-Path $ProfilesDir)) {
    New-Item -Path $ProfilesDir -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $SitesDir)) {
    New-Item -Path $SitesDir -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

# ============================================
# Default config
# ============================================
function New-DefaultConfig {
@"
[General]
SiteName        = paradise
BackupPath      = C:\SQL\BACKUP
SASToken        = <PLACEHOLDER>
StorageAccount  = ecsserver
"@
}

if (-not (Test-Path $ConfigFile)) {
    New-DefaultConfig | Out-File $ConfigFile -Encoding UTF8
}
elseif ((Get-Item $ConfigFile).Length -eq 0) {
    New-DefaultConfig | Out-File $ConfigFile -Encoding UTF8
}
else {
    $raw = Get-Content $ConfigFile -ErrorAction SilentlyContinue
    if ($raw -notmatch "^

\[General\]

") {
        New-DefaultConfig | Out-File $ConfigFile -Encoding UTF8
    }
}

# ============================================
# Config helpers
# ============================================
function Load-Config {
    param([string]$Path)
    if (-not $Path -or $Path.Trim() -eq "") {
        throw "Load-Config: Path is null or empty."
    }
    if (-not (Test-Path $Path)) {
        throw "Load-Config: File '$Path' not found."
    }

    $cfg = @{}
    $section = ""
    foreach ($line in Get-Content $Path) {
        $trim = $line.Trim()
        if ($trim -eq "" -or $trim.StartsWith("#")) { continue }
        if ($trim.StartsWith("[") -and $trim.EndsWith("]")) {
            $section = $trim.Trim("[","]")
            if (-not $cfg.ContainsKey($section)) { $cfg[$section] = @{} }
            continue
        }
        if ($trim -match "^(.*?)=(.*)$") {
            $key = $matches[1].Trim()
            $val = $matches[2].Trim()
            $cfg[$section][$key] = $val
        }
    }
    return $cfg
}
# Server Configuration
function Save-Config {
    param($Config, [string]$Path)
    if (-not $Path -or $Path.Trim() -eq "") {
        throw "Save-Config: Path is null or empty."
    }

    $lines = @()
    foreach ($section in $Config.Keys) {
        $lines += "[$section]"
        foreach ($key in $Config[$section].Keys) {
            $val = $Config[$section][$key]
            $lines += "$key = $val"
        }
        $lines += ""
    }
    $lines | Out-File $Path -Encoding UTF8
}
# Load Profiles
function Load-Profile {
    param([string]$ProfileName)
    if (-not $ProfileName -or $ProfileName.Trim() -eq "") {
        throw "Load-Profile: ProfileName is empty."
    }

    $ProfilePath = Join-Path $ProfilesDir "$ProfileName.ini"
    if (-not (Test-Path $ProfilePath)) {
        throw "Profile '$ProfileName' not found at '$ProfilePath'."
    }
    return Load-Config $ProfilePath
}
# Save Profiles
function Save-Profile {
    param([string]$ProfileName, $ConfigObject)
    if (-not $ProfileName -or $ProfileName.Trim() -eq "") {
        throw "Save-Profile: ProfileName is empty."
    }

    $ProfilePath = Join-Path $ProfilesDir "$ProfileName.ini"
    Save-Config -Config $ConfigObject -Path $ProfilePath
}
# Defaults
function New-DefaultProfile {
    param([string]$BusinessName)
@"
[Profile]
BusinessName    = $BusinessName
EmailTo         = mike@missionbeachattractions.com
EmailFrom       = info@pacificparadisepark.com
SMTPServer      = mail.pacificparadisepark.com
SMTPPort        = 587
SMTPUser        = info@pacificparadisepark.com
SMTPPass        = Starbar1!
"@
}

# Auto-create a default business profile if none exist
$defaultProfilePath = Join-Path $ProfilesDir "default.ini"
if (-not (Test-Path $defaultProfilePath)) {
    New-DefaultProfile -BusinessName "Paradise Park" | Out-File $defaultProfilePath -Encoding UTF8
}

# ============================================
# Site profiles
# ============================================
function New-SiteProfile {
    param(
        [string]$SiteName,
        [string]$BackupPath,
        [string]$SASToken
    )
@"
[Site]
SiteName        = $SiteName
BackupPath      = $BackupPath
SASToken        = $SASToken
StorageAccount  = ecsserver
"@
}

# Paradise
$paradiseSite = Join-Path $SitesDir "paradise.ini"
if (-not (Test-Path $paradiseSite)) {
    New-SiteProfile -SiteName "paradise" `
        -BackupPath "E:\SQL\BACKUP" `
        -SASToken "?sp=racwdl&st=2026-08-04T21:06:31Z&se=2027-08-05T05:21:31Z&spr=https&sv=2026-02-06&sr=c&sig=LRKOwsezkN9liGcsNIiZuXI9XqxDHXhVwRW%2FMnqu%2B2o%3D" |
        Out-File $paradiseSite -Encoding UTF8
}

# Seabrook
$seabrookSite = Join-Path $SitesDir "seabrook.ini"
if (-not (Test-Path $seabrookSite)) {
    New-SiteProfile -SiteName "seabrook" `
        -BackupPath "\\ecsbackup\backup" `
        -SASToken "?sp=racwdl&st=2026-08-04T21:05:45Z&se=2027-08-05T05:20:45Z&spr=https&sv=2026-02-06&sr=c&sig=jPIJ%2BOmlimIzAoA4L8Y2oPa4NHOihReYjdoZwPvLNq8%3D" |
        Out-File $seabrookSite -Encoding UTF8
}

# Atomic
$atomicSite = Join-Path $SitesDir "atomic.ini"
if (-not (Test-Path $atomicSite)) {
    New-SiteProfile -SiteName "atomic" `
        -BackupPath "\\ecsbackup\backup" `
        -SASToken "?sp=racwdl&st=2026-08-04T21:04:27Z&se=2027-08-05T05:19:27Z&spr=https&sv=2026-02-06&sr=c&sig=qTgpe4K7J%2F9o8LM0JsWTl07WjTYkMFPf0JPs6fPwW6w%3D" |
        Out-File $atomicSite -Encoding UTF8
}

$Config = Load-Config $ConfigFile
$Global:ActiveProfile = $null

# ============================================
# Theme detection
# ============================================
function Get-IsDarkTheme {
    try {
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        $appsUseLight = Get-ItemProperty -Path $key -Name AppsUseLightTheme -ErrorAction Stop
        return ($appsUseLight.AppsUseLightTheme -eq 0)
    } catch { return $false }
}
$IsDark = Get-IsDarkTheme

# ============================================
# Auto-detect SQLCMD
# ============================================
function Get-SqlCmdPath {

    # 1. ECS7 bundled SQLCMD
    $ecsSqlCmd = "C:\Program Files (x86)\ECS7\Manager\sqlcmd.exe"
    if (Test-Path $ecsSqlCmd) { return $ecsSqlCmd }

    # 2. WinGet-installed SQLCMD (ODBC 180)
    $odbc180 = "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\180\Tools\Binn\sqlcmd.exe"
    if (Test-Path $odbc180) { return $odbc180 }

    # 3. WinGet-installed SQLCMD (Microsoft SQLCMD package)
    $wingetSqlCmd = "C:\Program Files\Microsoft SQLCMD\sqlcmd.exe"
    if (Test-Path $wingetSqlCmd) { return $wingetSqlCmd }

    # 4. WinGet Links folder
    $wingetLink = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\sqlcmd.exe"
    if (Test-Path $wingetLink) { return $wingetLink }

    # 5. Standard Microsoft SQL Server SDK locations
    $candidates = @(
        "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\160\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\150\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\140\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\110\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\120\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\130\Tools\Binn\sqlcmd.exe",
        "C:\Program Files\Microsoft SQL Server\140\Tools\Binn\sqlcmd.exe"
    )

    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }

    throw "SQLCMD not found on this system."
}

# ============================================
# Auto-detect AzCopy via WinGet
# ============================================
function Get-AzCopyPath {
    $link = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\azcopy.exe"
    if ($link -and (Test-Path $link)) { return $link }

    $common = @(
        "C:\Program Files (x86)\Microsoft SDKs\Azure\AzCopy\AzCopy.exe",
        "C:\Program Files\Microsoft SDKs\Azure\AzCopy\AzCopy.exe"
    )
    foreach ($p in $common) {
        if (Test-Path $p) { return $p }
    }
    return "azcopy.exe"
}

# ============================================
# BackupPath auto-detect
# ============================================
function Resolve-BackupPath {
    $defaultE = "E:\SQL\BACKUP"
    $defaultC = "C:\SQL\BACKUP"

    if (Test-Path "E:\") {
        if (-not (Test-Path $defaultE)) {
            New-Item -Path $defaultE -ItemType Directory -Force | Out-Null
        }
        return $defaultE
    }

    if (Test-Path $defaultC) {
        return $defaultC
    }

    New-Item -Path $defaultC -ItemType Directory -Force | Out-Null
    return $defaultC
}

# ============================================
# StorageAccount from SAS
# ============================================
function Derive-StorageAccountFromSas {
    param([string]$SasToken)
    if ($SasToken -match "https://(.*?)\.blob\.core\.windows\.net") {
        return $matches[1]
    }
    return "ecsserver"
}

# ============================================
# SAS token validation
# ============================================
function Validate-SasToken {
    param([string]$SasToken)
    if (-not $SasToken -or $SasToken.Trim() -eq "<PLACEHOLDER>") { return $false }
    if ($SasToken -notmatch "\?") { return $false }
    if ($SasToken -notmatch "sig=") { return $false }
    return $true
}

# ============================================
# Config validator
# ============================================
function Validate-Config {
    param([ref]$Config)

    if (-not $Config.Value.ContainsKey("General")) {
        $Config.Value["General"] = @{
            SiteName        = "paradise"
            BackupPath      = "C:\SQL\BACKUP"
            SASToken        = "<PLACEHOLDER>"
            StorageAccount  = "ecsserver"
        }
    }

    if (-not $Config.Value.General.SiteName -or $Config.Value.General.SiteName.Trim() -eq "") {
        $Config.Value.General.SiteName = "paradise"
    }

    if (-not $Config.Value.General.BackupPath -or $Config.Value.General.BackupPath.Trim() -eq "") {
        $Config.Value.General.BackupPath = Resolve-BackupPath
    }

    if (-not (Test-Path $Config.Value.General.BackupPath)) {
        New-Item -Path $Config.Value.General.BackupPath -ItemType Directory -Force | Out-Null
    }

    if (-not $Config.Value.General.SASToken -or $Config.Value.General.SASToken.Trim() -eq "") {
        $Config.Value.General.SASToken = "<PLACEHOLDER>"
    }

    if (-not $Config.Value.General.StorageAccount -or $Config.Value.General.StorageAccount.Trim() -eq "") {
        $Config.Value.General.StorageAccount = Derive-StorageAccountFromSas -SasToken $Config.Value.General.SASToken
    }

    return $Config.Value
}

# ============================================
# Logging
# ============================================
function Write-Log {
    param([string]$Message)
    if (-not $LogFile -or $LogFile.Trim() -eq "") { return }
    $line = "[{0}] {1}" -f (Get-Date), $Message
    Add-Content -Path $LogFile -Value $line
}

# ============================================
# Backup engine
# ============================================
function Backup-Database {
    param(
        [string]$ServerName,
        [string]$BackupPath,
        [string]$DbName,
        [string]$Timestamp,
        [string]$SqlCmdPath
    )

    if (-not $BackupPath -or $BackupPath.Trim() -eq "") {
        throw "Backup-Database: BackupPath is empty."
    }

    $bakFile = Join-Path $BackupPath "$dbName-$timestamp.bak"
    Write-Log "Backing up $dbName to $bakFile"

    $query = "BACKUP DATABASE [$dbName] TO DISK='$bakFile' WITH INIT"
    & $SqlCmdPath -S $ServerName -E -C -Q $query

    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd returned exit code $LASTEXITCODE for $dbName"
    }

    Write-Log "Backup complete for $dbName"
    return $bakFile
}

function Upload-ToAzure {
    param(
        [string]$AzCopyPath,
        [string]$BakFile,
        [string]$StorageAccount,
        [string]$Container,
        [string]$SasToken,
        [string]$DbName,
        [string]$Timestamp
    )

    if (-not $BakFile -or $BakFile.Trim() -eq "") {
        throw "Upload-ToAzure: BakFile path is empty."
    }

    $blobName        = "$dbName-$timestamp.bak"
    $encodedBlobName = [System.Uri]::EscapeDataString($blobName)
    $dest            = "https://$StorageAccount.blob.core.windows.net/$Container/$encodedBlobName$SasToken"

    Write-Log "Uploading $bakFile to Azure container '$container'"
    Write-Log "Destination: $dest"

    & $AzCopyPath copy $BakFile $dest --overwrite=true --from-to=LocalBlob

    if ($LASTEXITCODE -ne 0) {
        throw "AzCopy returned exit code $LASTEXITCODE for $dbName"
    }

    Write-Log "AzCopy upload complete for $dbName"
}

function Clean-Retention {
    param(
        [string]$BackupPath,
        [int]$RetentionDays
    )

    if (-not $BackupPath -or $BackupPath.Trim() -eq "") {
        throw "Clean-Retention: BackupPath is empty."
    }

    Write-Log "Cleaning local backups older than $RetentionDays days..."
    Get-ChildItem -Path $BackupPath -Filter *.bak |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays) } |
        ForEach-Object {
            Write-Log "Deleting: $($_.FullName)"
            Remove-Item $_.FullName -Force
        }
}

function Send-EmailReport {
    param(
        [string]$SiteName,
        [string]$Timestamp,
        [System.Collections.ArrayList]$Errors,
        [string]$SmtpServer,
        [int]$SmtpPort,
        [string]$SmtpUser,
        [string]$SmtpPass,
        [string]$EmailTo,
        [string]$EmailFrom
    )

    if ($Errors.Count -eq 0) {
        $subject = "SQL Backup SUCCESS ($siteName) - $timestamp"
        $body    = "All backups completed successfully for site '$siteName'.`nLog file: $LogFile"
    } else {
        $subject = "SQL Backup FAILURE ($siteName) - $timestamp"
        $body    = "Errors occurred:`n`n" + ($Errors -join "`n") + "`n`nLog file: $LogFile"
    }

    try {
        $securePass = ConvertTo-SecureString $smtpPass -AsPlainText -Force
        $cred       = New-Object System.Management.Automation.PSCredential($smtpUser, $securePass)

        Send-MailMessage -To $emailTo -From $emailFrom -Subject $subject -Body $body `
            -SmtpServer $smtpServer -Port $smtpPort -UseSsl -Credential $cred

        Write-Log "Email sent: $subject"
    }
    catch {
        Write-Log "ERROR sending email: $_"
    }
}

function Start-Backup {
    param(
        $Config,
        [ScriptBlock]$StatusCallback,
        [string]$SelectedSite
    )

    # Load site config
    $siteConfigPath = Join-Path $SitesDir "$SelectedSite.ini"
    $siteConfig = Load-Config $siteConfigPath

    $Config = Validate-Config ([ref]$Config)

    $Config.General.SiteName       = $siteConfig.Site.SiteName
    $Config.General.BackupPath     = $siteConfig.Site.BackupPath
    $Config.General.SASToken       = $siteConfig.Site.SASToken
    $Config.General.StorageAccount = $siteConfig.Site.StorageAccount

    $siteName       = $Config.General.SiteName
    $backupPath     = $Config.General.BackupPath
    $sas            = $Config.General.SASToken
    $storageAccount = $Config.General.StorageAccount

    if (-not (Validate-SasToken $sas)) {
        Write-Log "Invalid SAS token configured."
        $StatusCallback.Invoke("Invalid SAS token.")
        throw "Invalid SAS token."
    }

    $serverName = "ECSSERVER"
    $databases  = @("ECS7", "ECS7_Cloud")
    $localRetentionDays = 3

    $sqlcmd = Get-SqlCmdPath
    $azcopy = Get-AzCopyPath

    Write-Log "SqlCmdPath: $sqlcmd"
    Write-Log "AzCopyPath: $azcopy"

    if (-not (Test-Path $backupPath)) {
        New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $errors = New-Object System.Collections.ArrayList

    Write-Log "==============================="
    Write-Log "Backup started for site: $siteName at $(Get-Date)"
    Write-Log "AppRoot: $AppRoot"
    Write-Log "ProfilesDir: $ProfilesDir"
    Write-Log "SitesDir: $SitesDir"
    Write-Log "LogDir: $LogDir"
    Write-Log "BackupPath: $backupPath"
    Write-Log "==============================="

    & taskkill /IM azcopy.exe /F 2>$null
    Start-Sleep -Seconds 1

    # Progress: starting
    $StatusCallback.Invoke("Starting backup...")
    Update-Progress 10

    foreach ($dbName in $databases) {
        try {
            if ($dbName -eq "ECS7") {
                $StatusCallback.Invoke("Backing up ECS7...")
                Update-Progress 25
            } elseif ($dbName -eq "ECS7_Cloud") {
                $StatusCallback.Invoke("Backing up ECS7_Cloud...")
                Update-Progress 40
            }

            $bakFile = Backup-Database -ServerName $serverName -BackupPath $backupPath `
                                       -DbName $dbName -Timestamp $timestamp -SqlCmdPath $sqlcmd

            if ($dbName -eq "ECS7") {
                $StatusCallback.Invoke("Uploading ECS7 to Azure...")
                Update-Progress 55
            } elseif ($dbName -eq "ECS7_Cloud") {
                $StatusCallback.Invoke("Uploading ECS7_Cloud to Azure...")
                Update-Progress 70
            }

            Upload-ToAzure -AzCopyPath $azcopy -BakFile $bakFile -StorageAccount $storageAccount `
                           -Container $siteName -SasToken $sas -DbName $dbName -Timestamp $timestamp
        }
        catch {
            $msg = "Error backing up ${dbName}: ${_}"
            $errors.Add($msg) | Out-Null
            Write-Log "ERROR: $msg"
        }
    }

    try {
        $StatusCallback.Invoke("Cleaning retention...")
        Update-Progress 80
        Clean-Retention -BackupPath $backupPath -RetentionDays $localRetentionDays
    }
    catch {
        $msg = "Error during retention cleanup: ${_}"
        $errors.Add($msg) | Out-Null
        Write-Log "ERROR: $msg"
    }

    $StatusCallback.Invoke("Sending email report...")
    Update-Progress 90
    Send-EmailReport -SiteName $siteName -Timestamp $timestamp -Errors $errors `
                     -SmtpServer "mail.pacificparadisepark.com" -SmtpPort 587 `
                     -SmtpUser "info@pacificparadisepark.com" -SmtpPass "Starbar1!" `
                     -EmailTo "mike@missionbeachattractions.com" -EmailFrom "info@pacificparadisepark.com"

    Update-Progress 100
    $StatusCallback.Invoke("Backup completed.")
    Write-Log "Backup completed for site '$siteName' at $(Get-Date)"
}

# ============================================
# WinForms GUI
# ============================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "ECS Backup Manager"
$form.Size = New-Object System.Drawing.Size(800,600)
$form.StartPosition = "CenterScreen"

if ($IsDark) {
    $form.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)
    $form.ForeColor = [System.Drawing.Color]::White
} else {
    $form.BackColor = [System.Drawing.Color]::White
    $form.ForeColor = [System.Drawing.Color]::Black
}

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill

$tabSettings = New-Object System.Windows.Forms.TabPage
$tabSettings.Text = "Settings"

$tabStatus = New-Object System.Windows.Forms.TabPage
$tabStatus.Text = "Backup Status"

$tabLogs = New-Object System.Windows.Forms.TabPage
$tabLogs.Text = "Logs"

$tabAbout = New-Object System.Windows.Forms.TabPage
$tabAbout.Text = "About"

$tabs.TabPages.AddRange(@($tabSettings, $tabStatus, $tabLogs, $tabAbout))
$form.Controls.Add($tabs)

# Profile controls (business-level)
$lblProfile = New-Object System.Windows.Forms.Label
$lblProfile.Text = "Profile (Business):"
$lblProfile.Location = New-Object System.Drawing.Point(20,10)
$lblProfile.Size = New-Object System.Drawing.Size(120,20)

$cmbProfiles = New-Object System.Windows.Forms.ComboBox
$cmbProfiles.Location = New-Object System.Drawing.Point(150,8)
$cmbProfiles.Size = New-Object System.Drawing.Size(200,24)
$cmbProfiles.DropDownStyle = "DropDownList"

$cmbProfiles.Items.Clear()
Get-ChildItem -Path $ProfilesDir -Filter *.ini | ForEach-Object {
    $name = $_.BaseName
    [void]$cmbProfiles.Items.Add($name)
}

$btnLoadProfile = New-Object System.Windows.Forms.Button
$btnLoadProfile.Text = "Load Profile"
$btnLoadProfile.Location = New-Object System.Drawing.Point(360,8)
$btnLoadProfile.Size = New-Object System.Drawing.Size(120,24)

$btnSaveProfile = New-Object System.Windows.Forms.Button
$btnSaveProfile.Text = "Save Profile"
$btnSaveProfile.Location = New-Object System.Drawing.Point(490,8)
$btnSaveProfile.Size = New-Object System.Drawing.Size(120,24)

$btnNewProfile = New-Object System.Windows.Forms.Button
$btnNewProfile.Text = "New Profile"
$btnNewProfile.Location = New-Object System.Drawing.Point(620,8)
$btnNewProfile.Size = New-Object System.Drawing.Size(120,24)

# Site controls (location-level)
$lblSite = New-Object System.Windows.Forms.Label
$lblSite.Text = "Site (Location):"
$lblSite.Location = New-Object System.Drawing.Point(20,40)
$lblSite.Size = New-Object System.Drawing.Size(120,20)

$cmbSite = New-Object System.Windows.Forms.ComboBox
$cmbSite.Location = New-Object System.Drawing.Point(150,38)
$cmbSite.Size = New-Object System.Drawing.Size(200,24)
$cmbSite.DropDownStyle = "DropDownList"

$cmbSite.Items.Clear()
Get-ChildItem -Path $SitesDir -Filter *.ini | ForEach-Object {
    $name = $_.BaseName
    [void]$cmbSite.Items.Add($name)
}

$lblBackupPath = New-Object System.Windows.Forms.Label
$lblBackupPath.Text = "Backup Path:"
$lblBackupPath.Location = New-Object System.Drawing.Point(20,80)
$lblBackupPath.Size = New-Object System.Drawing.Size(100,20)

$txtBackupPath = New-Object System.Windows.Forms.TextBox
$txtBackupPath.Location = New-Object System.Drawing.Point(150,78)
$txtBackupPath.Size = New-Object System.Drawing.Size(400,24)
$txtBackupPath.Text = $Config.General.BackupPath

$lblSAS = New-Object System.Windows.Forms.Label
$lblSAS.Text = "SAS Token:"
$lblSAS.Location = New-Object System.Drawing.Point(20,120)
$lblSAS.Size = New-Object System.Drawing.Size(100,20)

$txtSAS = New-Object System.Windows.Forms.TextBox
$txtSAS.Location = New-Object System.Drawing.Point(150,118)
$txtSAS.Size = New-Object System.Drawing.Size(400,24)
$txtSAS.Text = $Config.General.SASToken

$lblStorage = New-Object System.Windows.Forms.Label
$lblStorage.Text = "Storage Account:"
$lblStorage.Location = New-Object System.Drawing.Point(20,160)
$lblStorage.Size = New-Object System.Drawing.Size(120,20)

$txtStorage = New-Object System.Windows.Forms.TextBox
$txtStorage.Location = New-Object System.Drawing.Point(150,158)
$txtStorage.Size = New-Object System.Drawing.Size(200,24)
$txtStorage.Text = $Config.General.StorageAccount

$btnSaveSettings = New-Object System.Windows.Forms.Button
$btnSaveSettings.Text = "Save Settings (default config)"
$btnSaveSettings.Location = New-Object System.Drawing.Point(20,200)
$btnSaveSettings.Size = New-Object System.Drawing.Size(220,30)

$btnSaveSettings.Add_Click({
    $Config.General.SiteName       = $cmbSite.SelectedItem
    $Config.General.BackupPath     = $txtBackupPath.Text
    $Config.General.SASToken       = $txtSAS.Text
    $Config.General.StorageAccount = $txtStorage.Text
    Save-Config -Config $Config -Path $ConfigFile
    [System.Windows.Forms.MessageBox]::Show("Default config saved.","ECS Backup Manager")
})

# Profile load/save/new
$btnLoadProfile.Add_Click({
    $selected = $cmbProfiles.SelectedItem
    if (-not $selected) { return }

    try {
        $profileConfig = Load-Config (Join-Path $ProfilesDir "$selected.ini")
        $Global:ActiveProfile = $selected
        [System.Windows.Forms.MessageBox]::Show("Business profile '$selected' loaded.")
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_)
    }
})

$btnSaveProfile.Add_Click({
    if (-not $Global:ActiveProfile) {
        [System.Windows.Forms.MessageBox]::Show("No profile loaded.")
        return
    }

    $profileConfig = @{
        Profile = @{
            BusinessName = $Global:ActiveProfile
            EmailTo      = "mike@missionbeachattractions.com"
            EmailFrom    = "info@pacificparadisepark.com"
            SMTPServer   = "mail.pacificparadisepark.com"
            SMTPPort     = "587"
            SMTPUser     = "info@pacificparadisepark.com"
            SMTPPass     = "Starbar1!"
        }
    }

    Save-Profile -ProfileName $Global:ActiveProfile -ConfigObject $profileConfig
    [System.Windows.Forms.MessageBox]::Show("Profile '$Global:ActiveProfile' saved.")
})

$btnNewProfile.Add_Click({
    $name = [Microsoft.VisualBasic.Interaction]::InputBox("Enter new business profile name:", "New Profile")
    if ($name -eq "") { return }

    $profilePath = Join-Path $ProfilesDir "$name.ini"
    New-DefaultProfile -BusinessName $name | Out-File $profilePath -Encoding UTF8

    if (-not ($cmbProfiles.Items.Contains($name))) {
        [void]$cmbProfiles.Items.Add($name)
    }
    $cmbProfiles.SelectedItem = $name
    $Global:ActiveProfile = $name

    [System.Windows.Forms.MessageBox]::Show("Business profile '$name' created.")
})

# Site selection handler
$cmbSite.Add_SelectedIndexChanged({
    $selectedSite = $cmbSite.SelectedItem
    if (-not $selectedSite) { return }

    try {
        $siteConfigPath = Join-Path $SitesDir "$selectedSite.ini"
        $siteConfig = Load-Config $siteConfigPath

        $txtBackupPath.Text = $siteConfig.Site.BackupPath
        $txtSAS.Text        = $siteConfig.Site.SASToken
        $txtStorage.Text    = $siteConfig.Site.StorageAccount
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Error loading site '$selectedSite': $_")
    }
})

$tabSettings.Controls.AddRange(@(
    $lblProfile,$cmbProfiles,
    $btnLoadProfile,$btnSaveProfile,$btnNewProfile,
    $lblSite,$cmbSite,
    $lblBackupPath,$txtBackupPath,
    $lblSAS,$txtSAS,
    $lblStorage,$txtStorage,
    $btnSaveSettings
))

# Backup Status tab
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Status: Idle"
$lblStatus.Location = New-Object System.Drawing.Point(20,20)
$lblStatus.Size = New-Object System.Drawing.Size(400,20)

$btnRunBackup = New-Object System.Windows.Forms.Button
$btnRunBackup.Text = "Run Backup Now"
$btnRunBackup.Location = New-Object System.Drawing.Point(20,60)
$btnRunBackup.Size = New-Object System.Drawing.Size(150,30)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20,100)
$progressBar.Size = New-Object System.Drawing.Size(500,25)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0

$tabStatus.Controls.AddRange(@($lblStatus,$btnRunBackup,$progressBar))

# Logs tab
$txtLogs = New-Object System.Windows.Forms.TextBox
$txtLogs.Multiline = $true
$txtLogs.ScrollBars = "Vertical"
$txtLogs.ReadOnly = $true
$txtLogs.Location = New-Object System.Drawing.Point(20, 50)
$txtLogs.Size = New-Object System.Drawing.Size(740, 450)
$tabLogs.Controls.Add($txtLogs)
# Clear Log button
$btnClearLog = New-Object System.Windows.Forms.Button
$btnClearLog.Text = "Clear Log"
$btnClearLog.Location = New-Object System.Drawing.Point(20, 10)
$btnClearLog.Size = New-Object System.Drawing.Size(120, 30)

$btnClearLog.Add_Click({
    try {
        if (Test-Path $LogFile) {
            Clear-Content -Path $LogFile -Force
        }
        $txtLogs.Text = ""
        Write-Log "Log file cleared by user."
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Unable to clear log: $_")
    }
})

# Add button to Logs tab
$tabLogs.Controls.Add($btnClearLog)


function Refresh-Logs {
    if ($txtLogs.InvokeRequired) {
        $txtLogs.Invoke([Action]{
            if (Test-Path $LogFile) {
                $txtLogs.Text = [System.IO.File]::ReadAllText($LogFile)
            } else {
                $txtLogs.Text = "No log file found at $LogFile"
            }
        })
    } else {
        if (Test-Path $LogFile) {
            $txtLogs.Text = [System.IO.File]::ReadAllText($LogFile)
        } else {
            $txtLogs.Text = "No log file found at $LogFile"
        }
    }
}

# About tab
$lblAbout = New-Object System.Windows.Forms.Label
$lblAbout.Text = "ECS Backup Manager`nBusiness profiles + location site profiles."
$lblAbout.Location = New-Object System.Drawing.Point(20,20)
$lblAbout.Size = New-Object System.Drawing.Size(400,80)
$tabAbout.Controls.Add($lblAbout)

# Tray icon
$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = [System.Drawing.SystemIcons]::Information
$tray.Visible = $true
$tray.Text = "ECS Backup Manager"

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miOpen = $trayMenu.Items.Add("Open")
$miExit = $trayMenu.Items.Add("Exit")

$miOpen.Add_Click({ $form.Show(); $form.WindowState = "Normal" })
$miExit.Add_Click({
    $tray.Visible = $false
    $form.Close()
})

$tray.ContextMenuStrip = $trayMenu

$form.Add_Resize({
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        $form.Hide()
        $tray.ShowBalloonTip(1000,"ECS Backup Manager","Still running in tray.",[System.Windows.Forms.ToolTipIcon]::Info)
    }
})

$form.Add_FormClosing({
    $tray.Visible = $false
})

function Update-Status {
    param([string]$Message)
    if ($lblStatus.InvokeRequired) {
        $lblStatus.Invoke([Action]{ $lblStatus.Text = "Status: $Message" })
    } else {
        $lblStatus.Text = "Status: $Message"
    }
}

function Update-Progress {
    param([int]$Value)

    if ($progressBar.InvokeRequired) {
        $progressBar.Invoke([Action]{ $progressBar.Value = $Value })
    } else {
        $progressBar.Value = $Value
    }
}

# Backup button wiring
$btnRunBackup.Add_Click({
    if (-not $cmbSite.SelectedItem) {
        [System.Windows.Forms.MessageBox]::Show("Select a Site (Location) before running backup.")
        return
    }

    Update-Status "Starting backup..."
    Update-Progress 0
    Write-Log "Backup triggered from GUI."

    try {
        if ($Global:ActiveProfile -and $Global:ActiveProfile -ne "") {
            $Config = Load-Config $ConfigFile
        } else {
            $Config = Load-Config $ConfigFile
        }

        # Override with current GUI values (site will be enforced in Start-Backup)
        $Config.General.SiteName       = $cmbSite.SelectedItem
        $Config.General.BackupPath     = $txtBackupPath.Text
        $Config.General.SASToken       = $txtSAS.Text
        $Config.General.StorageAccount = $txtStorage.Text

        $Config = Validate-Config ([ref]$Config)

        Update-Status "Running backup..."
        Start-Backup -Config $Config -StatusCallback { param($m) Update-Status $m } -SelectedSite $cmbSite.SelectedItem

        Update-Status "Refreshing logs..."
        Refresh-Logs

        Update-Status "Backup completed successfully."
        Update-Progress 100
        $tray.ShowBalloonTip(1500, "Backup Complete", "All backup tasks finished.", [System.Windows.Forms.ToolTipIcon]::Info)
    }
    catch {
        Update-Status "Backup failed."
        Write-Log "Backup failed: $_"
        Refresh-Logs
        $tray.ShowBalloonTip(1500, "Backup Failed", "Errors occurred during backup.", [System.Windows.Forms.ToolTipIcon]::Error)
    }
})

Refresh-Logs
[void]$form.ShowDialog()
