Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$logPath = "C:\Users\Docker\export_brute_force_response.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Exporting brute_force_response results ==="

    . "C:\workspace\scripts\task_utils.ps1"

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
            "SELECT role FROM technician WHERE LOWER(username)=LOWER('$Username')"
        )
        foreach ($q in $queries) {
            $r = Invoke-SafeDBQuery $q
            if ($r -and $r -ne "" -and $r -notmatch "^-") { return $r }
        }
        return $null
    }

    function Get-NotificationEmail {
        $queries = @(
            "SELECT email FROM NotificationSettings LIMIT 5",
            "SELECT email FROM notificationsettings LIMIT 5",
            "SELECT emailid FROM AlertMeSettings LIMIT 5",
            "SELECT emailid FROM alertmesettings LIMIT 5",
            "SELECT notification_email FROM notification_config LIMIT 5"
        )
        foreach ($q in $queries) {
            $r = Invoke-SafeDBQuery $q
            if ($r -and $r -ne "" -and $r -notmatch "^-") { return $r }
        }
        return $null
    }

    # --- Task start timestamp ---
    $taskStart = 0
    try { $taskStart = [long](Get-Content "C:\Users\Docker\task_start_timestamp.txt" -Raw) } catch {}

    # --- Check analysis file ---
    $analysisFile = "C:\Users\Docker\Desktop\brute_force_analysis.txt"
    $fileExists = Test-Path $analysisFile
    $fileSize = 0
    $fileModTime = 0
    $fileContent = ""
    $fileModifiedAfterStart = $false

    if ($fileExists) {
        try {
            $fi = Get-Item $analysisFile
            $fileSize = $fi.Length
            $fileModTime = [long]([System.DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds())
            $fileModifiedAfterStart = ($fileModTime -gt $taskStart)
            $raw = Get-Content $analysisFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            $fileContent = if ($raw -and $raw.Length -gt 6000) { $raw.Substring(0, 6000) } else { if ($raw) { $raw } else { "" } }
        } catch {}
    }

    $contentLower = $fileContent.ToLower()
    $fileHasRwilliams = $contentLower -match "rwilliams"
    $fileHasJsmith = $contentLower -match "jsmith"
    $fileHasBruteForce = ($contentLower -match "brute" -or $contentLower -match "failed" -or $contentLower -match "attack")

    # --- Check technician ---
    $techExists = $null
    $techRole = $null
    try {
        $techExists = Find-TechnicianByUsername "incident_handler"
        if ($techExists) { $techRole = Find-TechnicianRole "incident_handler" }
    } catch {}

    # --- Check notification ---
    $notifEmail = $null
    try { $notifEmail = Get-NotificationEmail } catch {}
    $notifHasSecAlerts = $false
    if ($notifEmail) {
        $notifHasSecAlerts = $notifEmail -match "security-alerts" -or $notifEmail -match "security.alerts"
    }

    # --- Write result JSON ---
    $taskEnd = [long]([System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $resultPath = "C:\Users\Docker\brute_force_response_result.json"

    $resultJson = @"
{
  "task_name": "brute_force_response",
  "task_start": $taskStart,
  "task_end": $taskEnd,
  "tech_incident_handler_exists": $(if ($techExists -and $techExists -ne "") { "true" } else { "false" }),
  "tech_incident_handler_role": "$(if ($techRole) { $techRole.Trim() -replace '"', '' } else { '' })",
  "notification_email": "$(if ($notifEmail) { ($notifEmail -split '\n')[0].Trim() -replace '"', '' } else { '' })",
  "notification_has_security_alerts": $(if ($notifHasSecAlerts) { "true" } else { "false" }),
  "analysis_file_exists": $(if ($fileExists) { "true" } else { "false" }),
  "analysis_file_size": $fileSize,
  "analysis_file_mod_time": $fileModTime,
  "analysis_file_modified_after_start": $(if ($fileModifiedAfterStart) { "true" } else { "false" }),
  "analysis_file_content_length": $($fileContent.Length),
  "analysis_has_rwilliams": $(if ($fileHasRwilliams) { "true" } else { "false" }),
  "analysis_has_jsmith": $(if ($fileHasJsmith) { "true" } else { "false" }),
  "analysis_has_brute_force_language": $(if ($fileHasBruteForce) { "true" } else { "false" })
}
"@

    $resultJson | Out-File $resultPath -Encoding UTF8 -NoNewline
    Write-Host "Results written to: $resultPath"
    Write-Host "Tech incident_handler: $($techExists -ne $null)"
    Write-Host "Notification: $notifEmail"
    Write-Host "Analysis file: $fileExists, size: $fileSize"
    Write-Host "Has rwilliams: $fileHasRwilliams"

    Write-Host "=== Export complete ==="
} catch {
    Write-Host "EXPORT ERROR: $_"
    @"
{
  "task_name": "brute_force_response",
  "task_start": 0, "task_end": 0,
  "tech_incident_handler_exists": false, "tech_incident_handler_role": "",
  "notification_email": "", "notification_has_security_alerts": false,
  "analysis_file_exists": false, "analysis_file_size": 0,
  "analysis_file_mod_time": 0, "analysis_file_modified_after_start": false,
  "analysis_file_content_length": 0, "analysis_has_rwilliams": false,
  "analysis_has_jsmith": false, "analysis_has_brute_force_language": false,
  "export_error": true
}
"@ | Out-File "C:\Users\Docker\brute_force_response_result.json" -Encoding UTF8 -NoNewline
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
