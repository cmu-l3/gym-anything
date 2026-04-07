Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up fleet_health_priority_matrix task ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# ── 1. Stop any existing Multiecuscan instance ─────────────────────────────
Write-Host "[1/7] Stopping existing Multiecuscan instances..."
Stop-Multiecuscan

# ── 2. Remove pre-existing output files ────────────────────────────────────
Write-Host "[2/7] Cleaning up pre-existing output files..."
$outputFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\fleet_priority_matrix.txt"
Remove-Item $outputFile -Force -ErrorAction SilentlyContinue

# ── 3. Record task start timestamp ─────────────────────────────────────────
Write-Host "[3/7] Recording task start timestamp..."
$startTs = Get-TaskStartTimestamp -TaskName "fleet_health_priority_matrix"

# ── 4. Ensure data files are available ─────────────────────────────────────
Write-Host "[4/7] Ensuring reference data files are available..."
Ensure-DataFile -FileName "dtc_database_full.csv"
Ensure-DataFile -FileName "fiat_vehicle_specs.csv"
Ensure-DataFile -FileName "obd2_parameter_reference.csv"
Ensure-DataFile -FileName "diagnostic_procedures.txt"

# ── 5. Drop fleet manager briefing document ────────────────────────────────
Write-Host "[5/7] Creating fleet manager briefing document..."
$briefingFile = "C:\Users\Docker\Desktop\FLEET_BRIEFING_Urgent_Health_Check.txt"

Set-Content -Path $briefingFile -Encoding UTF8 -Value @"
=============================================================
  NEXPRESS LOGISTICS LTD
  FLEET MAINTENANCE BRIEFING
=============================================================
Issued by    : James Hargreaves, Fleet Manager
Date         : $(Get-Date -Format "dd/MM/yyyy")
To           : Fleet Technician (You)
Priority     : URGENT - Combined Service Slot Monday AM

BACKGROUND
----------
We have a combined service slot booked with SH Fleet Services on
Monday morning for 3 vehicles. The slot covers routine service
for all three, but engineering time is limited.

Before the vehicles go in, I need you to perform an electronic
diagnostic triage so the service team knows what to expect and
can order any required parts in advance. We cannot afford
unplanned downtime next week - two of these vehicles are on
scheduled delivery contracts.

VEHICLES REQUIRING ASSESSMENT
-------------------------------

VEHICLE A - CNG/PETROL COMBO
  Make/Model  : Fiat Punto 1.4 Natural Power
  Year        : 2014
  Engine      : 1368cc CNG/Petrol (199B4.000)
  Registration: FP14 NGP
  VIN         : ZFA18800000CNG421
  Mileage     : 68,420 km
  Last Service: 14 months ago (overdue by 2 months)
  Driver notes: "Slight hesitation when switching from CNG to petrol.
                 Engine light on for 2 weeks, went off yesterday."
  Usage       : Light urban deliveries, 120km/day

VEHICLE B - PETROL TURBO HATCHBACK
  Make/Model  : Alfa Romeo Giulietta 1.4 MultiAir Turbo
  Year        : 2013
  Engine      : 1368cc Petrol Turbo (940A2.000)
  Registration: AR13 GLT
  VIN         : ZAR940000B0GL1397
  Mileage     : 134,000 km
  Last Service: 6 months ago (on schedule)
  Driver notes: "Occasionally stutters at low RPM in heavy traffic.
                 No warning lights currently."
  Usage       : Sales rep / long-distance (500km/week)

VEHICLE C - DIESEL VAN
  Make/Model  : Fiat Ducato 2.3 Multijet 150HP L2H1
  Year        : 2016
  Engine      : 2287cc Diesel (F1AE0481G - 150HP)
  Registration: FD16 DUC
  VIN         : ZFA25000002FD1631
  Mileage     : 214,800 km
  Last Service: 3 months ago (on schedule)
  Driver notes: "Sometimes feels sluggish when loaded. DPF light
                 came on briefly twice last month, reset itself."
  Usage       : Heavy delivery van, 300km/day loaded

WHAT I NEED FROM YOU
---------------------
Using Multiecuscan (simulation mode) - scan Engine ECU of each vehicle:

FOR EACH VEHICLE:
  1. ECU identification (part number, HW version, SW version)
  2. All stored + pending DTCs (descriptions from dtc_database_full.csv)
  3. At least 3 engine parameters (coolant, fuel status, voltage, etc.)

THEN PRODUCE A COMPARATIVE REPORT:
  File: C:\Users\Docker\Desktop\MultiecuscanTasks\fleet_priority_matrix.txt

REPORT MUST INCLUDE:
  1. Side-by-side comparison table (Vehicle A vs B vs C)
     Columns: DTC count, Severity, ECU health, Urgent attention?
  2. Individual section per vehicle (full ECU info + DTCs + params)
  3. Priority Ranking table:
     - Rank 1: Most urgent (needs attention before Monday)
     - Rank 2: Moderate (service team should be aware)
     - Rank 3: Least urgent (routine service sufficient)
  4. Pre-service actions for each vehicle
     (parts to pre-order, special procedures, code clearing, etc.)
  5. Estimated downtime / cost impact per vehicle

REFERENCE DATA (C:\Users\Docker\Desktop\MultiecuscanData\)
-----------------------------------------------------------
- dtc_database_full.csv       : DTC descriptions
- obd2_parameter_reference.csv: Normal parameter ranges
- fiat_vehicle_specs.csv      : Vehicle technical specs
- diagnostic_procedures.txt   : Diagnostic procedures

DEADLINE: Report needed by end of today so I can
brief the service team and order parts tomorrow.

Thanks,
James Hargreaves
Fleet Manager, NexPress Logistics Ltd
=============================================================
"@

Write-Host "Fleet briefing created at: $briefingFile"

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

Write-Host "=== fleet_health_priority_matrix task setup complete ==="
Write-Host "Fleet briefing on Desktop: FLEET_BRIEFING_Urgent_Health_Check.txt"
