Set-StrictMode -Off
$ErrorActionPreference = "Continue"
Write-Host "=== Exporting Multi-Role Access Governance Result ==="

# Load shared utilities
. "C:\workspace\scripts\task_utils.ps1"

# -----------------------------------------------------------------------
# Read task start timestamp
# -----------------------------------------------------------------------
$taskStart = 0
try {
    $tsContent = Get-Content "C:\Users\Docker\task_start_ts_multi_role_access_governance.txt" -Raw -ErrorAction Stop
    $taskStart = [long]($tsContent.Trim())
    Write-Host "Task start timestamp: $taskStart"
} catch {
    Write-Host "Could not read task start timestamp: $_"
}

# -----------------------------------------------------------------------
# Helper: Query ADAudit Plus PostgreSQL database
# -----------------------------------------------------------------------
function Invoke-SafeDBQuery {
    param([string]$Query, [string]$Label = "")
    try {
        $result = Invoke-ADAuditDBQuery $Query
        if ($result -and $result -notmatch "ERROR:" -and $result -notmatch "does not exist") {
            if ($Label) { Write-Host "${Label}: $result" }
            return $result.Trim()
        }
    } catch {}
    return $null
}

# -----------------------------------------------------------------------
# Helper: Check if a technician exists and get their role
# -----------------------------------------------------------------------
function Find-Technician {
    param([string]$Username)

    $tableNames = @("TechnicianInfo", "technicianinfo", "technician", "techdata", "adap_technician", "users")
    $roleColumns = @("role", "technician_role", "userrole", "access_level", "rolename")

    foreach ($table in $tableNames) {
        foreach ($roleCol in $roleColumns) {
            $q = "SELECT username, $roleCol FROM $table WHERE LOWER(username) = LOWER('$Username') LIMIT 1;"
            $r = Invoke-SafeDBQuery $q
            if ($r -and $r.Trim() -ne "" -and $r -notmatch "ERROR") {
                Write-Host "Found technician $Username in table $table (role col: $roleCol): $r"
                return $r
            }
        }
        # Try without role column
        $q2 = "SELECT username FROM $table WHERE LOWER(username) = LOWER('$Username') LIMIT 1;"
        $r2 = Invoke-SafeDBQuery $q2
        if ($r2 -and $r2.Trim() -ne "" -and $r2 -notmatch "ERROR") {
            Write-Host "Found technician $Username (no role) in table $table: $r2"
            return $r2
        }
    }
    return $null
}

# -----------------------------------------------------------------------
# Criterion 1: Check for technician gov_lead (Auditor role)
# -----------------------------------------------------------------------
Write-Host "--- Checking technician: gov_lead ---"
$govLeadExists = $false
$govLeadRole = ""

$result = Find-Technician -Username "gov_lead"
if ($result -and $result.Trim() -ne "") {
    $govLeadExists = $true
    if ($result -match "\|") {
        $parts = $result.Trim().Split("|")
        if ($parts.Length -ge 2) { $govLeadRole = $parts[1].Trim() }
    }
    # Try a more targeted role query
    $roleR = Invoke-SafeDBQuery "SELECT role FROM TechnicianInfo WHERE LOWER(username) = 'gov_lead' LIMIT 1;"
    if ($roleR -and $roleR.Trim() -ne "" -and $roleR -notmatch "ERROR") {
        $govLeadRole = $roleR.Trim()
    }
}
Write-Host "gov_lead exists: $govLeadExists, role: $govLeadRole"

# -----------------------------------------------------------------------
# Criterion 2: Check for technician risk_analyst (Operator role)
# -----------------------------------------------------------------------
Write-Host "--- Checking technician: risk_analyst ---"
$riskAnalystExists = $false
$riskAnalystRole = ""

$result = Find-Technician -Username "risk_analyst"
if ($result -and $result.Trim() -ne "") {
    $riskAnalystExists = $true
    $roleR = Invoke-SafeDBQuery "SELECT role FROM TechnicianInfo WHERE LOWER(username) = 'risk_analyst' LIMIT 1;"
    if ($roleR -and $roleR.Trim() -ne "" -and $roleR -notmatch "ERROR") {
        $riskAnalystRole = $roleR.Trim()
    }
}
Write-Host "risk_analyst exists: $riskAnalystExists, role: $riskAnalystRole"

# -----------------------------------------------------------------------
# Criterion 3: Check for technician change_manager (Operator role)
# -----------------------------------------------------------------------
Write-Host "--- Checking technician: change_manager ---"
$changeManagerExists = $false
$changeManagerRole = ""

$result = Find-Technician -Username "change_manager"
if ($result -and $result.Trim() -ne "") {
    $changeManagerExists = $true
    $roleR = Invoke-SafeDBQuery "SELECT role FROM TechnicianInfo WHERE LOWER(username) = 'change_manager' LIMIT 1;"
    if ($roleR -and $roleR.Trim() -ne "" -and $roleR -notmatch "ERROR") {
        $changeManagerRole = $roleR.Trim()
    }
}
Write-Host "change_manager exists: $changeManagerExists, role: $changeManagerRole"

# -----------------------------------------------------------------------
# Criterion 4: Check for scheduled report 'Group Membership Changes Weekly'
# -----------------------------------------------------------------------
Write-Host "--- Checking scheduled report ---"
$reportFound = $false
$reportName = ""

$reportTables = @("ScheduledReport", "scheduledreport", "scheduled_report", "reports", "ReportSchedule", "reportschedule")
$reportCols = @("reportname", "report_name", "name", "title")

foreach ($table in $reportTables) {
    foreach ($col in $reportCols) {
        $q = "SELECT $col FROM $table WHERE LOWER($col) LIKE '%group%membership%' OR LOWER($col) LIKE '%membership%change%' OR (LOWER($col) LIKE '%group%' AND LOWER($col) LIKE '%weekly%') LIMIT 5;"
        $r = Invoke-SafeDBQuery $q
        if ($r -and $r.Trim() -ne "" -and $r -notmatch "ERROR") {
            $reportFound = $true
            $reportName = $r.Trim()
            Write-Host "Found matching report in ${table}.${col}: $reportName"
            break
        }
    }
    if ($reportFound) { break }
}

# Try broader search
if (-not $reportFound) {
    foreach ($table in $reportTables) {
        foreach ($col in $reportCols) {
            $q = "SELECT $col FROM $table WHERE LOWER($col) LIKE '%group%' LIMIT 10;"
            $r = Invoke-SafeDBQuery $q
            if ($r -and $r.Trim() -ne "" -and $r -notmatch "ERROR") {
                Write-Host "Group reports in ${table}.${col}: $r"
                if ($r -match "membership" -or ($r -match "group" -and $r -match "week")) {
                    $reportFound = $true
                    $reportName = $r.Trim()
                    break
                }
            }
        }
        if ($reportFound) { break }
    }
}
Write-Host "Report found: $reportFound, name: $reportName"

# -----------------------------------------------------------------------
# Criterion 5: Check governance audit file
# -----------------------------------------------------------------------
Write-Host "--- Checking governance audit file ---"
$auditFilePath = "C:\Users\Docker\Desktop\governance_audit.txt"
$auditFileExists = $false
$auditFileModTime = 0
$auditModifiedAfterStart = $false
$auditContentLength = 0
$auditHasJsmith = $false
$auditHasAbrown = $false
$auditHasGroupInfo = $false

if (Test-Path $auditFilePath) {
    $auditFileExists = $true
    $fileInfo = Get-Item $auditFilePath
    $auditFileModTime = [System.DateTimeOffset]::new($fileInfo.LastWriteTimeUtc).ToUnixTimeSeconds()

    if ($taskStart -gt 0 -and $auditFileModTime -gt $taskStart) {
        $auditModifiedAfterStart = $true
    }

    try {
        $content = Get-Content $auditFilePath -Raw -Encoding UTF8 -ErrorAction Stop
        if (-not $content) {
            $content = Get-Content $auditFilePath -Raw -Encoding Default -ErrorAction Stop
        }
        $auditContentLength = $content.Length

        $contentLower = $content.ToLower()
        $auditHasJsmith = $contentLower -match "jsmith"
        $auditHasAbrown = $contentLower -match "abrown"
        $auditHasGroupInfo = ($contentLower -match "administrator" -or $contentLower -match "security.team" -or
                              $contentLower -match "group" -or $contentLower -match "privilege")

        Write-Host "Audit file content length: $auditContentLength"
        Write-Host "Contains jsmith: $auditHasJsmith"
        Write-Host "Contains abrown: $auditHasAbrown"
        Write-Host "Contains group info: $auditHasGroupInfo"
    } catch {
        Write-Host "Could not read audit file content: $_"
    }
}
Write-Host "Audit file exists: $auditFileExists, mod time: $auditFileModTime, modified after start: $auditModifiedAfterStart"

# -----------------------------------------------------------------------
# Build result JSON
# -----------------------------------------------------------------------
$result = [ordered]@{
    task_name                    = "multi_role_access_governance"
    task_start                   = $taskStart
    export_time                  = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    # Technician gov_lead
    tech_gov_lead_exists         = $govLeadExists.ToString().ToLower()
    tech_gov_lead_role           = $govLeadRole

    # Technician risk_analyst
    tech_risk_analyst_exists     = $riskAnalystExists.ToString().ToLower()
    tech_risk_analyst_role       = $riskAnalystRole

    # Technician change_manager
    tech_change_manager_exists   = $changeManagerExists.ToString().ToLower()
    tech_change_manager_role     = $changeManagerRole

    # Scheduled report
    report_found                 = $reportFound.ToString().ToLower()
    report_name                  = $reportName

    # Audit file
    audit_file_exists            = $auditFileExists.ToString().ToLower()
    audit_file_mod_time          = $auditFileModTime
    audit_file_modified_after_start = $auditModifiedAfterStart.ToString().ToLower()
    audit_file_content_length    = $auditContentLength
    audit_has_jsmith             = $auditHasJsmith.ToString().ToLower()
    audit_has_abrown             = $auditHasAbrown.ToString().ToLower()
    audit_has_group_info         = $auditHasGroupInfo.ToString().ToLower()
}

$outputPath = "C:\Users\Docker\multi_role_access_governance_result.json"
$result | ConvertTo-Json -Depth 5 | Out-File -FilePath $outputPath -Encoding UTF8
Write-Host "Result exported to $outputPath"

Write-Host "=== Multi-Role Access Governance Export Complete ==="
