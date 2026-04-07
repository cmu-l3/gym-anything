Set-StrictMode -Off
$ErrorActionPreference = "Continue"

$logPath = "C:\Users\Docker\setup_forensic_attack_chain_analysis.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up Forensic Attack Chain Analysis Task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    $ready = Wait-ForADAudit -TimeoutSec 600
    if (-not $ready) {
        Write-Host "WARNING: ADAudit Plus not ready, proceeding anyway..."
    }

    # -----------------------------------------------------------------------
    # STEP 1: Delete stale output files BEFORE recording timestamp
    # -----------------------------------------------------------------------
    $staleFiles = @(
        "C:\Users\Docker\Desktop\attack_campaign_report.txt"
    )
    foreach ($f in $staleFiles) {
        Remove-Item $f -Force -ErrorAction SilentlyContinue
        Write-Host "Cleaned stale file: $f"
    }

    # -----------------------------------------------------------------------
    # STEP 2: Record task start timestamp AFTER cleanup
    # -----------------------------------------------------------------------
    $taskStart = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $taskStart | Out-File -FilePath "C:\Users\Docker\task_start_ts_forensic_attack_chain.txt" -Encoding ASCII -Force
    Write-Host "Task start timestamp: $taskStart"

    # -----------------------------------------------------------------------
    # STEP 3: Create user accounts for attack simulation
    # -----------------------------------------------------------------------
    Write-Host "Creating user accounts..."

    # Attack target - service account
    & net user svc_backup "SvcBackup@2024!" /add /fullname:"Backup Service Account" 2>$null

    # Noise users
    & net user jsmith "UserPass@123" /add /fullname:"John Smith" 2>$null
    & net user mjohnson "UserPass@123" /add /fullname:"Mike Johnson" 2>$null
    & net user rwilliams "UserPass@123" /add /fullname:"Rachel Williams" 2>$null
    & net user abrown "UserPass@123" /add /fullname:"Alice Brown" 2>$null
    & net user dlee "UserPass@123" /add /fullname:"David Lee" 2>$null

    # Create groups for escalation scenario
    & net localgroup Security_Team /add 2>$null
    & net localgroup IT_Support /add 2>$null
    & net localgroup Server_Admins /add 2>$null

    Write-Host "User accounts and groups created"

    # -----------------------------------------------------------------------
    # STEP 4: Generate noise baseline (normal failed logon activity)
    # -----------------------------------------------------------------------
    Write-Host "Generating baseline noise events..."

    # jsmith: 5 failed logons
    for ($i = 1; $i -le 5; $i++) {
        & net use "\\localhost\IPC$" /user:jsmith "wrong_js_$i" 2>$null
        Start-Sleep -Milliseconds 200
    }
    Write-Host "  jsmith: 5 failed logon events"

    # mjohnson: 3 failed logons
    for ($i = 1; $i -le 3; $i++) {
        & net use "\\localhost\IPC$" /user:mjohnson "wrong_mj_$i" 2>$null
        Start-Sleep -Milliseconds 200
    }
    Write-Host "  mjohnson: 3 failed logon events"

    # rwilliams: 8 failed logons (highest noise, still far below target)
    for ($i = 1; $i -le 8; $i++) {
        & net use "\\localhost\IPC$" /user:rwilliams "wrong_rw_$i" 2>$null
        Start-Sleep -Milliseconds 200
    }
    Write-Host "  rwilliams: 8 failed logon events"

    # abrown: 4 failed logons
    for ($i = 1; $i -le 4; $i++) {
        & net use "\\localhost\IPC$" /user:abrown "wrong_ab_$i" 2>$null
        Start-Sleep -Milliseconds 200
    }
    Write-Host "  abrown: 4 failed logon events"

    # dlee: 6 failed logons
    for ($i = 1; $i -le 6; $i++) {
        & net use "\\localhost\IPC$" /user:dlee "wrong_dl_$i" 2>$null
        Start-Sleep -Milliseconds 200
    }
    Write-Host "  dlee: 6 failed logon events"

    Start-Sleep -Seconds 2

    # -----------------------------------------------------------------------
    # STEP 5: Primary attack - brute-force against svc_backup (50 failed logons)
    # -----------------------------------------------------------------------
    Write-Host "Generating brute-force attack events (svc_backup - 50 attempts)..."
    for ($i = 1; $i -le 50; $i++) {
        & net use "\\localhost\IPC$" /user:svc_backup "BruteAttempt$i!" 2>$null
        Start-Sleep -Milliseconds 250
        if ($i % 10 -eq 0) {
            Write-Host "  Generated $i/50 failed logon events for svc_backup"
        }
    }
    Write-Host "  svc_backup: 50 failed logon events generated"

    Start-Sleep -Seconds 2

    # -----------------------------------------------------------------------
    # STEP 6: Compromise - successful logon for svc_backup
    # -----------------------------------------------------------------------
    Write-Host "Simulating successful compromise (svc_backup)..."
    & net use "\\localhost\IPC$" /user:svc_backup "SvcBackup@2024!" 2>$null
    Start-Sleep -Seconds 1
    & net use "\\localhost\IPC$" /delete 2>$null
    Write-Host "  svc_backup: successful logon event generated"

    Start-Sleep -Seconds 1

    # -----------------------------------------------------------------------
    # STEP 7: Privilege escalation - add svc_backup to Administrators
    # -----------------------------------------------------------------------
    Write-Host "Simulating privilege escalation (svc_backup -> Administrators)..."
    & net localgroup Administrators svc_backup /add 2>$null
    & net localgroup Security_Team svc_backup /add 2>$null
    Write-Host "  svc_backup added to Administrators and Security_Team"

    Start-Sleep -Seconds 1

    # -----------------------------------------------------------------------
    # STEP 8: Noise group changes (benign activity for contrast)
    # -----------------------------------------------------------------------
    Write-Host "Generating benign group change noise..."
    & net localgroup IT_Support mjohnson /add 2>$null
    & net localgroup Server_Admins rwilliams /add 2>$null
    Write-Host "  mjohnson -> IT_Support, rwilliams -> Server_Admins (benign)"

    # -----------------------------------------------------------------------
    # STEP 9: Record baseline technician count
    # -----------------------------------------------------------------------
    Write-Host "Recording baseline technician count..."
    try {
        $baselineTechs = Invoke-ADAuditDBQuery "SELECT COUNT(*) FROM TechnicianInfo;"
        $baselineTechs = if ($baselineTechs) { $baselineTechs.Trim() } else { "0" }
    } catch {
        $baselineTechs = "query_failed"
    }
    $baselineTechs | Out-File -FilePath "C:\Users\Docker\initial_tech_count_forensic.txt" -Encoding ASCII -Force
    Write-Host "Baseline technician count: $baselineTechs"

    # -----------------------------------------------------------------------
    # STEP 10: Wait for ADAudit Plus to process events
    # -----------------------------------------------------------------------
    Write-Host "Waiting 45s for ADAudit Plus to index events..."
    Start-Sleep -Seconds 45

    # -----------------------------------------------------------------------
    # STEP 11: Launch browser to ADAudit Plus
    # -----------------------------------------------------------------------
    try {
        Launch-BrowserToADAudit -Path "/" -WaitSeconds 20
        Write-Host "Browser launched to ADAudit Plus"
    } catch {
        Write-Host "Could not launch browser: $_"
    }

    Write-Host "=== Forensic Attack Chain Analysis Setup Complete ==="
    Write-Host "Attack: svc_backup(50 fails + 1 success + privilege escalation to Administrators)"
    Write-Host "Noise: jsmith(5), mjohnson(3), rwilliams(8), abrown(4), dlee(6)"
    Write-Host "Group noise: mjohnson->IT_Support, rwilliams->Server_Admins"
    Write-Host "Task start: $taskStart"
} catch {
    Write-Host "ERROR: $_"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
