Set-StrictMode -Off
$ErrorActionPreference = "Continue"
Write-Host "=== Setting up Multi-Role Access Governance Task ==="

# Load shared utilities
. "C:\workspace\scripts\task_utils.ps1"

# -----------------------------------------------------------------------
# STEP 1: Delete stale output files BEFORE recording timestamp
# -----------------------------------------------------------------------
$staleFiles = @(
    "C:\Users\Docker\Desktop\governance_audit.txt"
)
foreach ($f in $staleFiles) {
    Remove-Item $f -Force -ErrorAction SilentlyContinue
    Write-Host "Cleaned stale file: $f"
}

# -----------------------------------------------------------------------
# STEP 2: Record task start timestamp AFTER cleanup
# -----------------------------------------------------------------------
$taskStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$taskStart | Out-File -FilePath "C:\Users\Docker\task_start_ts_multi_role_access_governance.txt" -Encoding ASCII -Force
Write-Host "Task start timestamp: $taskStart"

# -----------------------------------------------------------------------
# Generate unauthorized privilege escalation events
# These simulate the security incident the agent must investigate
# -----------------------------------------------------------------------

# Event 1: Add jsmith to Administrators group (high-privilege escalation)
Write-Host "Generating unauthorized group membership changes..."
try {
    # Add jsmith to Administrators if not already there
    $members = net localgroup Administrators 2>$null
    if ($members -notcontains "jsmith") {
        & net localgroup Administrators jsmith /add 2>$null
        Write-Host "Added jsmith to Administrators group"
    } else {
        Write-Host "jsmith already in Administrators (pre-existing)"
    }
} catch {
    Write-Host "Note: Could not add jsmith to Administrators: $_"
}

Start-Sleep -Seconds 2

# Event 2: Add abrown to Security_Team group
try {
    $members = net localgroup Security_Team 2>$null
    if ($members -notcontains "abrown") {
        & net localgroup Security_Team abrown /add 2>$null
        Write-Host "Added abrown to Security_Team group"
    } else {
        Write-Host "abrown already in Security_Team (pre-existing)"
    }
} catch {
    Write-Host "Note: Could not add abrown to Security_Team: $_"
}

Start-Sleep -Seconds 1

# Event 3: Also add mjohnson to IT_Support to create noise (not a privileged group)
try {
    & net localgroup IT_Support mjohnson /add 2>$null
    Write-Host "Added mjohnson to IT_Support (noise event)"
} catch {
    Write-Host "Note: Could not add mjohnson to IT_Support"
}

Start-Sleep -Seconds 1

# Event 4: Add rwilliams to Server_Admins to create noise
try {
    & net localgroup Server_Admins rwilliams /add 2>$null
    Write-Host "Added rwilliams to Server_Admins (noise event)"
} catch {
    Write-Host "Note: Could not add rwilliams to Server_Admins"
}

# -----------------------------------------------------------------------
# Record baseline: which technicians currently exist
# -----------------------------------------------------------------------
Write-Host "Recording baseline technician state..."

# Try to query the database for existing technicians
$pgPath = "C:\Program Files\ManageEngine\ADAudit Plus\pgsql\bin\psql.exe"
$env:PGPASSWORD = "adap"

$techQuery = "SELECT username FROM technicianinfo LIMIT 100;"
$baselineTechs = ""
if (Test-Path $pgPath) {
    try {
        $result = & $pgPath -h localhost -p 33307 -U postgres -d adap -t -c $techQuery 2>$null
        $baselineTechs = ($result -join ",").Trim()
    } catch {
        $baselineTechs = "query_failed"
    }
} else {
    $baselineTechs = "psql_not_found"
}

$baselineTechs | Out-File -FilePath "C:\Users\Docker\initial_techs_multi_role.txt" -Encoding ASCII -Force
Write-Host "Baseline technicians recorded: $baselineTechs"

# -----------------------------------------------------------------------
# Record group membership baseline
# -----------------------------------------------------------------------
$adminMembers = (& net localgroup Administrators 2>$null | Select-String -Pattern "^[a-zA-Z]") -join ","
$adminMembers | Out-File -FilePath "C:\Users\Docker\initial_admin_members_multi_role.txt" -Encoding ASCII -Force

# -----------------------------------------------------------------------
# Wait for ADAudit Plus to be ready
# -----------------------------------------------------------------------
$ready = Wait-ForADAudit -TimeoutSec 120
if (-not $ready) {
    Write-Host "WARNING: ADAudit Plus not ready within timeout, proceeding anyway..."
}

# -----------------------------------------------------------------------
# Launch browser so agent can start working
# -----------------------------------------------------------------------
try {
    Launch-BrowserToADAudit -Path "/" -WaitSeconds 15
    Write-Host "Browser launched to ADAudit Plus"
} catch {
    Write-Host "Could not launch browser: $_"
}

Write-Host "=== Multi-Role Access Governance Setup Complete ==="
Write-Host "Unauthorized group changes: jsmith->Administrators, abrown->Security_Team"
Write-Host "Task start: $taskStart"
