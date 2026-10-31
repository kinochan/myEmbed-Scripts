# =========================
# ECS7 / ECS7_Cloud Sync Script
# Backup on ECSSERVER -> Copy -> Restore on ECSSTANDBY
# With logging, email alerts, health checks, and simple dashboard
# =========================

# -------------------------
# CONFIG
# -------------------------
$SourceServer      = "ECSSERVER"
$TargetServer      = "ECSSTANDBY"

# ECSSERVER backup folder (local)
$SourceBackupPath  = "E:\SQL\BACKUP"

# ECSSTANDBY backup folder (UNC share)
$TargetBackupPath  = "\\ECSSTANDBY\backup"

$Databases         = @("ECS7","ECS7_Cloud")

# Logging
$LogFolder         = "C:\Logs\ECS_Sync"
# Auto-clean logs older than 7 days
$LogRetentionDays = 7
Get-ChildItem -Path $LogFolder -Filter "*.log" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$LogRetentionDays) } |
    Remove-Item -Force -ErrorAction SilentlyContinue
$LogFile           = Join-Path $LogFolder ("ECS_Sync_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

# Email alerts
#$EnableEmail       = $true
#$SmtpServer        = "mail.mailserver.com"  # TODO: set real SMTP
#$FromAddress       = "user@mailserver.com"  # TODO: set real sender
#$ToAddress         = "user@mailserver.com"  # TODO: set real recipient

# Ensure log folder exists
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory | Out-Null
}

# -------------------------
# Logging / Alert helpers
# -------------------------
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Send-Alert {
    param(
        [string]$Subject,
        [string]$Body
    )
    if (-not $EnableEmail) { return }

    try {
        Send-MailMessage -SmtpServer $SmtpServer -From $FromAddress -To $ToAddress -Subject $Subject -Body $Body
        Write-Log "Alert email sent: $Subject" "INFO"
    }
    catch {
        Write-Log "Failed to send alert email: $($_.Exception.Message)" "ERROR"
    }
}

# -------------------------
# SQL helper (TCP forced)
# -------------------------
function Invoke-Sql {
    param(
        [string]$Server,
        [string]$Query
    )
    Write-Log "SQL on ${Server}: ${Query}" "DEBUG"
    sqlcmd -S "tcp:$Server,1433" -C -E -Q $Query
}

# -------------------------
# Health check
# -------------------------
function Run-HealthCheck {
    Write-Log "=== HEALTH CHECK START ===" "INFO"

    # Services on ECSSTANDBY
    Write-Log "Checking SQL services on ECSSTANDBY" "INFO"
    try {
        $services = Get-Service -ComputerName $TargetServer MSSQLSERVER, SQLBrowser, SQLWriter -ErrorAction Stop
        foreach ($svc in $services) {
            Write-Log ("Service {0} - Status: {1}, StartType: {2}" -f $svc.Name, $svc.Status, $svc.StartType) "INFO"
        }
    }
    catch {
        Write-Log "Failed to query services on ECSSTANDBY: $($_.Exception.Message)" "ERROR"
        Send-Alert "ECS Sync Health Check Failed (Services)" "Failed to query SQL services on ECSSTANDBY.`n`n$($_.Exception.Message)"
    }

    # Connectivity + identity
    Write-Log "Checking SQL connectivity to ECSSTANDBY" "INFO"
    try {
        $query = "SELECT @@VERSION AS Version, SUSER_SNAME() AS Login;"
        Invoke-Sql -Server $TargetServer -Query $query | ForEach-Object { Write-Log $_ "INFO" }
    }
    catch {
        Write-Log "Failed to connect to ECSSTANDBY SQL: $($_.Exception.Message)" "ERROR"
        Send-Alert "ECS Sync Health Check Failed (Connectivity)" "Failed to connect to ECSSTANDBY SQL.`n`n$($_.Exception.Message)"
    }

    # Database states
    Write-Log "Checking database states on ECSSTANDBY" "INFO"
    try {
        $dbQuery = @"
SELECT name, state_desc, user_access_desc
FROM sys.databases
WHERE name IN ('ECS7','ECS7_Cloud');
"@
        Invoke-Sql -Server $TargetServer -Query $dbQuery | ForEach-Object { Write-Log $_ "INFO" }
    }
    catch {
        Write-Log "Failed to query database states on ECSSTANDBY: $($_.Exception.Message)" "ERROR"
        Send-Alert "ECS Sync Health Check Failed (DB State)" "Failed to query database states on ECSSTANDBY.`n`n$($_.Exception.Message)"
    }

    Write-Log "=== HEALTH CHECK END ===" "INFO"
}

# -------------------------
# MAIN
# -------------------------
Write-Log "=== ECS SYNC START ===" "INFO"

# Run health check before sync
Run-HealthCheck

# 1) BACKUP on ECSSERVER
foreach ($db in $Databases) {
    $backupFile = Join-Path $SourceBackupPath "$db.bak"
    $query = @"
BACKUP DATABASE [$db]
TO DISK = N'$backupFile'
WITH INIT;
"@
    Write-Log "Backing up $db to $backupFile" "INFO"
    try {
        Invoke-Sql -Server $SourceServer -Query $query
        Write-Log "Backup completed for $db" "INFO"
    }
    catch {
        Write-Log "Backup FAILED for ${db}: $($_.Exception.Message)" "ERROR"
        Send-Alert "ECS Sync Backup FAILED ($db)" "Backup failed for $db on $SourceServer.`n`n$($_.Exception.Message)"
        continue
    }
}

# 2) COPY backups to ECSSTANDBY
foreach ($db in $Databases) {
    $src  = Join-Path $SourceBackupPath "$db.bak"
    $dest = Join-Path $TargetBackupPath "$db.bak"

    Write-Log "Copying $src -> $dest" "INFO"
    try {
        Copy-Item $src $dest -Force
        Write-Log "Copy completed for $db" "INFO"
    }
    catch {
        Write-Log "Copy FAILED for ${db}: $($_.Exception.Message)" "ERROR"
        Send-Alert "ECS Sync Copy FAILED ($db)" "Copy failed for $db from $src to $dest.`n`n$($_.Exception.Message)"
        continue
    }
}
# 3) RESTORE on ECSSTANDBY
foreach ($db in $Databases) {
    $latest = Join-Path $TargetBackupPath "$db.bak"

    if (-not (Test-Path $latest)) {
        Write-Log "Backup file missing for ${db}: ${latest}" "ERROR"
        Send-Alert "ECS Sync Restore FAILED (${db})" "Backup file missing on ECSSTANDBY: ${latest}"
        continue
    }

    Write-Log "Preparing restore for ${db}" "INFO"

    # --- AUTO-FIX: Detect if database is stuck in RESTORING mode ---
    $checkStateQuery = "SELECT state_desc FROM sys.databases WHERE name = '$db';"
    $stateResult = Invoke-Sql -Server $TargetServer -Query $checkStateQuery

    if ($stateResult -match "RESTORING") {
        Write-Log "Database $db is stuck in RESTORING mode. Resetting with NORECOVERY..." "WARN"
        Invoke-Sql -Server $TargetServer -Query "RESTORE DATABASE [$db] WITH NORECOVERY;"
    }

    # --- Correct file paths for ECSSTANDBY ---
    switch ($db) {
        "ECS7" {
            $RestoreDataFile = "C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\DATA\ECS7.mdf"
            $RestoreLogFile  = "C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\DATA\ECS7_log.ldf"
            $UndoFile        = "C:\SQL\UNDO\ECS7_undo.tuf"
            $logicalData     = "ECS7"
            $logicalLog      = "ECS7_log"
        }
        "ECS7_Cloud" {
            $RestoreDataFile = "C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\DATA\ECS7_Cloud.mdf"
            $RestoreLogFile  = "C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\DATA\ECS7_Cloud_Log.ldf"
            $UndoFile        = "C:\SQL\UNDO\ECS7_Cloud_undo.tuf"
            $logicalData     = "ECS7_Cloud"
            $logicalLog      = "ECS7_Cloud_Log"
        }
    }

    # Ensure UNDO folder exists
    $undoFolder = Split-Path $UndoFile
    if (-not (Test-Path $undoFolder)) {
        New-Item -ItemType Directory -Path $undoFolder | Out-Null
        Write-Log "Created UNDO folder: $undoFolder" "INFO"
    }

    # --- STANDBY restore ---
    $restoreQuery = @"
RESTORE DATABASE [$db]
FROM DISK = N'$latest'
WITH REPLACE,
MOVE N'$logicalData' TO N'$RestoreDataFile',
MOVE N'$logicalLog' TO N'$RestoreLogFile',
STANDBY = N'$UndoFile';
"@

    try {
        Write-Log "Restoring ${db} with STANDBY mode..." "INFO"
        Invoke-Sql -Server $TargetServer -Query $restoreQuery
        Write-Log "Restore completed for ${db} (STANDBY mode)" "INFO"
    }
    catch {
        Write-Log "Restore FAILED for ${db}: $($_.Exception.Message)" "ERROR"
        Send-Alert "ECS Sync Restore FAILED (${db})" "Restore failed for ${db} on ECSSTANDBY.`n`n$($_.Exception.Message)"
        continue
    }
}


Write-Log "=== ECS SYNC COMPLETE ===" "INFO"

# Write last successful sync status
$StatusFile = "C:\Logs\ECS_Sync\LastSuccessfulSync.txt"

$StatusContent = @"
Last Successful Sync: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Source Server: $SourceServer
Target Server: $TargetServer
Databases Synced: $($Databases -join ", ")
Log File: $LogFile
"@

Set-Content -Path $StatusFile -Value $StatusContent
Write-Log "Updated last successful sync status file: $StatusFile" "INFO"

Write-Log "Dashboard: see log file $LogFile for full run details." "INFO"
