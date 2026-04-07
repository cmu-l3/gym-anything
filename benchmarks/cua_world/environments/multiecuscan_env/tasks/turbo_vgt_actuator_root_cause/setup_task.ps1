Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up turbo_vgt_actuator_root_cause task ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# ── 1. Stop any existing Multiecuscan instance ─────────────────────────────
Write-Host "[1/7] Stopping existing Multiecuscan instances..."
Stop-Multiecuscan

# ── 2. Remove pre-existing output files ────────────────────────────────────
Write-Host "[2/7] Cleaning up pre-existing output files..."
$outputFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\turbo_rca_report.txt"
Remove-Item $outputFile -Force -ErrorAction SilentlyContinue

# ── 3. Record task start timestamp ─────────────────────────────────────────
Write-Host "[3/7] Recording task start timestamp..."
$startTs = Get-TaskStartTimestamp -TaskName "turbo_vgt_actuator_root_cause"

# ── 4. Ensure data files are available ─────────────────────────────────────
Write-Host "[4/7] Ensuring reference data files are available..."
Ensure-DataFile -FileName "dtc_database_full.csv"
Ensure-DataFile -FileName "fiat_vehicle_specs.csv"
Ensure-DataFile -FileName "obd2_parameter_reference.csv"
Ensure-DataFile -FileName "diagnostic_procedures.txt"

# ── 5. Drop customer work order with vehicle history ──────────────────────
Write-Host "[5/7] Creating customer work order with vehicle history..."
$workOrderFile = "C:\Users\Docker\Desktop\WORK_ORDER_Punto_PowerLoss.txt"

Set-Content -Path $workOrderFile -Encoding UTF8 -Value @"
=============================================================
  FIAT DEALERSHIP - TECHNICAL REPAIR ORDER (TRO)
=============================================================
TRO Number  : TRO-2024-1183
Date        : $(Get-Date -Format "dd/MM/yyyy")
Technician  : (Your Name / Badge Number)
Priority    : URGENT - Customer waiting

VEHICLE DETAILS
---------------
Make/Model  : Fiat Punto 1.3 Multijet Diesel Active
Year        : 2012
Engine      : 1248cc Diesel (169A1.000 - 75HP)
Transmission: 5-speed Manual
Mileage     : 94,217 miles
Registration: LK12 RWP
VIN         : ZFA19900000742816
Colour      : Bossa Nova White

CUSTOMER COMPLAINT (verbatim)
------------------------------
"When I drive on the motorway and accelerate hard past about 50mph,
the car feels like it suddenly loses all power - like hitting a wall.
The engine warning light flashes a few times then sometimes stays on.
Sometimes the car barely makes it to 60mph. When I pull over and
restart the engine it's fine again for a while.
This has been happening for about 3 months, getting worse."

VEHICLE HISTORY FROM OUR RECORDS
---------------------------------
- 82,000 miles: Oil service (5W-30, correct spec)
- 89,000 miles: Air filter replaced
- 91,500 miles: Customer complained of sluggish performance - no fault
  codes found at that time, EGR cleaned externally
- 93,000 miles: DPF forced regen performed, Soot level was 89%

PREVIOUS WORKSHOP NOTES
------------------------
[91,500 mi] Tech D. Baker: "No live fault codes at time of visit.
Boost pressure appeared normal at idle. EGR valve exterior cleaned.
Advised customer to monitor."

[93,000 mi] Tech M. Singh: "DPF regen performed. Engine parameters
checked - all within spec. No turbo-related DTCs at time of visit.
Turbo actuator not tested due to no codes present."

DIAGNOSTIC TASK
---------------
Perform comprehensive turbo system root cause analysis:

1. Connect to Engine ECU in Multiecuscan (simulation mode)
2. Read ALL stored + pending DTCs (pay attention to P02xx, P03xx, boost)
3. Monitor live parameters: Boost Pressure (actual vs requested),
   MAF, EGR valve position, Throttle, RPM, Coolant Temp, Actuator duty
4. Identify most probable root cause from:
   a) VGT actuator solenoid failure (P0045, P0046)
   b) VGT geometry stuck or carbon-fouled (P0234, P0299)
   c) Boost pressure sensor fault (P0235, P0236)
   d) EGR valve causing reduced airflow (P0400, P0401, P0404)
   e) Intercooler pipe leak (no specific code - manifest as low boost)

5. Write report to:
   C:\Users\Docker\Desktop\MultiecuscanTasks\turbo_rca_report.txt

REPORT MUST INCLUDE:
- ECU identification
- All DTCs with descriptions (cross-ref dtc_database_full.csv)
- Live parameter readings with normal range comparison
- Root cause identification with evidence from diagnostic data
- Recommended repair actions
- Estimated labour time

REFERENCE DATA (C:\Users\Docker\Desktop\MultiecuscanData\)
-----------------------------------------------------------
- dtc_database_full.csv       : 3,000+ DTC code descriptions
- obd2_parameter_reference.csv: Parameter normal ranges
- fiat_vehicle_specs.csv      : Fiat vehicle technical specs
- diagnostic_procedures.txt   : Standard diagnostic workflows

AUTHORISATION FOR DIAGNOSTIC WORK: APPROVED (max 1.5 hrs diagnostic)
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

# ── 8. Dismiss startup dialogs ────────────────────────────────────────────
Write-Host "[8/7] Dismissing startup dialogs..."
Run-DismissDialogs

Write-Host "=== turbo_vgt_actuator_root_cause task setup complete ==="
Write-Host "Work order on Desktop: WORK_ORDER_Punto_PowerLoss.txt"
