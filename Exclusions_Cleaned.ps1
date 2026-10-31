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
#Exclusions for EMBED & SQL
Add-MpPreference -ExclusionProcess "sqlservr.exe"
Add-MpPreference -ExclusionProcess "sqlwriter.exe"
Add-MpPreference -ExclusionProcess "ssms.exe"
Add-MpPreference -ExclusionProcess "sqlcmd.exe"
Add-MpPreference -ExclusionProcess "anydesk.exe"
Add-MpPreference -ExclusionPath "C:\Program Files\Microsoft SQL Server"
Add-MpPreference -ExclusionPath "C:\Program Files\Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL"
Add-MpPreference -ExclusionPath "C:\Program Files\Microsoft SQL Server\MSSQL16.SQLEXPRESS\MSSQL"
Add-MpPreference -ExclusionPath "C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL"
Add-MpPreference -ExclusionPath "C:\SQL"
Add-MpPreference -ExclusionPath "C:\Backup"
Add-MpPreference -ExclusionPath "C:\Program Files (x86)\ECS7"
Add-MpPreference -ExclusionPath "C:\inetpub\wwwroot\EcsReports"
Add-MpPreference -ExclusionPath "D:\SQL"
