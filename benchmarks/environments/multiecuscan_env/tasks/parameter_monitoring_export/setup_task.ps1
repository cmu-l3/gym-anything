Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up parameter_monitoring_export task ==="

. C:\workspace\scripts\task_utils.ps1

Write-Host "[1/6] Stopping existing Multiecuscan..."
Stop-Multiecuscan

Write-Host "[2/6] Cleaning up..."
Remove-Item "C:\Users\Docker\Desktop\MultiecuscanTasks\parameter_analysis.txt" -Force -ErrorAction SilentlyContinue

Write-Host "[3/6] Recording start timestamp..."
$startTs = Get-TaskStartTimestamp -TaskName "parameter_monitoring_export"

Write-Host "[4/6] Ensuring reference data..."
Ensure-DataFile -FileName "obd2_parameter_reference.csv"
Ensure-DataFile -FileName "real_obd_drive_session.csv"
Ensure-DataFile -FileName "real_obd_idle_session.csv"
Ensure-DataFile -FileName "fiat_vehicle_specs.csv"

$instructionFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\parameter_monitor_instructions.txt"
Set-Content -Path $instructionFile -Value @"
PARAMETER MONITORING & EXPORT TASK
====================================
Vehicle: Alfa Romeo MiTo 1.4 MultiAir Turbo

Steps:
1. Select: Alfa Romeo > MiTo > Engine, then choose the appropriate engine module
2. Click "Simulate"
3. Navigate to the Parameters view
4. Select at least 4 parameters:
   - Engine RPM
   - Engine Coolant Temperature
   - Control Module Voltage (Battery Voltage)
   - Throttle Position
5. Observe live values for at least 10 seconds
6. Navigate to the Graph view to see graphical display
7. Create analysis report at:
   C:\Users\Docker\Desktop\MultiecuscanTasks\parameter_analysis.txt

Report must include:
- Parameter name, observed value(s), unit
- Min/Max/Average estimates from observation
- Normal operating range (from obd2_parameter_reference.csv)
- In-range assessment (OK / WARNING / CRITICAL)
- Comparison with real-world data (real_obd_drive_session.csv)

Reference files in MultiecuscanData:
- obd2_parameter_reference.csv: Normal ranges per SAE J1979
- real_obd_drive_session.csv: Real OBD-II driving session log
- real_obd_idle_session.csv: Real OBD-II idle session log
"@

Write-Host "[5/7] Killing OneDrive and notifications..."
Kill-OneDriveAndNotifications

Write-Host "[6/7] Launching Multiecuscan..."
$mesExe = Find-MultiecuscanExe
if (-not $mesExe) { Write-Host "ERROR: Multiecuscan not found!"; exit 1 }
Launch-MultiecuscanInteractive -MesExe $mesExe -WaitSeconds 25

Write-Host "[7/7] Dismissing startup dialogs and waiting for MES to load..."
Run-DismissDialogs

Write-Host "=== parameter_monitoring_export task setup complete ==="
