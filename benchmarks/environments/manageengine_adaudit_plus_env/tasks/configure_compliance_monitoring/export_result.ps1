Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$logPath = "C:\Users\Docker\export_configure_compliance_monitoring.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Exporting configure_compliance_monitoring results ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # ---- DB helper: safe query that swallows errors ----
    function Invoke-SafeDBQuery {
        param([string]$Query)
        try {
            $r = Invoke-ADAuditDBQuery $Query
            if ($r -and $r -notmatch "ERROR:" -and $r -notmatch "FATAL:" -and $r -notmatch "does not exist") {
                return $r.Trim()
            }
        } catch {}
        return $null
    }

    # ---- Check technician by username ----
    function Find-TechnicianByUsername {
        param([string]$Username)
        $queries = @(
            "SELECT username FROM TechnicianInfo WHERE LOWER(username)=LOWER('$Username')",
            "SELECT username FROM technicianinfo WHERE LOWER(username)=LOWER('$Username')",
            "SELECT username FROM technician WHERE LOWER(username)=LOWER('$Username')",
            "SELECT username FROM techdata WHERE LOWER(username)=LOWER('$Username')"
        )
        foreach ($q in $queries) {
            $r = Invoke-SafeDBQuery $q
            if ($r -and $r -ne "" -and $r -notmatch "^-") { return $r }
        }
        return $null
    }

    function Find-TechnicianRole {
        param([string]$Username)
        $queries = @(
            "SELECT role FROM TechnicianInfo WHERE LOWER(username)=LOWER('$Username')",
            "SELECT role FROM technicianinfo WHERE LOWER(username)=LOWER('$Username')",
            "SELECT role FROM technician WHERE LOWER(username)=LOWER('$Username')",
            "SELECT techniciantype FROM TechnicianInfo WHERE LOWER(username)=LOWER('$Username')"
        )
        foreach ($q in $queries) {
            $r = Invoke-SafeDBQuery $q
            if ($r -and $r -ne "" -and $r -notmatch "^-") { return $r }
        }
        return $null
    }

    # ---- Check scheduled report by name pattern ----
    function Find-ScheduledReport {
        param([string]$NamePattern)
        # SQL LIKE wildcard for partial match
        $likePattern = "%$NamePattern%"
        $queries = @(
            "SELECT report_name FROM ScheduledReportInfo WHERE LOWER(report_name) LIKE LOWER('$likePattern')",
            "SELECT reportname FROM scheduledreportinfo WHERE LOWER(reportname) LIKE LOWER('$likePattern')",
            "SELECT report_name FROM schedulereport WHERE LOWER(report_name) LIKE LOWER('$likePattern')",
            "SELECT name FROM scheduled_reports WHERE LOWER(name) LIKE LOWER('$likePattern')",
            "SELECT report_name FROM sch_reports WHERE LOWER(report_name) LIKE LOWER('$likePattern')"
        )
        foreach ($q in $queries) {
            $r = Invoke-SafeDBQuery $q
            if ($r -and $r -ne "" -and $r -notmatch "^-") { return $r }
        }
        return $null
    }

    # ---- Check SMTP server configuration ----
    function Get-SMTPServer {
        $queries = @(
            "SELECT servername FROM MailConfiguration LIMIT 1",
            "SELECT servername FROM mailconfiguration LIMIT 1",
            "SELECT smtp_server FROM mailsettings LIMIT 1",
            "SELECT server FROM smtpconfig LIMIT 1",
            "SELECT servername FROM mailserver LIMIT 1"
        )
        foreach ($q in $queries) {
            $r = Invoke-SafeDBQuery $q
            if ($r -and $r -ne "" -and $r -notmatch "^-") { return $r }
        }
        return $null
    }

    # ---- Check notification email ----
    function Get-NotificationEmail {
        $queries = @(
            "SELECT email FROM NotificationSettings LIMIT 3",
            "SELECT email FROM notificationsettings LIMIT 3",
            "SELECT emailid FROM AlertMeSettings LIMIT 3",
            "SELECT emailid FROM alertmesettings LIMIT 3",
            "SELECT notification_email FROM notification_config LIMIT 3"
        )
        foreach ($q in $queries) {
            $r = Invoke-SafeDBQuery $q
            if ($r -and $r -ne "" -and $r -notmatch "^-") { return $r }
        }
        return $null
    }

    # ---- Run checks ----
    $taskStart = 0
    try { $taskStart = [long](Get-Content "C:\Users\Docker\task_start_timestamp.txt" -Raw) } catch {}

    $techGdprExists = $null
    $techGdprRole = $null
    try {
        $techGdprExists = Find-TechnicianByUsername "gdpr_auditor"
        if ($techGdprExists) { $techGdprRole = Find-TechnicianRole "gdpr_auditor" }
    } catch {}

    $smtpServer = $null
    try { $smtpServer = Get-SMTPServer } catch {}

    $report1Found = $null
    try { $report1Found = Find-ScheduledReport "User Account Changes" } catch {}

    $report2Found = $null
    try { $report2Found = Find-ScheduledReport "Privileged Access" } catch {}

    $notifEmail = $null
    try { $notifEmail = Get-NotificationEmail } catch {}

    # Check if noc@internal.corp appears in notification email
    $notifHasNoc = $false
    if ($notifEmail) { $notifHasNoc = $notifEmail -match "noc@internal.corp" -or $notifEmail -match "noc" }

    # Check SMTP matches expected
    $smtpMatches = $false
    if ($smtpServer) { $smtpMatches = $smtpServer -match "smtp.internal.corp" -or $smtpServer -match "smtp" }

    # ---- Write result JSON ----
    $taskEnd = [long]([System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $resultPath = "C:\Users\Docker\configure_compliance_monitoring_result.json"

    $resultJson = @"
{
  "task_name": "configure_compliance_monitoring",
  "task_start": $taskStart,
  "task_end": $taskEnd,
  "tech_gdpr_auditor_exists": $(if ($techGdprExists -and $techGdprExists -ne "") { "true" } else { "false" }),
  "tech_gdpr_auditor_role": "$(if ($techGdprRole) { $techGdprRole.Trim() -replace '"', '' } else { '' })",
  "smtp_server": "$(if ($smtpServer) { $smtpServer.Trim() -replace '"', '' } else { '' })",
  "smtp_matches_expected": $(if ($smtpMatches) { "true" } else { "false" }),
  "report1_found": $(if ($report1Found -and $report1Found -ne "") { "true" } else { "false" }),
  "report1_name": "$(if ($report1Found) { $report1Found.Trim() -replace '"', '' } else { '' })",
  "report2_found": $(if ($report2Found -and $report2Found -ne "") { "true" } else { "false" }),
  "report2_name": "$(if ($report2Found) { $report2Found.Trim() -replace '"', '' } else { '' })",
  "notification_email": "$(if ($notifEmail) { ($notifEmail -split '\n')[0].Trim() -replace '"', '' } else { '' })",
  "notification_has_noc": $(if ($notifHasNoc) { "true" } else { "false" })
}
"@

    $resultJson | Out-File $resultPath -Encoding UTF8 -NoNewline
    Write-Host "Results written to: $resultPath"
    Write-Host "Tech gdpr_auditor exists: $($techGdprExists -ne $null -and $techGdprExists -ne '')"
    Write-Host "SMTP server: $smtpServer"
    Write-Host "Report1 (Daily): $report1Found"
    Write-Host "Report2 (Weekly): $report2Found"
    Write-Host "Notification email: $notifEmail"

    Write-Host "=== Export complete ==="
} catch {
    Write-Host "EXPORT ERROR: $_"
    @"
{
  "task_name": "configure_compliance_monitoring",
  "task_start": 0, "task_end": 0,
  "tech_gdpr_auditor_exists": false,
  "tech_gdpr_auditor_role": "",
  "smtp_server": "",
  "smtp_matches_expected": false,
  "report1_found": false, "report1_name": "",
  "report2_found": false, "report2_name": "",
  "notification_email": "",
  "notification_has_noc": false,
  "export_error": true
}
"@ | Out-File "C:\Users\Docker\configure_compliance_monitoring_result.json" -Encoding UTF8 -NoNewline
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
