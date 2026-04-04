Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up engine_fault_diagnosis task ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# ── 1. Stop any existing Multiecuscan instance ─────────────────────────────
Write-Host "[1/6] Stopping existing Multiecuscan instances..."
Stop-Multiecuscan

# ── 2. Remove pre-existing output files ────────────────────────────────────
Write-Host "[2/6] Cleaning up pre-existing output files..."
$outputFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\engine_diagnostic_report.txt"
Remove-Item $outputFile -Force -ErrorAction SilentlyContinue

# ── 3. Record task start timestamp ─────────────────────────────────────────
Write-Host "[3/6] Recording task start timestamp..."
$startTs = Get-TaskStartTimestamp -TaskName "engine_fault_diagnosis"

# ── 4. Ensure data files are available ─────────────────────────────────────
Write-Host "[4/6] Ensuring reference data files are available..."
Ensure-DataFile -FileName "dtc_database_full.csv"
Ensure-DataFile -FileName "fiat_vehicle_specs.csv"
Ensure-DataFile -FileName "obd2_parameter_reference.csv"
Ensure-DataFile -FileName "diagnostic_procedures.txt"

# Create task-specific instruction file
$instructionFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\engine_diagnosis_instructions.txt"
Set-Content -Path $instructionFile -Value @"
ENGINE FAULT DIAGNOSIS TASK
===========================
Vehicle: Fiat 500 1.3 MultiJet Diesel

Steps:
1. In Multiecuscan, select: Fiat > 500 > Engine system
2. Select the appropriate engine module for the 1.3 MultiJet Diesel
3. Click "Simulate" to start simulation mode
4. Record the ECU identification data
5. Read all Diagnostic Trouble Codes (DTCs)
6. Monitor at least 4 engine parameters: RPM, Coolant Temp, Battery V, Throttle
7. Create report file at:
   C:\Users\Docker\Desktop\MultiecuscanTasks\engine_diagnostic_report.txt

Report must include:
- ECU Info section (part number, HW/SW versions)
- DTC section (codes, descriptions from dtc_database_full.csv)
- Parameter section (values, normal ranges from obd2_parameter_reference.csv)
- Recommendations section

Reference files are in: C:\Users\Docker\Desktop\MultiecuscanData\
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

Write-Host "=== engine_fault_diagnosis task setup complete ==="
