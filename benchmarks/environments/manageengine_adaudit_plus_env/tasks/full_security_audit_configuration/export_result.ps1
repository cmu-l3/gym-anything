Set-StrictMode -Off
$ErrorActionPreference = "Continue"
Write-Host "=== Exporting Full Security Audit Configuration Result ==="

# Load shared utilities
. "C:\workspace\scripts\task_utils.ps1"

# -----------------------------------------------------------------------
# Read task start timestamp
# -----------------------------------------------------------------------
$taskStart = 0
try {
    $tsContent = Get-Content "C:\Users\Docker\task_start_ts_full_security_audit_configuration.txt" -Raw -ErrorAction Stop
    $taskStart = [long]($tsContent.Trim())
    Write-Host "Task start timestamp: $taskStart"
} catch {
    Write-Host "Could not read task start timestamp: $_"
}

# -----------------------------------------------------------------------
# Database helper (uses task_utils Invoke-ADAuditDBQuery)
# -----------------------------------------------------------------------
function Invoke-DBQuery {
    param([string]$Query)
    try {
        $result = Invoke-ADAuditDBQuery $Query
        if ($result -and $result -notmatch "ERROR:" -and $result -notmatch "does not exist") {
            return $result.Trim()
        }
    } catch { }
    return $null
}

# -----------------------------------------------------------------------
# Criterion 1: Check for technician security_ops
# -----------------------------------------------------------------------
Write-Host "--- Checking technician: security_ops ---"
$techExists = $false
$techRole = ""

$tableNames = @("TechnicianInfo", "technicianinfo", "technician", "techdata", "adap_technician")
foreach ($table in $tableNames) {
    $q = "SELECT username FROM $table WHERE LOWER(username) = 'security_ops' LIMIT 1;"
    $r = Invoke-DBQuery -Query $q
    if ($r -and $r -ne "") {
        $techExists = $true
        Write-Host "Found security_ops in table: $table"

        # Try to get role
        $roleColumns = @("role", "technician_role", "userrole", "access_level")
        foreach ($col in $roleColumns) {
            $rq = "SELECT $col FROM $table WHERE LOWER(username) = 'security_ops' LIMIT 1;"
            $rr = Invoke-DBQuery -Query $rq
            if ($rr -and $rr -ne "" -and $rr -notmatch "column") {
                $techRole = $rr.Trim()
                break
            }
        }
        break
    }
}
Write-Host "security_ops exists: $techExists, role: $techRole"

# -----------------------------------------------------------------------
# Criterion 2: Check for email notification / alert profile
# -----------------------------------------------------------------------
Write-Host "--- Checking notification configuration ---"
$notifConfigured = $false
$notifEmail = ""
$notifHasThreshold = $false

if ($true) {
    # Try various notification-related tables
    $notifTables = @(
        @{Table="NotificationProfile"; Cols=@("email", "email_address", "toaddress", "recipient")},
        @{Table="notificationprofile"; Cols=@("email", "email_address", "toaddress", "recipient")},
        @{Table="AlertProfile"; Cols=@("email", "email_address", "toaddress", "recipient")},
        @{Table="alertprofile"; Cols=@("email", "email_address", "toaddress", "recipient")},
        @{Table="EmailNotification"; Cols=@("email", "email_address", "toaddress", "recipient")},
        @{Table="emailnotification"; Cols=@("email", "email_address", "toaddress", "recipient")},
        @{Table="MailConfig"; Cols=@("toemail", "email", "mail_to")},
        @{Table="mailconfig"; Cols=@("toemail", "email", "mail_to")},
        @{Table="Notification"; Cols=@("email", "email_address", "toaddress")},
        @{Table="notification"; Cols=@("email", "email_address", "toaddress")}
    )

    foreach ($entry in $notifTables) {
        $table = $entry.Table
        foreach ($col in $entry.Cols) {
            $q = "SELECT $col FROM $table WHERE $col IS NOT NULL AND $col <> '' LIMIT 5;"
            $r = Invoke-DBQuery -Query $q
            if ($r -and $r -ne "") {
                $notifConfigured = $true
                $notifEmail = $r.Trim()
                Write-Host "Found notification email in ${table}.${col}: $notifEmail"
                break
            }
        }
        if ($notifConfigured) { break }
    }

    # Also check threshold-based settings
    $thresholdTables = @("AlertRule", "alertrule", "ThresholdRule", "thresholdrule", "FailedLogonAlert", "failedlogonalertt")
    foreach ($table in $thresholdTables) {
        $q = "SELECT COUNT(*) FROM $table LIMIT 1;"
        $r = Invoke-DBQuery -Query $q
        if ($r -and $r -match "^\d+$" -and [int]$r -gt 0) {
            $notifHasThreshold = $true
            Write-Host "Found threshold rules in table: $table (count: $r)"
            break
        }
    }
}
Write-Host "Notification configured: $notifConfigured, email: $notifEmail, threshold: $notifHasThreshold"

# -----------------------------------------------------------------------
# Criterion 3: Check for scheduled 'Security Summary' report
# -----------------------------------------------------------------------
Write-Host "--- Checking scheduled report ---"
$secReportFound = $false
$secReportName = ""

if ($true) {
    $reportTables = @("ScheduledReport", "scheduledreport", "scheduled_report", "ReportSchedule", "reportschedule", "reports")
    $reportCols = @("reportname", "report_name", "name", "title", "schedulename")

    foreach ($table in $reportTables) {
        foreach ($col in $reportCols) {
            # Look for security summary or security daily
            $q = "SELECT $col FROM $table WHERE (LOWER($col) LIKE '%security%' AND (LOWER($col) LIKE '%summary%' OR LOWER($col) LIKE '%daily%')) LIMIT 5;"
            $r = Invoke-DBQuery -Query $q
            if ($r -and $r -ne "") {
                $secReportFound = $true
                $secReportName = $r.Trim()
                Write-Host "Found security report in ${table}.${col}: $secReportName"
                break
            }
        }
        if ($secReportFound) { break }
    }

    # Broader fallback search
    if (-not $secReportFound) {
        foreach ($table in $reportTables) {
            foreach ($col in $reportCols) {
                $q = "SELECT $col FROM $table WHERE LOWER($col) LIKE '%security%' LIMIT 10;"
                $r = Invoke-DBQuery -Query $q
                if ($r -and $r -ne "") {
                    Write-Host "Security-related reports in ${table}.${col}: $r"
                    if ($r -match "summary" -or $r -match "daily") {
                        $secReportFound = $true
                        $secReportName = $r.Trim()
                        break
                    }
                }
            }
            if ($secReportFound) { break }
        }
    }
}
Write-Host "Security report found: $secReportFound, name: $secReportName"

# -----------------------------------------------------------------------
# Criterion 4+5+6: Check threat assessment file
# -----------------------------------------------------------------------
Write-Host "--- Checking threat assessment file ---"
$assessmentPath = "C:\Users\Docker\Desktop\threat_assessment.txt"
$assessmentExists = $false
$assessmentModTime = 0
$assessmentModifiedAfterStart = $false
$assessmentContentLength = 0
$assessmentFileSize = 0
$assessmentHasBruteforce1 = $false
$assessmentHasTestattacker = $false
$assessmentHasWrongadmin = $false
$assessmentHasThreatLanguage = $false

if (Test-Path $assessmentPath) {
    $assessmentExists = $true
    $fileInfo = Get-Item $assessmentPath
    $assessmentFileSize = $fileInfo.Length
    $assessmentModTime = [System.DateTimeOffset]::new($fileInfo.LastWriteTimeUtc).ToUnixTimeSeconds()

    if ($taskStart -gt 0 -and $assessmentModTime -gt $taskStart) {
        $assessmentModifiedAfterStart = $true
    }

    try {
        $content = Get-Content $assessmentPath -Raw -Encoding UTF8 -ErrorAction Stop
        if (-not $content) {
            $content = Get-Content $assessmentPath -Raw -Encoding Default -ErrorAction Stop
        }
        $assessmentContentLength = $content.Length

        $cl = $content.ToLower()
        $assessmentHasBruteforce1 = $cl -match "bruteforce1"
        $assessmentHasTestattacker = $cl -match "testattacker"
        $assessmentHasWrongadmin = $cl -match "wrongadmin"
        $assessmentHasThreatLanguage = ($cl -match "brute.?force" -or $cl -match "failed.logon" -or
                                        $cl -match "threat" -or $cl -match "attack" -or
                                        $cl -match "remediat" -or $cl -match "suspicious")

        Write-Host "Assessment file content length: $assessmentContentLength"
        Write-Host "Contains bruteforce1: $assessmentHasBruteforce1"
        Write-Host "Contains testattacker: $assessmentHasTestattacker"
        Write-Host "Contains wrongadmin: $assessmentHasWrongadmin"
        Write-Host "Has threat language: $assessmentHasThreatLanguage"
    } catch {
        Write-Host "Could not read assessment file: $_"
    }
}
Write-Host "Assessment exists: $assessmentExists, mod after start: $assessmentModifiedAfterStart"

# -----------------------------------------------------------------------
# Build result JSON
# -----------------------------------------------------------------------
$result = [ordered]@{
    task_name                         = "full_security_audit_configuration"
    task_start                        = $taskStart
    export_time                       = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    # Technician
    tech_security_ops_exists          = $techExists.ToString().ToLower()
    tech_security_ops_role            = $techRole

    # Notification
    notification_configured           = $notifConfigured.ToString().ToLower()
    notification_email                = $notifEmail
    notification_has_threshold        = $notifHasThreshold.ToString().ToLower()

    # Scheduled report
    security_report_found             = $secReportFound.ToString().ToLower()
    security_report_name              = $secReportName

    # Threat assessment file
    assessment_file_exists            = $assessmentExists.ToString().ToLower()
    assessment_file_mod_time          = $assessmentModTime
    assessment_file_modified_after_start = $assessmentModifiedAfterStart.ToString().ToLower()
    assessment_content_length         = $assessmentContentLength
    assessment_file_size              = $assessmentFileSize
    assessment_has_bruteforce1        = $assessmentHasBruteforce1.ToString().ToLower()
    assessment_has_testattacker       = $assessmentHasTestattacker.ToString().ToLower()
    assessment_has_wrongadmin         = $assessmentHasWrongadmin.ToString().ToLower()
    assessment_has_threat_language    = $assessmentHasThreatLanguage.ToString().ToLower()
}

$outputPath = "C:\Users\Docker\full_security_audit_configuration_result.json"
$result | ConvertTo-Json -Depth 5 | Out-File -FilePath $outputPath -Encoding UTF8
Write-Host "Result exported to $outputPath"

Write-Host "=== Full Security Audit Configuration Export Complete ==="
