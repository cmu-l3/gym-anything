Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up comprehensive_prepurchase_audit task ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# ── 1. Stop any existing Multiecuscan instance ─────────────────────────────
Write-Host "[1/7] Stopping existing Multiecuscan instances..."
Stop-Multiecuscan

# ── 2. Remove pre-existing output files ────────────────────────────────────
Write-Host "[2/7] Cleaning up pre-existing output files..."
$outputFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\prepurchase_certificate.txt"
Remove-Item $outputFile -Force -ErrorAction SilentlyContinue

# ── 3. Record task start timestamp ─────────────────────────────────────────
Write-Host "[3/7] Recording task start timestamp..."
$startTs = Get-TaskStartTimestamp -TaskName "comprehensive_prepurchase_audit"

# ── 4. Ensure data files are available ─────────────────────────────────────
Write-Host "[4/7] Ensuring reference data files are available..."
Ensure-DataFile -FileName "dtc_database_full.csv"
Ensure-DataFile -FileName "fiat_vehicle_specs.csv"
Ensure-DataFile -FileName "obd2_parameter_reference.csv"
Ensure-DataFile -FileName "diagnostic_procedures.txt"

# ── 5. Drop client work order ─────────────────────────────────────────────
Write-Host "[5/7] Creating client inspection request..."
$workOrderFile = "C:\Users\Docker\Desktop\CLIENT_REQUEST_Ducato_Prepurchase.txt"

Set-Content -Path $workOrderFile -Encoding UTF8 -Value @"
=============================================================
  INDEPENDENT VEHICLE INSPECTION SERVICES LTD
  PRE-PURCHASE ELECTRONIC INSPECTION REQUEST
=============================================================
Inspection Ref: IVIS-2024-5501
Date: $(Get-Date -Format "dd/MM/yyyy")
Inspector: (Your Name / Certification Number)
Client: NextDay Couriers Ltd (accounts@nextday-couriers.co.uk)

VEHICLE UNDER INSPECTION
-------------------------
Make/Model  : Fiat Ducato 2.3 Multijet II 130HP L3H2
Year        : 2016
Engine      : 2287cc Diesel (F1AE3481D - 130HP / 96kW)
Fuel        : Diesel (Euro 6)
Transmission: 6-speed Manual
GVWR        : 3,500 kg
Body        : Long Wheelbase High Roof Panel Van
Mileage     : 187,420 miles (per dashboard - VERIFY)
Registration: YN16 GTR
VIN         : ZFA25000002187430
Colour      : Pearl White

CLIENT'S INTENDED USE
----------------------
Fleet vehicle for a courier delivery business.
Expected annual mileage: 55,000 - 65,000 miles per year.
The van will carry parcels up to 1,000kg daily.
Client requires reliable operation with no unexpected breakdowns.

SELLER'S CLAIMS (from ad listing)
----------------------------------
- "Full service history" (dealer stamps in book)
- "Only 2 previous owners - both fleet users"
- "New DPF fitted 2 years ago"
- "MOT until March 2025 - no advisories"
- "New Michelin tyres front and rear"
- Asking Price: £14,995

CONCERNS FLAGGED BY CLIENT
---------------------------
Client test drove the vehicle and noted:
1. "Slight roughness at idle when cold"
2. "Gearbox feels notchy going into 3rd"
3. "Dashboard showed an amber warning light briefly on startup
   but it went off after a few seconds"

INSPECTION REQUIRED
-------------------
Full 5-system electronic diagnostic inspection:

SYSTEM 1 - ENGINE ECU (F1AE3481D)
  - ECU identification (part number, SW/HW versions)
  - All stored + pending DTCs with DTC database descriptions
  - Key parameters: coolant temp, fuel pressure, injection qty,
    EGR position, DPF soot level (if readable), boost pressure
  - Classify each DTC: CRITICAL / MAJOR / MINOR / CLEARED

SYSTEM 2 - TRANSMISSION / GEARBOX
  - ECU identification
  - All stored + pending DTCs
  - Any gear selector, clutch, or synchroniser fault codes
  - Classify faults

SYSTEM 3 - ABS / BRAKING SYSTEM
  - ECU identification
  - All DTCs (wheel speed sensors, ABS pump, EBD, ESP)
  - Classify faults

SYSTEM 4 - BODY COMPUTER (BSI/BCM)
  - ECU identification
  - All DTCs (CAN faults, lighting, locks, immobiliser)
  - Classify faults

SYSTEM 5 - AIRBAG / SRS SYSTEM
  - ECU identification
  - All DTCs - ANY airbag fault = CRITICAL classification
  - Check for deployed airbag history (VIN/chassis codes)
  - Classify faults

CERTIFICATE FORMAT REQUIRED
------------------------------
File: C:\Users\Docker\Desktop\MultiecuscanTasks\prepurchase_certificate.txt

MUST INCLUDE:
  1. Cover page (vehicle details, inspection date, inspector)
  2. Section for each of the 5 systems (ECU info + DTCs + classification)
  3. Overall Risk Score: 0-100 (0=excellent, 100=do not buy)
  4. Final Verdict:
     - RECOMMENDED (Risk < 30, no critical faults)
     - CONDITIONAL RECOMMENDED (Risk 30-60, fixable issues)
     - NOT RECOMMENDED (Risk > 60, or any critical safety faults)
  5. Justification paragraph explaining verdict

REFERENCE DATA (C:\Users\Docker\Desktop\MultiecuscanData\)
-----------------------------------------------------------
- dtc_database_full.csv       : DTC descriptions (3,000+ codes)
- obd2_parameter_reference.csv: Normal parameter ranges
- fiat_vehicle_specs.csv      : Ducato technical specifications
- diagnostic_procedures.txt   : Diagnostic workflow guide

LEGAL NOTE: This inspection report will be provided to the client
as part of a commercial transaction. Accuracy is essential.
Inspector assumes professional liability for this certificate.
=============================================================
"@

Write-Host "Client request created at: $workOrderFile"

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

Write-Host "=== comprehensive_prepurchase_audit task setup complete ==="
Write-Host "Client request on Desktop: CLIENT_REQUEST_Ducato_Prepurchase.txt"
