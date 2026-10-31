# CONFIG
$SourceServer      = "ECSSERVER"
$TargetServer      = "ECSSTANDBY"

# ECSSERVER backup folder (local)
$SourceBackupPath  = "E:\SQL\BACKUP"

# ECSSTANDBY backup folder (UNC share)
$TargetBackupPath  = "\\ECSSTANDBY\backup"

$Databases         = @("ECS7","ECS7_Cloud")

# Helper: run T-SQL (TCP forced)
function Invoke-Sql {
    param(
        [string]$Server,
        [string]$Query
    )
    sqlcmd -S "tcp:$Server,1433" -C -E -Q $Query
}

# 1) BACKUP on ECSSERVER
foreach ($db in $Databases) {
    $backupFile = Join-Path $SourceBackupPath "$db.bak"
    $query = @"
BACKUP DATABASE [$db]
TO DISK = N'$backupFile'
WITH INIT;
"@
    Write-Host "Backing up $db to $backupFile"
    Invoke-Sql -Server $SourceServer -Query $query
}

# 2) COPY backups to ECSSTANDBY
foreach ($db in $Databases) {
    $src  = Join-Path $SourceBackupPath "$db.bak"
    $dest = Join-Path $TargetBackupPath "$db.bak"

    Write-Host "Copying $src -> $dest"
    Copy-Item $src $dest -Force
}

# 3) RESTORE on ECSSTANDBY
foreach ($db in $Databases) {
    $latest = Join-Path $TargetBackupPath "$db.bak"

    if (-not (Test-Path $latest)) {
        Write-Warning "Backup file missing: $latest"
        continue
    }

    Write-Host "Restoring $db from $latest"

    switch ($db) {
        "ECS7" {
            $dataFile     = "C:\SQLData\ECS7.mdf"
            $logFile      = "C:\SQLData\ECS7_log.ldf"
            $logicalData  = "ECS7"
            $logicalLog   = "ECS7_log"
        }
        "ECS7_Cloud" {
            $dataFile     = "C:\SQLData\ECS7_Cloud.mdf"
            $logFile      = "C:\SQLData\ECS7_Cloud_log.ldf"
            $logicalData  = "ECS7_Cloud"
            $logicalLog   = "ECS7_Cloud_log"
        }
    }

    $restoreQuery = @"
RESTORE DATABASE [$db]
FROM DISK = N'$latest'
WITH REPLACE,
MOVE N'$logicalData' TO N'$dataFile',
MOVE N'$logicalLog' TO N'$logFile',
RECOVERY;
"@

    Invoke-Sql -Server $TargetServer -Query $restoreQuery
}
