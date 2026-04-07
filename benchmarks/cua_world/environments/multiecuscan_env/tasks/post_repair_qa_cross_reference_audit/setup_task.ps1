Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up post_repair_qa_cross_reference_audit task ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# ── 1. Stop any existing Multiecuscan instance ─────────────────────────────
Write-Host "[1/8] Stopping existing Multiecuscan instances..."
Stop-Multiecuscan

# ── 2. Remove pre-existing output files ────────────────────────────────────
Write-Host "[2/8] Cleaning up pre-existing output files..."
$outputFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\qa_verification_report.txt"
Remove-Item $outputFile -Force -ErrorAction SilentlyContinue

# ── 3. Record task start timestamp ─────────────────────────────────────────
Write-Host "[3/8] Recording task start timestamp..."
$startTs = Get-TaskStartTimestamp -TaskName "post_repair_qa_cross_reference_audit"

# ── 4. Ensure data files are available ─────────────────────────────────────
Write-Host "[4/8] Ensuring reference data files are available..."
Ensure-DataFile -FileName "dtc_database_full.csv"
Ensure-DataFile -FileName "fiat_vehicle_specs.csv"
Ensure-DataFile -FileName "obd2_parameter_reference.csv"
Ensure-DataFile -FileName "diagnostic_procedures.txt"

# ── 5. Drop QA work order document ────────────────────────────────────────
Write-Host "[5/8] Creating QA work order document..."
$workOrderFile = "C:\Users\Docker\Desktop\QA_WORK_ORDER_Ducato_PostRepair.txt"

Set-Content -Path $workOrderFile -Encoding UTF8 -Value @"
=============================================================
  MERIDIAN COMMERCIAL VEHICLE SERVICES
  POST-REPAIR QUALITY ASSURANCE WORK ORDER
=============================================================
Work Order:    QA-2024-2847
Original RO:   WO-2024-2831 (completed 15/03/2024)
QA Date:       $(Get-Date -Format "dd/MM/yyyy")
Workshop:      Meridian Commercial Vehicle Services

VEHICLE INFORMATION
-------------------
Make/Model  : Fiat Ducato (250) Facelift
Engine      : 2.3 Multijet 130HP (F1AE3481D)
Year        : 2016
Registration: BD17 HRX
VIN         : ZFA25000002198745
Odometer    : 156,830 miles

ORIGINAL REPAIR SUMMARY (WO-2024-2831)
---------------------------------------
1. VGT turbo actuator replacement
   - Part fitted: 49335-01960 (Mitsubishi TD04)
   - Original fault: P0234 overboost + mechanical seizure
2. Intercooler outlet hose replacement
   - Split found during turbo removal
3. Body Computer software reflash
   - Updated to latest calibration per FCA TSB 08-032-24
   - Original fault: Intermittent CAN gateway timeout (U0100)

CUSTOMER CALLBACK (3 days post-repair)
--------------------------------------
"Vehicle doesn't feel right since collection."
  - Occasional hesitation at 2000-2500 RPM
  - Amber engine warning light appeared once, cleared itself
  - Dashboard clock reset to 00:00 (noted on collection)

QA INSPECTION REQUIREMENTS
--------------------------
Perform ISO-compliant post-repair verification using
Multiecuscan in SIMULATION MODE.

STEP 1 - ECU SCANNING
  a) ENGINE ECU
     - Record ECU part number, HW version, SW version
     - Read ALL stored and pending DTCs
     - Record at least 8 engine parameters
       (e.g. RPM, coolant temp, battery voltage, throttle,
        MAF, fuel pressure, EGR, intake air temp, etc.)

  b) BODY COMPUTER
     - Record ECU part number, HW version, SW version
     - Read ALL stored and pending DTCs
     - Note any CAN communication or network faults

STEP 2 - DATA CROSS-REFERENCE
  Open files from C:\Users\Docker\Desktop\MultiecuscanData\

  a) Look up EVERY DTC found in dtc_database_full.csv
     Include the full description text from the CSV file.

  b) For each engine parameter recorded, look up the normal
     idle specification range in obd2_parameter_reference.csv
     Include the Normal_Idle_Min and Normal_Idle_Max values.

  c) Verify the vehicle engine code (F1AE3481D) and ECU type
     against the entries in fiat_vehicle_specs.csv.

STEP 3 - QA REPORT
  Create report at:
  C:\Users\Docker\Desktop\MultiecuscanTasks\qa_verification_report.txt

  Report MUST include these sections:
  1. VEHICLE IDENTIFICATION
     Make, model, VIN, engine code, mileage

  2. ENGINE ECU FINDINGS
     ECU identification (part number, HW/SW)
     All DTCs with full descriptions from dtc_database_full.csv
     Parameter readings

  3. BODY COMPUTER FINDINGS
     ECU identification (part number, HW/SW)
     All DTCs with full descriptions from dtc_database_full.csv

  4. PARAMETER COMPARISON TABLE
     For each engine parameter recorded:
     | Parameter | Observed Value | Normal Range (from CSV) | Status |
     Use Normal_Idle_Min and Normal_Idle_Max from
     obd2_parameter_reference.csv

  5. VEHICLE SPECIFICATION VERIFICATION
     Confirm engine code and ECU type match fiat_vehicle_specs.csv

  6. QA VERDICT
     PASSED / CONDITIONAL PASS / FAILED
     With reasoning addressing:
     - Was the turbo repair completed correctly?
     - Was the body computer reflash successful?
     - Are there any new faults?

Workshop QA Manager: David Foster
Priority: HIGH - customer awaiting callback by end of day
=============================================================
"@

Write-Host "QA work order created at: $workOrderFile"

# ── 6. Kill OneDrive/notifications before launch ────────────────────────────
Write-Host "[6/8] Killing OneDrive and notifications..."
Kill-OneDriveAndNotifications

# ── 7. Launch Multiecuscan ─────────────────────────────────────────────────
Write-Host "[7/8] Launching Multiecuscan..."
$mesExe = Find-MultiecuscanExe
if (-not $mesExe) {
    Write-Host "ERROR: Multiecuscan executable not found!"
    exit 1
}
Launch-MultiecuscanInteractive -MesExe $mesExe -WaitSeconds 25

# ── 8. Dismiss startup dialogs ────────────────────────────────────────────
Write-Host "[8/8] Dismissing startup dialogs..."
Run-DismissDialogs

Write-Host "=== post_repair_qa_cross_reference_audit task setup complete ==="
Write-Host "QA work order on Desktop: QA_WORK_ORDER_Ducato_PostRepair.txt"
