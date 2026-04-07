Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\export_forensic_attack_chain_analysis.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Exporting Forensic Attack Chain Analysis Results ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # --- Helper function (same pattern as existing tasks) ---
    function Invoke-DBQuery {
        param([string]$Query)
        try {
            $result = Invoke-ADAuditDBQuery $Query
            if ($result -and $result -notmatch "ERROR:" -and $result -notmatch "does not exist") {
                return $result.Trim()
            }
        } catch {}
        return $null
    }

    # -----------------------------------------------------------------------
    # Read task start timestamp
    # -----------------------------------------------------------------------
    $taskStart = 0
    try {
        $tsContent = Get-Content "C:\Users\Docker\task_start_ts_forensic_attack_chain.txt" -Raw -ErrorAction Stop
        $taskStart = [long]($tsContent.Trim())
        Write-Host "Task start timestamp: $taskStart"
    } catch {
        Write-Host "Could not read task start timestamp: $_"
    }

    # -----------------------------------------------------------------------
    # Check technician: forensic_lead
    # -----------------------------------------------------------------------
    Write-Host "--- Checking technician: forensic_lead ---"
    $techExists = $false
    $techRole = ""

    $tableNames = @("TechnicianInfo", "technicianinfo", "technician", "techdata", "adap_technician")
    foreach ($table in $tableNames) {
        $q = "SELECT username FROM $table WHERE LOWER(username) = 'forensic_lead' LIMIT 1;"
        $r = Invoke-DBQuery -Query $q
        if ($r -and $r -ne "") {
            $techExists = $true
            Write-Host "Found forensic_lead in table: $table"

            # Try to get role
            $roleColumns = @("role", "technician_role", "userrole", "access_level")
            foreach ($col in $roleColumns) {
                $rq = "SELECT $col FROM $table WHERE LOWER(username) = 'forensic_lead' LIMIT 1;"
                $rr = Invoke-DBQuery -Query $rq
                if ($rr -and $rr -ne "" -and $rr -notmatch "column") {
                    $techRole = $rr.Trim()
                    break
                }
            }
            break
        }
    }
    Write-Host "forensic_lead exists: $techExists, role: $techRole"

    # -----------------------------------------------------------------------
    # Check alert profile: APT Campaign Detection
    # -----------------------------------------------------------------------
    Write-Host "--- Checking alert profile ---"
    $alertExists = $false
    $alertName = ""
    $alertSeverity = ""

    $alertTables = @(
        @{Table="AlertProfile"; NameCol="name"; SevCol="severity"},
        @{Table="alertprofile"; NameCol="name"; SevCol="severity"},
        @{Table="NotificationProfile"; NameCol="name"; SevCol="severity"},
        @{Table="notificationprofile"; NameCol="name"; SevCol="severity"},
        @{Table="alert_config"; NameCol="name"; SevCol="severity"},
        @{Table="AlertMeProfile"; NameCol="profilename"; SevCol="severity"}
    )

    foreach ($entry in $alertTables) {
        $q = "SELECT $($entry.NameCol) FROM $($entry.Table) WHERE LOWER($($entry.NameCol)) LIKE '%apt%campaign%' LIMIT 1;"
        $r = Invoke-DBQuery -Query $q
        if ($r -and $r -ne "") {
            $alertExists = $true
            $alertName = $r.Trim()
            Write-Host "Found alert in table $($entry.Table): $alertName"

            # Get severity
            $sq = "SELECT $($entry.SevCol) FROM $($entry.Table) WHERE LOWER($($entry.NameCol)) LIKE '%apt%campaign%' LIMIT 1;"
            $sr = Invoke-DBQuery -Query $sq
            if ($sr -and $sr -ne "" -and $sr -notmatch "column") {
                $alertSeverity = $sr.Trim()
            }
            break
        }
    }

    # Broader fallback: any alert with "APT" in the name
    if (-not $alertExists) {
        foreach ($entry in $alertTables) {
            $q = "SELECT $($entry.NameCol) FROM $($entry.Table) WHERE LOWER($($entry.NameCol)) LIKE '%apt%' LIMIT 5;"
            $r = Invoke-DBQuery -Query $q
            if ($r -and $r -ne "") {
                $alertExists = $true
                $alertName = $r.Trim()
                Write-Host "Found APT-related alert in $($entry.Table): $alertName"
                break
            }
        }
    }
    Write-Host "Alert exists: $alertExists, name: $alertName, severity: $alertSeverity"

    # -----------------------------------------------------------------------
    # Check notification email configuration
    # -----------------------------------------------------------------------
    Write-Host "--- Checking notification email ---"
    $notifEmail = ""
    $notifHasSocLead = $false

    $notifTables = @(
        @{Table="NotificationProfile"; Cols=@("email", "email_address", "toaddress", "recipient")},
        @{Table="notificationprofile"; Cols=@("email", "email_address", "toaddress", "recipient")},
        @{Table="AlertProfile"; Cols=@("email", "email_address", "toaddress", "recipient")},
        @{Table="alertprofile"; Cols=@("email", "email_address", "toaddress", "recipient")},
        @{Table="EmailNotification"; Cols=@("email", "email_address", "toaddress")},
        @{Table="emailnotification"; Cols=@("email", "email_address", "toaddress")},
        @{Table="MailConfig"; Cols=@("toemail", "email", "mail_to")},
        @{Table="mailconfig"; Cols=@("toemail", "email", "mail_to")}
    )

    foreach ($entry in $notifTables) {
        foreach ($col in $entry.Cols) {
            $q = "SELECT $col FROM $($entry.Table) WHERE $col IS NOT NULL AND $col <> '' LIMIT 5;"
            $r = Invoke-DBQuery -Query $q
            if ($r -and $r -ne "") {
                $notifEmail = $r.Trim()
                $notifHasSocLead = $notifEmail -match "soc-lead" -or $notifEmail -match "soc.lead"
                Write-Host "Found email in $($entry.Table).$($col): $notifEmail"
                break
            }
        }
        if ($notifEmail -ne "") { break }
    }
    Write-Host "Notification email: $notifEmail, has soc-lead: $notifHasSocLead"

    # -----------------------------------------------------------------------
    # Check forensic report file
    # -----------------------------------------------------------------------
    Write-Host "--- Checking forensic report file ---"
    $reportPath = "C:\Users\Docker\Desktop\attack_campaign_report.txt"
    $reportExists = $false
    $reportModTime = 0
    $reportModifiedAfterStart = $false
    $reportContentLength = 0
    $reportFileSize = 0
    $reportHasSvcBackup = $false
    $reportHasAdministrators = $false
    $reportHasPrivilegeEscalation = $false
    $reportHasBruteForce = $false
    $reportHasRemediation = $false

    if (Test-Path $reportPath) {
        $reportExists = $true
        $fileInfo = Get-Item $reportPath
        $reportFileSize = $fileInfo.Length
        $reportModTime = [System.DateTimeOffset]::new($fileInfo.LastWriteTimeUtc).ToUnixTimeSeconds()

        if ($taskStart -gt 0 -and $reportModTime -gt $taskStart) {
            $reportModifiedAfterStart = $true
        }

        try {
            $content = Get-Content $reportPath -Raw -Encoding UTF8 -ErrorAction Stop
            if (-not $content) {
                $content = Get-Content $reportPath -Raw -Encoding Default -ErrorAction Stop
            }
            $reportContentLength = $content.Length

            $cl = $content.ToLower()
            $reportHasSvcBackup = $cl -match "svc_backup" -or $cl -match "svc.backup" -or $cl -match "svcbackup"
            $reportHasAdministrators = $cl -match "administrator"
            $reportHasPrivilegeEscalation = $cl -match "privilege" -or $cl -match "escalat" -or $cl -match "added to.*admin"
            $reportHasBruteForce = $cl -match "brute" -or $cl -match "failed.logon" -or $cl -match "failed.auth" -or $cl -match "credential.attack"
            $reportHasRemediation = $cl -match "remediat" -or $cl -match "recommend" -or $cl -match "disable" -or $cl -match "reset.password" -or $cl -match "mitigat"

            Write-Host "Report content length: $reportContentLength"
            Write-Host "Contains svc_backup: $reportHasSvcBackup"
            Write-Host "Contains administrators: $reportHasAdministrators"
            Write-Host "Contains privilege escalation: $reportHasPrivilegeEscalation"
            Write-Host "Contains brute force: $reportHasBruteForce"
            Write-Host "Contains remediation: $reportHasRemediation"
        } catch {
            Write-Host "Could not read report file: $_"
        }
    }
    Write-Host "Report exists: $reportExists, mod after start: $reportModifiedAfterStart"

    # -----------------------------------------------------------------------
    # Build result JSON
    # -----------------------------------------------------------------------
    $result = [ordered]@{
        task_name                         = "forensic_attack_chain_analysis"
        task_start                        = $taskStart
        export_time                       = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

        # Technician
        tech_forensic_lead_exists         = $techExists.ToString().ToLower()
        tech_forensic_lead_role           = $techRole

        # Alert profile
        alert_apt_campaign_exists         = $alertExists.ToString().ToLower()
        alert_apt_campaign_name           = $alertName
        alert_apt_campaign_severity       = $alertSeverity

        # Notification email
        notification_email                = $notifEmail
        notification_has_soc_lead         = $notifHasSocLead.ToString().ToLower()

        # Forensic report file
        report_file_exists                = $reportExists.ToString().ToLower()
        report_file_size                  = $reportFileSize
        report_file_mod_time              = $reportModTime
        report_file_modified_after_start  = $reportModifiedAfterStart.ToString().ToLower()
        report_content_length             = $reportContentLength
        report_has_svc_backup             = $reportHasSvcBackup.ToString().ToLower()
        report_has_administrators         = $reportHasAdministrators.ToString().ToLower()
        report_has_privilege_escalation   = $reportHasPrivilegeEscalation.ToString().ToLower()
        report_has_brute_force            = $reportHasBruteForce.ToString().ToLower()
        report_has_remediation            = $reportHasRemediation.ToString().ToLower()
    }

    $outputPath = "C:\Users\Docker\forensic_attack_chain_analysis_result.json"
    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $outputPath -Encoding UTF8
    Write-Host "Result exported to $outputPath"

    Write-Host "=== Forensic Attack Chain Analysis Export Complete ==="
} catch {
    Write-Host "EXPORT ERROR: $_"
    Write-Host $_.ScriptStackTrace

    # Write minimal fallback result
    @"
{
  "task_name": "forensic_attack_chain_analysis",
  "task_start": 0, "export_time": 0,
  "tech_forensic_lead_exists": "false", "tech_forensic_lead_role": "",
  "alert_apt_campaign_exists": "false", "alert_apt_campaign_name": "", "alert_apt_campaign_severity": "",
  "notification_email": "", "notification_has_soc_lead": "false",
  "report_file_exists": "false", "report_file_size": 0, "report_file_mod_time": 0,
  "report_file_modified_after_start": "false", "report_content_length": 0,
  "report_has_svc_backup": "false", "report_has_administrators": "false",
  "report_has_privilege_escalation": "false", "report_has_brute_force": "false",
  "report_has_remediation": "false",
  "export_error": "true"
}
"@ | Out-File "C:\Users\Docker\forensic_attack_chain_analysis_result.json" -Encoding UTF8 -NoNewline
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
