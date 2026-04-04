Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

$logPath = "C:\Users\Docker\export_investigate_account_activity.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Exporting investigate_account_activity results ==="

    # Load shared utilities
    . "C:\workspace\scripts\task_utils.ps1"

    # --- Helper: safely query the ADAudit Plus DB with multiple table name fallbacks ---
    function Invoke-SafeDBQuery {
        param([string]$Query)
        try {
            $result = Invoke-ADAuditDBQuery $Query
            if ($result -and ($result -notmatch "ERROR:" -and $result -notmatch "FATAL:" -and $result -notmatch "does not exist")) {
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
            "SELECT username FROM techdata WHERE LOWER(username)=LOWER('$Username')",
            "SELECT username FROM adap_user WHERE LOWER(username)=LOWER('$Username')",
            "SELECT username FROM users WHERE LOWER(username)=LOWER('$Username') AND username != 'admin'"
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
            "SELECT techniciantype FROM TechnicianInfo WHERE LOWER(username)=LOWER('$Username')",
            "SELECT user_type FROM techdata WHERE LOWER(username)=LOWER('$Username')"
        )
        foreach ($q in $queries) {
            $r = Invoke-SafeDBQuery $q
            if ($r -and $r -ne "" -and $r -notmatch "^-") { return $r }
        }
        return $null
    }

    # --- Also try the ADAudit Plus REST API for technician verification ---
    function Get-TechViaAPI {
        param([string]$Username)
        try {
            $session = Get-ADAuditSession
            if (-not $session) { return $null }
            # Try known ADAudit Plus API patterns
            $endpoints = @(
                "/adap/api/conf/techData",
                "/adap/api/v1/conf/techData",
                "/adap/admin/techData"
            )
            foreach ($ep in $endpoints) {
                try {
                    $resp = Invoke-ADAuditAPI -Path $ep -WebSession $session
                    if ($resp -and $resp.Content -match $Username) {
                        return "found_via_api"
                    }
                } catch {}
            }
        } catch {}
        return $null
    }

    # --- Read task start timestamp ---
    $taskStart = 0
    try {
        $taskStart = [long](Get-Content "C:\Users\Docker\task_start_timestamp.txt" -Raw)
    } catch {}

    # --- Check the report file ---
    $reportFile = "C:\Users\Docker\Desktop\account_threat_report.txt"
    $reportExists = Test-Path $reportFile
    $reportSize = 0
    $reportModTime = 0
    $reportContent = ""
    $reportModifiedAfterStart = $false

    if ($reportExists) {
        try {
            $fi = Get-Item $reportFile
            $reportSize = $fi.Length
            $reportModTime = [long]([System.DateTimeOffset]::new($fi.LastWriteTimeUtc).ToUnixTimeSeconds())
            $reportModifiedAfterStart = ($reportModTime -gt $taskStart)
            # Read content (cap at 8000 chars to avoid huge JSON)
            $rawContent = Get-Content $reportFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($rawContent -and $rawContent.Length -gt 8000) {
                $reportContent = $rawContent.Substring(0, 8000)
            } else {
                $reportContent = if ($rawContent) { $rawContent } else { "" }
            }
        } catch {
            Write-Host "Could not read report file: $_"
        }
    }

    # --- Check for known usernames in report content ---
    $contentLower = $reportContent.ToLower()
    $accountEventUsers = @("jsmith", "mjohnson", "rwilliams", "abrown", "dlee")
    $failedLogonUsers = @("baduser1", "baduser2", "wrongadmin", "testattacker", "bruteforce1")
    $allExpectedUsers = $accountEventUsers + $failedLogonUsers

    $foundAccountUsers = @($accountEventUsers | Where-Object { $contentLower -match $_.ToLower() })
    $foundFailedUsers = @($failedLogonUsers | Where-Object { $contentLower -match $_.ToLower() })
    $totalUsersFound = $foundAccountUsers.Count + $foundFailedUsers.Count

    # --- Check technician soc_analyst1 via DB ---
    $techExists = $null
    $techRole = $null
    try {
        $techExists = Find-TechnicianByUsername "soc_analyst1"
        if ($techExists) {
            $techRole = Find-TechnicianRole "soc_analyst1"
        }
    } catch {
        Write-Host "DB technician check failed: $_"
    }

    # Fallback: try API if DB check failed
    if (-not $techExists) {
        try {
            $techExists = Get-TechViaAPI "soc_analyst1"
        } catch {}
    }

    # --- Write result JSON ---
    $taskEnd = [long]([System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $resultPath = "C:\Users\Docker\investigate_account_activity_result.json"

    $resultJson = @"
{
  "task_name": "investigate_account_activity",
  "task_start": $taskStart,
  "task_end": $taskEnd,
  "report_file_exists": $(if ($reportExists) { "true" } else { "false" }),
  "report_file_size": $reportSize,
  "report_mod_time": $reportModTime,
  "report_modified_after_start": $(if ($reportModifiedAfterStart) { "true" } else { "false" }),
  "report_content_length": $($reportContent.Length),
  "found_account_users_count": $($foundAccountUsers.Count),
  "found_failed_logon_users_count": $($foundFailedUsers.Count),
  "total_users_found": $totalUsersFound,
  "found_users_list": "$($($foundAccountUsers + $foundFailedUsers) -join ',')",
  "report_has_dlee": $(if ($contentLower -match "dlee") { "true" } else { "false" }),
  "report_has_mjohnson": $(if ($contentLower -match "mjohnson") { "true" } else { "false" }),
  "report_has_jsmith": $(if ($contentLower -match "jsmith") { "true" } else { "false" }),
  "report_has_abrown": $(if ($contentLower -match "abrown") { "true" } else { "false" }),
  "report_has_rwilliams": $(if ($contentLower -match "rwilliams") { "true" } else { "false" }),
  "report_has_baduser1": $(if ($contentLower -match "baduser1") { "true" } else { "false" }),
  "report_has_baduser2": $(if ($contentLower -match "baduser2") { "true" } else { "false" }),
  "report_has_wrongadmin": $(if ($contentLower -match "wrongadmin") { "true" } else { "false" }),
  "report_has_testattacker": $(if ($contentLower -match "testattacker") { "true" } else { "false" }),
  "report_has_bruteforce1": $(if ($contentLower -match "bruteforce1") { "true" } else { "false" }),
  "tech_soc_analyst1_exists": $(if ($techExists -and $techExists -ne "") { "true" } else { "false" }),
  "tech_soc_analyst1_role": "$(if ($techRole) { $techRole.Trim() } else { '' })"
}
"@

    $resultJson | Out-File $resultPath -Encoding UTF8 -NoNewline
    Write-Host "Result written to: $resultPath"
    Write-Host "Report file exists: $reportExists"
    Write-Host "Report size: $reportSize bytes"
    Write-Host "Report modified after start: $reportModifiedAfterStart"
    Write-Host "Total users found in report: $totalUsersFound"
    Write-Host "Tech soc_analyst1 exists: $($techExists -ne $null -and $techExists -ne '')"

    Write-Host "=== Export complete ==="
} catch {
    Write-Host "EXPORT ERROR: $_"
    Write-Host $_.ScriptStackTrace

    # Write minimal result so verifier doesn't crash
    @"
{
  "task_name": "investigate_account_activity",
  "task_start": 0,
  "task_end": 0,
  "report_file_exists": false,
  "report_file_size": 0,
  "report_modified_after_start": false,
  "report_content_length": 0,
  "found_account_users_count": 0,
  "found_failed_logon_users_count": 0,
  "total_users_found": 0,
  "found_users_list": "",
  "tech_soc_analyst1_exists": false,
  "tech_soc_analyst1_role": "",
  "export_error": true
}
"@ | Out-File "C:\Users\Docker\investigate_account_activity_result.json" -Encoding UTF8 -NoNewline
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
