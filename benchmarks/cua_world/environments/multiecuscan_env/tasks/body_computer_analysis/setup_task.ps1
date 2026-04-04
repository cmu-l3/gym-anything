Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up body_computer_analysis task ==="

. C:\workspace\scripts\task_utils.ps1

Write-Host "[1/6] Stopping existing Multiecuscan..."
Stop-Multiecuscan

Write-Host "[2/6] Cleaning up..."
Remove-Item "C:\Users\Docker\Desktop\MultiecuscanTasks\body_computer_report.txt" -Force -ErrorAction SilentlyContinue

Write-Host "[3/6] Recording start timestamp..."
$startTs = Get-TaskStartTimestamp -TaskName "body_computer_analysis"

Write-Host "[4/6] Ensuring reference data..."
Ensure-DataFile -FileName "dtc_database_full.csv"
Ensure-DataFile -FileName "fiat_vehicle_specs.csv"
Ensure-DataFile -FileName "diagnostic_procedures.txt"

$instructionFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\body_computer_instructions.txt"
Set-Content -Path $instructionFile -Value @"
BODY COMPUTER ANALYSIS TASK
============================
Vehicle: Fiat 500
System: Body Computer (BCM)

Steps:
1. Select: Fiat > 500 > Body > Body Computer module
2. Click "Simulate"
3. Record ECU identification (part number, HW/SW)
4. Check for body-related DTCs
   - Look for B-codes (Body) and U-codes (Network)
5. Explore all available configuration and adjustment settings
   - Document each category and available settings
   - Note current values where visible

Output: C:\Users\Docker\Desktop\MultiecuscanTasks\body_computer_report.txt

Report sections:
1. ECU IDENTIFICATION
2. BODY DTCs (with descriptions from dtc_database_full.csv)
3. CONFIGURATION SETTINGS (category, setting, current value)
4. RECOMMENDATIONS (common owner-requested changes)

DTC reference: C:\Users\Docker\Desktop\MultiecuscanData\dtc_database_full.csv
Procedures: C:\Users\Docker\Desktop\MultiecuscanData\diagnostic_procedures.txt
"@

Write-Host "[5/7] Killing OneDrive and notifications..."
Kill-OneDriveAndNotifications

Write-Host "[6/7] Launching Multiecuscan..."
$mesExe = Find-MultiecuscanExe
if (-not $mesExe) { Write-Host "ERROR: Multiecuscan not found!"; exit 1 }
Launch-MultiecuscanInteractive -MesExe $mesExe -WaitSeconds 25

Write-Host "[7/7] Dismissing startup dialogs and waiting for MES to load..."
Run-DismissDialogs

Write-Host "=== body_computer_analysis task setup complete ==="
