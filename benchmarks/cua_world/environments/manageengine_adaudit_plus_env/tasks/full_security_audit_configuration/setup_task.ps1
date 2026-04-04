Set-StrictMode -Off
$ErrorActionPreference = "Continue"
Write-Host "=== Setting up Full Security Audit Configuration Task ==="

# Load shared utilities
. "C:\workspace\scripts\task_utils.ps1"

# -----------------------------------------------------------------------
# STEP 1: Delete stale output files BEFORE recording timestamp
# -----------------------------------------------------------------------
$staleFiles = @(
    "C:\Users\Docker\Desktop\threat_assessment.txt"
)
foreach ($f in $staleFiles) {
    Remove-Item $f -Force -ErrorAction SilentlyContinue
    Write-Host "Cleaned stale file: $f"
}

# -----------------------------------------------------------------------
# STEP 2: Record task start timestamp AFTER cleanup
# -----------------------------------------------------------------------
$taskStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$taskStart | Out-File -FilePath "C:\Users\Docker\task_start_ts_full_security_audit_configuration.txt" -Encoding ASCII -Force
Write-Host "Task start timestamp: $taskStart"

# -----------------------------------------------------------------------
# Generate realistic multi-vector attack scenario
# -----------------------------------------------------------------------

# --- Phase 1: Primary brute force threat (bruteforce1 - 25 failed logons) ---
Write-Host "Generating primary brute force events (bruteforce1)..."
for ($i = 1; $i -le 25; $i++) {
    & net use "\\localhost\IPC$" /user:bruteforce1 "Password$i!" 2>$null
    Start-Sleep -Milliseconds 200
}
Write-Host "bruteforce1: 25 failed logon events generated"

Start-Sleep -Seconds 2

# --- Phase 2: Secondary threat (testattacker - 8 failed logons) ---
Write-Host "Generating secondary threat events (testattacker)..."
for ($i = 1; $i -le 8; $i++) {
    & net use "\\localhost\IPC$" /user:testattacker "Attempt$i@2024" 2>$null
    Start-Sleep -Milliseconds 250
}
Write-Host "testattacker: 8 failed logon events generated"

Start-Sleep -Seconds 1

# --- Phase 3: Noise events (wrongadmin - 5 failed logons) ---
Write-Host "Generating noise events (wrongadmin)..."
for ($i = 1; $i -le 5; $i++) {
    & net use "\\localhost\IPC$" /user:wrongadmin "Admin$i" 2>$null
    Start-Sleep -Milliseconds 200
}
Write-Host "wrongadmin: 5 failed logon events generated"

Start-Sleep -Seconds 1

# --- Phase 4: File access activity (jsmith accesses confidential files) ---
Write-Host "Generating file access events (jsmith)..."
$auditFolder = "C:\AuditTestFolder\Confidential"
if (Test-Path $auditFolder) {
    $sensitiveFiles = @("quarterly_report_Q4.txt", "employee_records.txt", "security_policy.txt")
    foreach ($filename in $sensitiveFiles) {
        $filepath = Join-Path $auditFolder $filename
        if (-not (Test-Path $filepath)) {
            Set-Content -Path $filepath -Value "Confidential document - $filename" -Encoding UTF8
        }
        try {
            $null = Get-Content $filepath -ErrorAction SilentlyContinue
        } catch { }
    }
    Write-Host "File access events generated in $auditFolder"
} else {
    Write-Host "Audit folder not found at $auditFolder, skipping file events"
    $altFolder = "C:\AuditTestFolder"
    if (Test-Path $altFolder) {
        Write-Host "Alternative audit folder found"
    }
}

# --- Phase 5: Normal activity for contrast (mjohnson account changes) ---
Write-Host "Generating normal activity events..."
try {
    & net user mjohnson /comment:"Regular employee - IT Department" 2>$null
    Write-Host "mjohnson account modification event generated"
} catch {
    Write-Host "Could not modify mjohnson: $_"
}

# -----------------------------------------------------------------------
# Record baseline technician count using task_utils
# -----------------------------------------------------------------------
Write-Host "Recording baseline technician count..."
try {
    $baselineTechs = Invoke-ADAuditDBQuery "SELECT COUNT(*) FROM TechnicianInfo;"
    $baselineTechs = if ($baselineTechs) { $baselineTechs.Trim() } else { "0" }
} catch {
    $baselineTechs = "query_failed"
}
$baselineTechs | Out-File -FilePath "C:\Users\Docker\initial_tech_count_full_security.txt" -Encoding ASCII -Force
Write-Host "Baseline technician count: $baselineTechs"

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

Write-Host "=== Full Security Audit Configuration Setup Complete ==="
Write-Host "Events: bruteforce1(25 fails), testattacker(8 fails), wrongadmin(5 fails), jsmith(file access)"
Write-Host "Task start: $taskStart"
