Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up multi_system_scan task ==="

. C:\workspace\scripts\task_utils.ps1

# ── 1. Stop existing instances ─────────────────────────────────────────────
Write-Host "[1/6] Stopping existing Multiecuscan instances..."
Stop-Multiecuscan

# ── 2. Remove pre-existing output ─────────────────────────────────────────
Write-Host "[2/6] Cleaning up..."
$outputFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\multi_system_report.txt"
Remove-Item $outputFile -Force -ErrorAction SilentlyContinue

# ── 3. Record start timestamp ─────────────────────────────────────────────
Write-Host "[3/6] Recording start timestamp..."
$startTs = Get-TaskStartTimestamp -TaskName "multi_system_scan"

# ── 4. Ensure data files ──────────────────────────────────────────────────
Write-Host "[4/6] Ensuring reference data..."
Ensure-DataFile -FileName "dtc_database_full.csv"
Ensure-DataFile -FileName "fiat_vehicle_specs.csv"
Ensure-DataFile -FileName "diagnostic_procedures.txt"

$instructionFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\multi_scan_instructions.txt"
Set-Content -Path $instructionFile -Value @"
MULTI-SYSTEM DIAGNOSTIC SCAN TASK
==================================
Vehicle: Fiat 500

Scan at least THREE systems sequentially (choose from available systems):

For each system:
  Navigate: Fiat > 500 > [System] > [available module]
  Start simulation > Read ECU identification > Read all DTCs > Disconnect

Output file: C:\Users\Docker\Desktop\MultiecuscanTasks\multi_system_report.txt

Report format:
  VEHICLE: Fiat 500
  DATE: [current date/time]

  For each system scanned:
  === SYSTEM N: [SYSTEM NAME] ===
  ECU: [part number, HW, SW]
  DTCs: [code - description]
  Status: [assessment]

  === OVERALL VEHICLE HEALTH ===
  [Summary and recommendations]

DTC reference: C:\Users\Docker\Desktop\MultiecuscanData\dtc_database_full.csv
"@

# ── 5. Kill OneDrive/notifications before launch ────────────────────────────
Write-Host "[5/7] Killing OneDrive and notifications..."
Kill-OneDriveAndNotifications

# ── 6. Launch Multiecuscan ─────────────────────────────────────────────────
Write-Host "[6/7] Launching Multiecuscan..."
$mesExe = Find-MultiecuscanExe
if (-not $mesExe) {
    Write-Host "ERROR: Multiecuscan executable not found!"
    exit 1
}
Launch-MultiecuscanInteractive -MesExe $mesExe -WaitSeconds 25

# ── 7. Dismiss startup dialogs (synchronized — waits for completion) ──────
Write-Host "[7/7] Dismissing startup dialogs and waiting for MES to load..."
Run-DismissDialogs

Write-Host "=== multi_system_scan task setup complete ==="
