Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up emissions_readiness_assessment task ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# ── 1. Stop any existing Multiecuscan instance ─────────────────────────────
Write-Host "[1/7] Stopping existing Multiecuscan instances..."
Stop-Multiecuscan

# ── 2. Remove pre-existing output files ────────────────────────────────────
Write-Host "[2/7] Cleaning up pre-existing output files..."
$outputFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\emissions_readiness_report.txt"
Remove-Item $outputFile -Force -ErrorAction SilentlyContinue

# ── 3. Record task start timestamp ─────────────────────────────────────────
Write-Host "[3/7] Recording task start timestamp..."
$startTs = Get-TaskStartTimestamp -TaskName "emissions_readiness_assessment"

# ── 4. Ensure data files are available ─────────────────────────────────────
Write-Host "[4/7] Ensuring reference data files are available..."
Ensure-DataFile -FileName "dtc_database_full.csv"
Ensure-DataFile -FileName "fiat_vehicle_specs.csv"
Ensure-DataFile -FileName "obd2_parameter_reference.csv"
Ensure-DataFile -FileName "diagnostic_procedures.txt"

# ── 5. Drop customer work order on Desktop ──────────────────────────────────
Write-Host "[5/7] Creating customer work order..."
$workOrderDir = "C:\Users\Docker\Desktop"
$workOrderFile = "$workOrderDir\WORK_ORDER_MiTo_MOT_Check.txt"

Set-Content -Path $workOrderFile -Encoding UTF8 -Value @"
=============================================================
  INDEPENDENT MOT STATION - PRE-MOT DIAGNOSTIC WORK ORDER
=============================================================
Work Order #: WO-2024-0847
Date: $(Get-Date -Format "dd/MM/yyyy")
Technician: (Your Name)

CUSTOMER DETAILS
----------------
Name: Sarah Mitchell
Phone: 07891 234567
Email: s.mitchell@email.co.uk

VEHICLE DETAILS
---------------
Make/Model: Alfa Romeo MiTo 1.4 TB Lusso
Year: 2010
Engine: 1368cc Petrol Turbo (955A8.000)
Fuel: Petrol
Transmission: 6-speed Manual
Mileage: 78,432 miles
Registration: EX10 KLM
VIN: ZAR955000A1234567
Colour: Competizione Red

CUSTOMER COMPLAINT
------------------
"I need an MOT and want to check if the car will pass emissions.
The battery went flat 3 weeks ago and had to be replaced.
The engine management light came on briefly last week but
went off by itself. Just wants to make sure it's ready."

PRE-MOT CHECK REQUESTED
------------------------
- OBD-II readiness monitor status (all monitors)
- DTC scan (stored + pending codes)
- Emissions system health
- Formal readiness verdict for MOT

REPORT REQUIRED
---------------
Please produce a written report at:
C:\Users\Docker\Desktop\MultiecuscanTasks\emissions_readiness_report.txt

The report MUST include:
1. Vehicle & ECU identification
2. Readiness monitor status table (each monitor: COMPLETE / INCOMPLETE / N/A)
3. All DTCs with descriptions (use dtc_database_full.csv for descriptions)
4. MOT verdict: READY / NOT READY / CONDITIONAL
5. Required drive cycles for any incomplete monitors
6. Estimated mileage/time to complete readiness

REFERENCE FILES (in C:\Users\Docker\Desktop\MultiecuscanData\)
----------------------------------------------------------------
- dtc_database_full.csv     : DTC code descriptions
- obd2_parameter_reference.csv : Normal parameter ranges
- diagnostic_procedures.txt : Standard OBD-II drive cycle procedures

NOTE: UK MOT rules allow max 1 incomplete monitor on post-2000 vehicles.
If catalyst monitor is incomplete, vehicle CANNOT pass MOT emissions test.
=============================================================
"@

Write-Host "Work order created at: $workOrderFile"

# ── 6. Kill OneDrive/notifications before launch ────────────────────────────
Write-Host "[6/7] Killing OneDrive and notifications..."
Kill-OneDriveAndNotifications

# ── 7. Launch Multiecuscan ─────────────────────────────────────────────────
Write-Host "[7/7] Launching Multiecuscan..."
$mesExe = Find-MultiecuscanExe
if (-not $mesExe) {
    Write-Host "ERROR: Multiecuscan executable not found!"
    exit 1
}
Launch-MultiecuscanInteractive -MesExe $mesExe -WaitSeconds 25

# ── 8. Dismiss startup dialogs (synchronized — waits for completion) ──────
Write-Host "[8/7] Dismissing startup dialogs and waiting for MES to load..."
Run-DismissDialogs

Write-Host "=== emissions_readiness_assessment task setup complete ==="
Write-Host "Work order on Desktop: WORK_ORDER_MiTo_MOT_Check.txt"
