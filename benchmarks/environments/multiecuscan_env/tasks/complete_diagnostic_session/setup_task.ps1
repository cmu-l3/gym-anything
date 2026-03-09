Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up complete_diagnostic_session task ==="

. C:\workspace\scripts\task_utils.ps1

Write-Host "[1/6] Stopping existing Multiecuscan..."
Stop-Multiecuscan

Write-Host "[2/6] Cleaning up..."
Remove-Item "C:\Users\Docker\Desktop\MultiecuscanTasks\full_session_report.txt" -Force -ErrorAction SilentlyContinue

Write-Host "[3/6] Recording start timestamp..."
$startTs = Get-TaskStartTimestamp -TaskName "complete_diagnostic_session"

Write-Host "[4/6] Ensuring all reference data..."
Ensure-DataFile -FileName "dtc_database_full.csv"
Ensure-DataFile -FileName "fiat_vehicle_specs.csv"
Ensure-DataFile -FileName "obd2_parameter_reference.csv"
Ensure-DataFile -FileName "diagnostic_procedures.txt"
Ensure-DataFile -FileName "real_obd_drive_session.csv"
Ensure-DataFile -FileName "real_obd_long_session.csv"

$instructionFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\full_session_instructions.txt"
Set-Content -Path $instructionFile -Value @"
COMPLETE DIAGNOSTIC SESSION TASK
==================================
Vehicle: Fiat Ducato 2.3 JTD

This task requires a COMPLETE diagnostic workflow:

PHASE 1 - ENGINE DIAGNOSTICS
  1. Select: Fiat > Ducato > Engine, then choose the appropriate engine module
  2. Click "Simulate"
  3. Record ECU identification
  4. Read ALL engine DTCs
  5. Monitor at least 4 parameters:
     - Engine RPM
     - Coolant Temperature
     - Battery Voltage (Control Module Voltage)
     - Fuel Rail Pressure (or Intake Manifold Pressure if unavailable)
  6. View parameter graph
  7. Disconnect

PHASE 2 - BODY COMPUTER
  8. Select: Fiat > Ducato > Body > Body Computer
  9. Click "Simulate"
  10. Read ECU info
  11. Read body DTCs
  12. Disconnect

PHASE 3 - REPORT
  13. Create comprehensive report at:
      C:\Users\Docker\Desktop\MultiecuscanTasks\full_session_report.txt

REPORT FORMAT (5 mandatory sections):
  A. VEHICLE & SESSION INFO
     - Vehicle make/model/year/engine
     - Date and time of session
     - Diagnostic tool used

  B. ENGINE ECU IDENTIFICATION
     - Part number, HW version, SW version
     - System status

  C. ENGINE DTCs
     - All codes found
     - Description for each (from dtc_database_full.csv)
     - Status (active/stored)
     - Severity assessment

  D. ENGINE PARAMETER ANALYSIS
     - For each of 4 parameters: observed value, unit
     - Normal range (from obd2_parameter_reference.csv)
     - Comparison with real-world data (real_obd_drive_session.csv)
     - In-range assessment

  E. BODY COMPUTER DTCs
     - ECU identification
     - Body-related DTCs found
     - Descriptions

  F. OVERALL ASSESSMENT
     - Vehicle health summary
     - Prioritized repair recommendations
     - Urgency level for each issue

Reference files in C:\Users\Docker\Desktop\MultiecuscanData\:
- dtc_database_full.csv: 3000+ real OBD-II trouble codes
- obd2_parameter_reference.csv: Normal parameter ranges
- real_obd_drive_session.csv: Real OBD-II driving session data
- real_obd_long_session.csv: Extended real driving session data
- diagnostic_procedures.txt: Standard diagnostic procedures
- fiat_vehicle_specs.csv: Vehicle specifications
"@

Write-Host "[5/7] Killing OneDrive and notifications..."
Kill-OneDriveAndNotifications

Write-Host "[6/7] Launching Multiecuscan..."
$mesExe = Find-MultiecuscanExe
if (-not $mesExe) { Write-Host "ERROR: Multiecuscan not found!"; exit 1 }
Launch-MultiecuscanInteractive -MesExe $mesExe -WaitSeconds 25

Write-Host "[7/7] Dismissing startup dialogs and waiting for MES to load..."
Run-DismissDialogs

Write-Host "=== complete_diagnostic_session task setup complete ==="
