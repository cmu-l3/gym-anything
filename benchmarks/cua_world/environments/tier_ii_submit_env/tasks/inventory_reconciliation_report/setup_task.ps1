[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up inventory_reconciliation_report task ==="

. C:\workspace\scripts\task_utils.ps1

Stop-Tier2Submit

Remove-Item "C:\Users\Docker\Desktop\Tier2Output\reconciled_submission.t2s" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\Desktop\inventory_reconciliation_report_result.json" -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop\Tier2Output" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop\Tier2Tasks" | Out-Null

Copy-Item "C:\workspace\data\green_valley_baseline.t2s" -Destination "C:\Users\Docker\Desktop\Tier2Tasks\green_valley_baseline.t2s" -Force
Copy-Item "C:\workspace\data\chemical_reference.csv" -Destination "C:\Users\Docker\Desktop\Tier2Tasks\chemical_reference.csv" -Force -ErrorAction SilentlyContinue

$startTime = Record-TaskStart -TaskName "inventory_reconciliation_report"

# Drop the reconciliation memo on the Desktop
$memoContent = @"
GREEN VALLEY WATER FACILITY
Operations Department - Year-End Inventory Reconciliation Memo

Date: January 15, 2025
From: Patricia Nguyen, Operations Manager
To: Environmental Compliance Department
RE: 2025 Tier II Chemical Inventory Reconciliation

This memo summarizes the reconciled chemical inventory data for the 2025
reporting year based on quarterly delivery logs, usage records, and physical
inventory counts conducted December 2024.

CHEMICAL INVENTORY UPDATES:

1. CHLORINE (CAS 7782-50-5)
   The new bulk storage tank (commissioned Q2 2024) has significantly
   increased our storage capacity.
   - Revised Maximum Amount On-Site: 35,000 lbs (Range Code 07)
   - Revised Average Daily Amount: 22,000 lbs (Range Code 07)
   - Days On-Site: 365 (unchanged)
   - NEW STORAGE LOCATION: A second storage location has been added:
     Description: Outdoor emergency reserve - Cylinder bank
     Storage Type: Cylinder
     Pressure: Greater than ambient pressure
     Temperature: Ambient temperature
     Amount: 5,000 lbs
   NOTE: The existing Chlorination building storage remains unchanged.

2. FLUOROSILIC ACID (CAS 16961-83-4)
   Following the Q3 process optimization, we have reduced our fluoride
   chemical requirements.
   - Revised Maximum Amount On-Site: 30,000 lbs (Range Code 07)
   - Revised Average Daily Amount: 18,000 lbs (Range Code 06)
   - Days On-Site: 365 (unchanged)
   - Storage: No changes to storage locations.

FACILITY UPDATES:
   - Maximum occupants has increased from 18 to 25 following the addition
     of the new process control room and laboratory expansion.

CERTIFICATION:
   - Certifier: James Okafor, Environmental Compliance Manager
   - Date Signed: February 1, 2025

Please update the Tier II submission accordingly before the March 1 deadline.

Patricia Nguyen
Operations Manager
Green Valley Water Facility
Tel: 802-555-1234
"@

Set-Content -Path "C:\Users\Docker\Desktop\Inventory_Reconciliation_Memo_2025.txt" -Value $memoContent -Encoding UTF8
Write-Host "Reconciliation memo placed on Desktop."

# Launch Tier2 Submit
$t2sExe = Find-Tier2SubmitExe
Launch-Tier2SubmitInteractive -Tier2SubmitExe $t2sExe -WaitSeconds 20

$dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
if (Test-Path $dismissScript) {
    schtasks /Create /TN "DismissT2S_InvRecon" /TR "powershell -ExecutionPolicy Bypass -File $dismissScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN "DismissT2S_InvRecon" 2>$null
    Start-Sleep -Seconds 15
    schtasks /Delete /TN "DismissT2S_InvRecon" /F 2>$null
}

Write-Host "=== inventory_reconciliation_report setup complete ==="
