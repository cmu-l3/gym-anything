Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\export_investigate_coordinated_intrusion.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Exporting Investigate Coordinated Intrusion Results ==="

    . "C:\workspace\scripts\task_utils.ps1"

    # --- Helper function (same pattern as existing tasks) ---
    function Invoke-DBQuery {
        param([string]$Query)
        try {
            $result = Invoke-ADAuditDBQuery $Query
            if ($result -and $result -notmatch "ERROR:" -and $result -notmatch "FATAL:" -and $result -notmatch "does not exist") {
                return $result.Trim()
            }
        } catch {}
        return $null
    }

    function Find-TechnicianByUsername {
        param([string]$Username)
        $queries = @(
            "SELECT username FROM TechnicianInfo WHERE LOWER(username)=LOWER('$Username')",
            "SELECT username FROM technicianinfo WHERE LOWER(username)=LOWER('$Username')",
            "SELECT username FROM technician WHERE LOWER(username)=LOWER('$Username')",
            "SELECT username FROM techdata WHERE LOWER(username)=LOWER('$Username')"
        )
        foreach ($q in $queries) {
            $r = Invoke-DBQuery -Query $q
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
            $r = Invoke-DBQuery -Query $q
            if ($r -and $r -ne "" -and $r -notmatch "^-") { return $r }
        }
        return $null
    }

    # -----------------------------------------------------------------------
    # Read task start timestamp
    # -----------------------------------------------------------------------
    $taskStart = 0
    try {
        $tsContent = Get-Content "C:\Users\Docker\task_start_ts_coordinated_intrusion.txt" -Raw -ErrorAction Stop
        $taskStart = [long]($tsContent.Trim())
        Write-Host "Task start timestamp: $taskStart"
    } catch {
        Write-Host "Could not read task start timestamp: $_"
    }

    # -----------------------------------------------------------------------
    # Check technician: soc_lead
    # -----------------------------------------------------------------------
    Write-Host "--- Checking technician: soc_lead ---"
    $techExists = $false
    $techRole = ""

    $techResult = Find-TechnicianByUsername "soc_lead"
    if ($techResult -and $techResult -ne "") {
        $techExists = $true
        $roleResult = Find-TechnicianRole "soc_lead"
        if ($roleResult -and $roleResult -ne "") {
            $techRole = $roleResult.Trim()
        }
    }
    Write-Host "soc_lead exists: $techExists, role: $techRole"

    # -----------------------------------------------------------------------
    # Check alert profile: Coordinated Intrusion Detection
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
        $q = "SELECT $($entry.NameCol) FROM $($entry.Table) WHERE LOWER($($entry.NameCol)) LIKE '%coordinated%intrusion%' LIMIT 1;"
        $r = Invoke-DBQuery -Query $q
        if ($r -and $r -ne "") {
            $alertExists = $true
            $alertName = $r.Trim()
            Write-Host "Found alert in table $($entry.Table): $alertName"

            # Get severity
            $sq = "SELECT $($entry.SevCol) FROM $($entry.Table) WHERE LOWER($($entry.NameCol)) LIKE '%coordinated%intrusion%' LIMIT 1;"
            $sr = Invoke-DBQuery -Query $sq
            if ($sr -and $sr -ne "" -and $sr -notmatch "column") {
                $alertSeverity = $sr.Trim()
            }
            break
        }
    }

    # Broader fallback: any alert with "intrusion" in the name
    if (-not $alertExists) {
        foreach ($entry in $alertTables) {
            $q = "SELECT $($entry.NameCol) FROM $($entry.Table) WHERE LOWER($($entry.NameCol)) LIKE '%intrusion%' LIMIT 5;"
            $r = Invoke-DBQuery -Query $q
            if ($r -and $r -ne "") {
                $alertExists = $true
                $alertName = $r.Trim()
                Write-Host "Found intrusion-related alert in $($entry.Table): $alertName"
                break
            }
        }
    }
    Write-Host "Alert exists: $alertExists, name: $alertName, severity: $alertSeverity"

    # -----------------------------------------------------------------------
    # Check notification email for alert
    # -----------------------------------------------------------------------
    Write-Host "--- Checking notification email ---"
    $notifEmail = ""
    $notifHasSoc = $false

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
                $notifHasSoc = $notifEmail -match "soc@meridianfin" -or $notifEmail -match "soc.meridianfin"
                Write-Host "Found email in $($entry.Table).$($col): $notifEmail"
                break
            }
        }
        if ($notifEmail -ne "") { break }
    }
    Write-Host "Notification email: $notifEmail, has soc: $notifHasSoc"

    # -----------------------------------------------------------------------
    # Check SMTP configuration
    # -----------------------------------------------------------------------
    Write-Host "--- Checking SMTP configuration ---"
    $smtpServer = ""
    $smtpQueries = @(
        "SELECT servername FROM MailConfiguration LIMIT 1",
        "SELECT servername FROM mailconfiguration LIMIT 1",
        "SELECT smtp_server FROM mailsettings LIMIT 1",
        "SELECT server FROM smtpconfig LIMIT 1",
        "SELECT servername FROM mailserver LIMIT 1"
    )
    foreach ($q in $smtpQueries) {
        $r = Invoke-DBQuery -Query $q
        if ($r -and $r -ne "" -and $r -notmatch "^-") {
            $smtpServer = $r.Trim()
            Write-Host "SMTP server: $smtpServer"
            break
        }
    }

    $smtpMatchesMeridian = $false
    if ($smtpServer) {
        $smtpMatchesMeridian = $smtpServer -match "mail.meridianfin" -or $smtpServer -match "meridianfin"
    }
    Write-Host "SMTP matches meridianfin: $smtpMatchesMeridian"

    # -----------------------------------------------------------------------
    # Check incident report file
    # -----------------------------------------------------------------------
    Write-Host "--- Checking incident report file ---"
    $reportPath = "C:\Users\Docker\Desktop\incident_report.txt"
    $reportExists = $false
    $reportModTime = 0
    $reportModifiedAfterStart = $false
    $reportContentLength = 0
    $reportFileSize = 0
    $reportHasSvcBackup = $false
    $reportHasMaintSvc = $false
    $reportHasAdministrators = $false
    $reportHasRemoteDesktop = $false
    $reportHasPrivilegeEscalation = $false
    $reportHasBruteForce = $false
    $reportHasRemediation = $false
    $reportHasBackdoor = $false

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
            $reportHasMaintSvc = $cl -match "maint_svc" -or $cl -match "maint.svc" -or $cl -match "maintsvc" -or $cl -match "maintenance.service"
            $reportHasAdministrators = $cl -match "administrator"
            $reportHasRemoteDesktop = $cl -match "remote.desktop" -or $cl -match "rdp"
            $reportHasPrivilegeEscalation = $cl -match "privilege" -or $cl -match "escalat" -or $cl -match "added to.*admin"
            $reportHasBruteForce = $cl -match "brute" -or $cl -match "failed.logon" -or $cl -match "failed.auth" -or $cl -match "credential"
            $reportHasRemediation = $cl -match "remediat" -or $cl -match "recommend" -or $cl -match "disable" -or $cl -match "reset.password" -or $cl -match "mitigat" -or $cl -match "block" -or $cl -match "revoke"
            $reportHasBackdoor = $cl -match "backdoor" -or $cl -match "back.door" -or $cl -match "persistence" -or $cl -match "planted"

            Write-Host "Report content length: $reportContentLength"
            Write-Host "Contains svc_backup: $reportHasSvcBackup"
            Write-Host "Contains maint_svc: $reportHasMaintSvc"
            Write-Host "Contains administrators: $reportHasAdministrators"
            Write-Host "Contains remote desktop: $reportHasRemoteDesktop"
            Write-Host "Contains privilege escalation: $reportHasPrivilegeEscalation"
            Write-Host "Contains brute force: $reportHasBruteForce"
            Write-Host "Contains remediation: $reportHasRemediation"
            Write-Host "Contains backdoor: $reportHasBackdoor"
        } catch {
            Write-Host "Could not read report file: $_"
        }
    }
    Write-Host "Report exists: $reportExists, mod after start: $reportModifiedAfterStart"

    # -----------------------------------------------------------------------
    # Build result JSON
    # -----------------------------------------------------------------------
    $result = [ordered]@{
        task_name                         = "investigate_coordinated_intrusion"
        task_start                        = $taskStart
        export_time                       = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

        # Technician
        tech_soc_lead_exists              = $techExists.ToString().ToLower()
        tech_soc_lead_role                = $techRole

        # Alert profile
        alert_intrusion_exists            = $alertExists.ToString().ToLower()
        alert_intrusion_name              = $alertName
        alert_intrusion_severity          = $alertSeverity

        # Notification email
        notification_email                = $notifEmail
        notification_has_soc              = $notifHasSoc.ToString().ToLower()

        # SMTP
        smtp_server                       = $smtpServer
        smtp_matches_meridian             = $smtpMatchesMeridian.ToString().ToLower()

        # Incident report file
        report_file_exists                = $reportExists.ToString().ToLower()
        report_file_size                  = $reportFileSize
        report_file_mod_time              = $reportModTime
        report_file_modified_after_start  = $reportModifiedAfterStart.ToString().ToLower()
        report_content_length             = $reportContentLength
        report_has_svc_backup             = $reportHasSvcBackup.ToString().ToLower()
        report_has_maint_svc              = $reportHasMaintSvc.ToString().ToLower()
        report_has_administrators         = $reportHasAdministrators.ToString().ToLower()
        report_has_remote_desktop         = $reportHasRemoteDesktop.ToString().ToLower()
        report_has_privilege_escalation   = $reportHasPrivilegeEscalation.ToString().ToLower()
        report_has_brute_force            = $reportHasBruteForce.ToString().ToLower()
        report_has_remediation            = $reportHasRemediation.ToString().ToLower()
        report_has_backdoor               = $reportHasBackdoor.ToString().ToLower()
    }

    $outputPath = "C:\Users\Docker\investigate_coordinated_intrusion_result.json"
    $result | ConvertTo-Json -Depth 5 | Out-File -FilePath $outputPath -Encoding UTF8
    Write-Host "Result exported to $outputPath"

    Write-Host "=== Investigate Coordinated Intrusion Export Complete ==="
} catch {
    Write-Host "EXPORT ERROR: $_"
    Write-Host $_.ScriptStackTrace

    # Write minimal fallback result
    @"
{
  "task_name": "investigate_coordinated_intrusion",
  "task_start": 0, "export_time": 0,
  "tech_soc_lead_exists": "false", "tech_soc_lead_role": "",
  "alert_intrusion_exists": "false", "alert_intrusion_name": "", "alert_intrusion_severity": "",
  "notification_email": "", "notification_has_soc": "false",
  "smtp_server": "", "smtp_matches_meridian": "false",
  "report_file_exists": "false", "report_file_size": 0, "report_file_mod_time": 0,
  "report_file_modified_after_start": "false", "report_content_length": 0,
  "report_has_svc_backup": "false", "report_has_maint_svc": "false",
  "report_has_administrators": "false", "report_has_remote_desktop": "false",
  "report_has_privilege_escalation": "false", "report_has_brute_force": "false",
  "report_has_remediation": "false", "report_has_backdoor": "false",
  "export_error": "true"
}
"@ | Out-File "C:\Users\Docker\investigate_coordinated_intrusion_result.json" -Encoding UTF8 -NoNewline
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
