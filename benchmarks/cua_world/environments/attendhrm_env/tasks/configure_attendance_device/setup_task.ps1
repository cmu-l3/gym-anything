# setup_task.ps1 — configure_attendance_device
# Prepares the environment for registering a new biometric attendance device.
#
# WHAT IT DOES:
#   - Ensures the "Westside Office" branch exists in the database
#   - Cleans up any prior device record with name "WS-FP-RECEPTION-01"
#   - Launches AttendHRM and logs in

$logPath = "C:\Users\Docker\task_setup_configure_attendance_device.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

try {
    Write-Host "=== Setting up configure_attendance_device task ==="

    . "C:\workspace\scripts\task_utils.ps1"

    New-Item -ItemType Directory -Force -Path "C:\temp" | Out-Null

    Stop-AttendHRM
    Start-Sleep -Seconds 2

    $isqlPath = "C:\Program Files (x86)\Firebird\Firebird_5_0\isql.exe"
    $dbPath   = "C:\Program Files (x86)\Attend HRM\Data\DEMO.FDB"

    function Run-Isql {
        param([string]$sql)
        $tmp = "C:\Windows\Temp\isql_setup_$(Get-Random).sql"
        Set-Content -Path $tmp -Value ($sql + "`nCOMMIT;`nEXIT;") -Encoding ASCII
        $out = & $isqlPath -user SYSDBA -password masterkey $dbPath -q -i $tmp 2>&1
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        return $out
    }

    # ---- Cleanup from any prior test run ----
    Write-Host "Cleaning up prior WS-FP-RECEPTION-01 device..."
    $cleanup = Run-Isql @"
DELETE FROM ATT_DEV WHERE UPPER(DEV_NAME) LIKE '%WS-FP-RECEPTION-01%';
"@
    Write-Host "Cleanup result: $cleanup"

    # ---- Ensure Westside Office branch exists ----
    Write-Host "Ensuring Westside Office branch exists..."
    $branchSetup = Run-Isql @"
UPDATE OR INSERT INTO WGR_BRA (BRA_ID, BRA_NAME, BRA_CODE)
VALUES (
  (SELECT COALESCE(MAX(BRA_ID), 200) + 1 FROM WGR_BRA),
  'Westside Office',
  'WSO'
)
MATCHING (BRA_NAME);
"@
    Write-Host "Branch setup result: $branchSetup"

    # Record setup state
    $state = @{
        expected_device_name = "WS-FP-RECEPTION-01"
        expected_ip          = "192.168.10.45"
        expected_port        = 4370
        expected_serial      = "ZK-TF20-2024-00871"
        expected_branch      = "Westside Office"
        seeded_at            = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    $state | ConvertTo-Json -Depth 3 | Set-Content -Path "C:\temp\configure_attendance_device_setup.json" -Encoding ASCII
    Write-Host "Setup state saved."

    (Get-Date -Format "yyyy-MM-dd HH:mm:ss") | Set-Content -Path "C:\temp\task_start_timestamp.txt" -Encoding ASCII

    # ---- Launch AttendHRM ----
    Close-Browsers
    $edgeKiller = Start-EdgeKillerTask

    try {
        Launch-AttendHRMInteractive -WaitSeconds 15
        $started = Wait-ForAttendHRM -TimeoutSec 30
        if (-not $started) {
            Write-Host "WARNING: AttendHRM not detected, proceeding anyway"
        }
        Login-AttendHRM -WaitAfterLoginSec 6
        Set-AttendHRMForeground | Out-Null
        Start-Sleep -Seconds 1
        Write-Host "Task ready: AttendHRM logged in, agent should register new attendance device."
    } finally {
        Stop-EdgeKillerTask -KillerInfo $edgeKiller
    }

    Write-Host "=== configure_attendance_device setup complete ==="

} catch {
    Write-Host "ERROR in setup_task.ps1: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
