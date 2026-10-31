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
# Data, Log, Backup Dir
Add-MpPreference -ExclusionPath "C:\Program Files (x86)\ECS7\"
Add-MpPreference -ExclusionPath "E:\SQL\BACKUP\"
Add-MpPreference -ExclusionPath "C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\DATA"
Add-MpPreference -ExclusionPath "C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Log"
# SQL Server
Add-MpPreference -ExclusionProcess "C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\Binn\sqlservr.exe"
# SQL FILE EXTENSIONS
Add-MpPreference -ExclusionExtension "mdf"
Add-MpPreference -ExclusionExtension "ndf"
Add-MpPreference -ExclusionExtension "ldf"
Add-MpPreference -ExclusionExtension "bak"
Add-MpPreference -ExclusionExtension "trn"
# Confirm Complete
Write-Host "SQL Defender Script Complete"
