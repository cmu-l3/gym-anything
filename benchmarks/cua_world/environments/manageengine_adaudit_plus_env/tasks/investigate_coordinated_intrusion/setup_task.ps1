Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\setup_investigate_coordinated_intrusion.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up Investigate Coordinated Intrusion Task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    $ready = Wait-ForADAudit -TimeoutSec 600
    if (-not $ready) {
        Write-Host "WARNING: ADAudit Plus not ready, proceeding anyway..."
    }

    # -----------------------------------------------------------------------
    # STEP 1: Delete stale output files BEFORE recording timestamp
    # -----------------------------------------------------------------------
    $staleFiles = @(
        "C:\Users\Docker\Desktop\incident_report.txt"
    )
    foreach ($f in $staleFiles) {
        Remove-Item $f -Force -ErrorAction SilentlyContinue
        Write-Host "Cleaned stale file: $f"
    }

    # -----------------------------------------------------------------------
    # STEP 2: Record task start timestamp AFTER cleanup
    # -----------------------------------------------------------------------
    $taskStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $taskStart | Out-File -FilePath "C:\Users\Docker\task_start_ts_coordinated_intrusion.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $taskStart"

    # -----------------------------------------------------------------------
    # STEP 3: Create service accounts (the attack surface)
    # -----------------------------------------------------------------------
    Write-Host "Creating service accounts..."

    # Primary brute-force target (password must NOT contain username per Windows policy)
    & net user svc_backup "B@ckServ2024!" /add /fullname:"Backup Service Account" /comment:"Backup automation service" 2>$null

    # Reconnaissance targets
    & net user svc_sql "P@ssw0rd2024!" /add /fullname:"SQL Service Account" /comment:"SQL Server service" 2>$null
    & net user svc_deploy "P@ssw0rd2024!" /add /fullname:"Deployment Service Account" /comment:"CI/CD deployment service" 2>$null
    & net user svc_monitoring "P@ssw0rd2024!" /add /fullname:"Monitoring Service Account" /comment:"Infrastructure monitoring" 2>$null

    # Legitimate admin (noise)
    & net user admin_jones "AdminJ@2024!" /add /fullname:"Mike Jones" /comment:"Senior Systems Administrator" 2>$null

    # Diversionary account (created by attacker, used for probe, NOT escalated)
    & net user helpdesk_temp "HDesk@2024!" /add /fullname:"Temp Helpdesk" /comment:"Temporary helpdesk account" 2>$null

    Write-Host "Service accounts created"

    # -----------------------------------------------------------------------
    # STEP 3b: Disable account lockout policy (Windows 11 defaults to 10 attempts)
    # -----------------------------------------------------------------------
    Write-Host "Disabling account lockout policy for event generation..."
    & net accounts /lockoutthreshold:0 2>$null
    Write-Host "Account lockout threshold set to 0 (disabled)"

    # -----------------------------------------------------------------------
    # STEP 4: Reconnaissance probing (noise - 5 failures each)
    # -----------------------------------------------------------------------
    Write-Host "Generating reconnaissance probing events..."

    foreach ($recon in @("svc_sql", "svc_deploy", "svc_monitoring")) {
        for ($i = 1; $i -le 5; $i++) {
            & net use "\\localhost\IPC$" /user:$recon "ReconProbe$i!" 2>$null
            Start-Sleep -Milliseconds 200
        }
        Write-Host "  ${recon}: 5 failed logon events"
    }

    Start-Sleep -Seconds 1

    # -----------------------------------------------------------------------
    # STEP 5: Brute-force attack on svc_backup (40 failed logons)
    # -----------------------------------------------------------------------
    Write-Host "Generating brute-force attack events (svc_backup - 40 attempts)..."
    for ($i = 1; $i -le 40; $i++) {
        & net use "\\localhost\IPC$" /user:svc_backup "BruteAttempt$i!" 2>$null
        Start-Sleep -Milliseconds 250
        if ($i % 10 -eq 0) {
            Write-Host "  Generated $i/40 failed logon events for svc_backup"
        }
    }
    Write-Host "  svc_backup: 40 failed logon events generated"

    Start-Sleep -Seconds 1

    # -----------------------------------------------------------------------
    # STEP 6: Diversionary probing from helpdesk_temp (12 failures, no escalation)
    # -----------------------------------------------------------------------
    Write-Host "Generating diversionary probe events (helpdesk_temp - 12 attempts)..."
    for ($i = 1; $i -le 12; $i++) {
        & net use "\\localhost\IPC$" /user:helpdesk_temp "HelpDesk$i!" 2>$null
        Start-Sleep -Milliseconds 200
    }
    Write-Host "  helpdesk_temp: 12 failed logon events (diversion, no escalation)"

    Start-Sleep -Seconds 1

    # -----------------------------------------------------------------------
    # STEP 7: Legitimate admin lockout noise (admin_jones)
    # -----------------------------------------------------------------------
    Write-Host "Generating legitimate admin lockout noise (admin_jones)..."
    for ($i = 1; $i -le 8; $i++) {
        & net use "\\localhost\IPC$" /user:admin_jones "WrongAdminPass$i!" 2>$null
        Start-Sleep -Milliseconds 200
    }
    Write-Host "  admin_jones: 8 failed logon events (legitimate lockout)"

    # Legitimate recovery: successful logon + password reset
    & net use "\\localhost\IPC$" /user:admin_jones "AdminJ@2024!" 2>$null
    Start-Sleep -Milliseconds 500
    & net use "\\localhost\IPC$" /delete 2>$null
    Write-Host "  admin_jones: successful logon recovery"
    & net user admin_jones "AdminJ@2025!" 2>$null
    Write-Host "  admin_jones: password reset (legitimate recovery)"

    Start-Sleep -Seconds 2

    # -----------------------------------------------------------------------
    # STEP 8: Compromise of svc_backup (successful logon)
    # -----------------------------------------------------------------------
    Write-Host "Simulating successful compromise (svc_backup)..."
    & net use "\\localhost\IPC$" /user:svc_backup "B@ckServ2024!" 2>$null
    Start-Sleep -Seconds 1
    & net use "\\localhost\IPC$" /delete 2>$null
    Write-Host "  svc_backup: successful logon event generated"

    Start-Sleep -Seconds 1

    # -----------------------------------------------------------------------
    # STEP 9: Privilege escalation (svc_backup -> Administrators + RDP)
    # -----------------------------------------------------------------------
    Write-Host "Simulating privilege escalation (svc_backup)..."
    & net localgroup Administrators svc_backup /add 2>$null
    & net localgroup "Remote Desktop Users" svc_backup /add 2>$null
    Write-Host "  svc_backup added to Administrators and Remote Desktop Users"

    Start-Sleep -Seconds 1

    # -----------------------------------------------------------------------
    # STEP 10: Backdoor account creation + escalation
    # -----------------------------------------------------------------------
    Write-Host "Simulating backdoor account creation (maint_svc)..."
    & net user maint_svc "M@int2024!" /add /fullname:"Maintenance Service" /comment:"System maintenance" 2>$null
    & net localgroup Administrators maint_svc /add 2>$null
    Write-Host "  maint_svc created and added to Administrators (backdoor)"

    Start-Sleep -Seconds 1

    # -----------------------------------------------------------------------
    # STEP 11: Persistence - reset svc_backup password
    # -----------------------------------------------------------------------
    Write-Host "Simulating persistence (svc_backup password reset)..."
    & net user svc_backup "N3wP@ss2024!" 2>$null
    Write-Host "  svc_backup password reset (persistence)"

    # -----------------------------------------------------------------------
    # STEP 12: Record baseline technician count
    # -----------------------------------------------------------------------
    Write-Host "Recording baseline technician count..."
    try {
        $baselineTechs = Invoke-ADAuditDBQuery "SELECT COUNT(*) FROM TechnicianInfo;"
        $baselineTechs = if ($baselineTechs) { $baselineTechs.Trim() } else { "0" }
    } catch {
        $baselineTechs = "query_failed"
    }
    $baselineTechs | Out-File -FilePath "C:\Users\Docker\initial_tech_count_coordinated.txt" -Encoding ASCII -Force
    Write-Host "Baseline technician count: $baselineTechs"

    # -----------------------------------------------------------------------
    # STEP 13: Wait for ADAudit Plus to process events
    # -----------------------------------------------------------------------
    Write-Host "Waiting 45s for ADAudit Plus to index events..."
    Start-Sleep -Seconds 45

    # -----------------------------------------------------------------------
    # STEP 14: Launch browser to ADAudit Plus
    # -----------------------------------------------------------------------
    try {
        Launch-BrowserToADAudit -Path "/" -WaitSeconds 20
        Write-Host "Browser launched to ADAudit Plus"
    } catch {
        Write-Host "Could not launch browser: $_"
    }

    Write-Host "=== Investigate Coordinated Intrusion Setup Complete ==="
    Write-Host "Attack chain: svc_backup(40 fails + 1 success + Administrators + Remote Desktop Users)"
    Write-Host "Backdoor: maint_svc(created + Administrators)"
    Write-Host "Diversion: helpdesk_temp(12 fails, no escalation)"
    Write-Host "Noise: svc_sql(5), svc_deploy(5), svc_monitoring(5), admin_jones(8 + recovery)"
    Write-Host "Task start: $taskStart"
} catch {
    Write-Host "ERROR: $_"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
