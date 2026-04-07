Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up electrical_consumer_drain_audit task ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# ── 1. Stop any existing Multiecuscan instance ─────────────────────────────
Write-Host "[1/7] Stopping existing Multiecuscan instances..."
Stop-Multiecuscan

# ── 2. Remove pre-existing output files ────────────────────────────────────
Write-Host "[2/7] Cleaning up pre-existing output files..."
$outputFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\drain_audit_report.txt"
Remove-Item $outputFile -Force -ErrorAction SilentlyContinue

# ── 3. Record task start timestamp ─────────────────────────────────────────
Write-Host "[3/7] Recording task start timestamp..."
$startTs = Get-TaskStartTimestamp -TaskName "electrical_consumer_drain_audit"

# ── 4. Ensure data files are available ─────────────────────────────────────
Write-Host "[4/7] Ensuring reference data files are available..."
Ensure-DataFile -FileName "dtc_database_full.csv"
Ensure-DataFile -FileName "fiat_vehicle_specs.csv"
Ensure-DataFile -FileName "obd2_parameter_reference.csv"
Ensure-DataFile -FileName "diagnostic_procedures.txt"

# ── 5. Drop customer work order ────────────────────────────────────────────
Write-Host "[5/7] Creating customer work order..."
$workOrderFile = "C:\Users\Docker\Desktop\WORK_ORDER_500L_BatteryDrain.txt"

Set-Content -Path $workOrderFile -Encoding UTF8 -Value @"
=============================================================
  AUTO-ELECTRICAL DIAGNOSTIC WORK ORDER
=============================================================
Work Order: AE-2024-0392
Date: $(Get-Date -Format "dd/MM/yyyy")
Auto-Electrician: (Your Name)

VEHICLE DETAILS
---------------
Make/Model  : Fiat 500L 1.4 16v Easy
Year        : 2015
Engine      : 1368cc Petrol (199B6.000 - 95HP)
Transmission: 6-speed Manual
Mileage     : 52,814 miles
Registration: FN15 BXK
VIN         : ZFA33900000385421
Colour      : Yacht Blue

CUSTOMER COMPLAINT (verbatim)
------------------------------
"The car keeps draining the battery overnight. I replaced the battery
6 weeks ago with a brand new Bosch S5 096 AGM and that's already
struggling to start. My mechanic checked the alternator and says
it's charging fine at 14.2V when running.
I sometimes leave the car for 2-3 days without driving it and it's
completely dead when I come back. Started happening about 4 months ago,
around the time I got a new key fob and had the alarm serviced."

BATTERY REPLACEMENT HISTORY
-----------------------------
Date        | Battery           | Workshop
------------|-------------------|------------------
12 Mar 2022 | Varta C15 (OEM)  | Quick Fit Center
08 Jan 2024 | Bosch S5 096 AGM | Customer (DIY)
(Still in) NOTE: Battery tested weak after only 6 weeks

DIAGNOSTIC HISTORY
------------------
[02 Feb 2024] Halfords battery test: "Battery: REPLACE (weak)"
              Alternator: "PASS - 14.2V charging voltage"
              No further diagnostics performed.

DIAGNOSTIC REQUIREMENTS
-----------------------
Perform electronic module audit to identify parasitic drain source.

REQUIRED: Cross-system scan of BOTH:

SYSTEM 1 - Body Computer (BSI/BCM):
  - Connect to Body Computer module in Multiecuscan
  - Read all stored DTCs
  - Look for: CAN bus faults, network wake-up codes,
    comfort module faults, alarm system codes, central
    locking anomalies, anything suggesting a module
    failing to sleep after ignition-off

SYSTEM 2 - Engine ECU:
  - Connect to Engine ECU in Multiecuscan
  - Read battery voltage live parameter
  - Read alternator / smart charge parameters if available
  - Read any charging system or CAN communication DTCs

REPORT REQUIRED:
  C:\Users\Docker\Desktop\MultiecuscanTasks\drain_audit_report.txt

Report must include:
  1. ECU identification for BOTH systems (Body Computer + Engine)
  2. ALL DTCs from both systems with descriptions
     (cross-reference dtc_database_full.csv)
  3. Battery voltage and charging system parameters
  4. Ranked suspect list (which module most likely causing drain)
  5. Recommended next steps (fuse pull test sequence, which
     circuits to isolate first, current clamp procedure)

REFERENCE DATA (C:\Users\Docker\Desktop\MultiecuscanData\)
-----------------------------------------------------------
- dtc_database_full.csv       : DTC descriptions
- obd2_parameter_reference.csv: Normal parameter ranges
- fiat_vehicle_specs.csv      : Fiat 500L technical data
- diagnostic_procedures.txt   : Electrical diagnostic procedures

NOTES FOR TECHNICIAN:
- Fiat 500L uses FIAT's BSI (Body Systems Interface) as body computer
- CAN bus network includes: Engine ECU, ABS, Body Computer, Airbag,
  Instrument Cluster, Climate Control, Infotainment, Gateway
- Quiescent current should be <50mA after 10min sleep
- If alarm system was recently "serviced" - check for alarm siren
  module staying active (common drain source on 500L)
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

Write-Host "=== electrical_consumer_drain_audit task setup complete ==="
Write-Host "Work order on Desktop: WORK_ORDER_500L_BatteryDrain.txt"
