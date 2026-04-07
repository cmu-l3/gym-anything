[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up regulatory_notification_chemical_entry task ==="

. C:\workspace\scripts\task_utils.ps1

Stop-Tier2Submit

# Clean output files
Remove-Item "C:\Users\Docker\Desktop\Tier2Output\new_chemicals_added.t2s" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\Desktop\regulatory_notification_chemical_entry_result.json" -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop\Tier2Output" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop\Tier2Tasks" | Out-Null

# Copy baseline
Copy-Item "C:\workspace\data\green_valley_baseline.t2s" -Destination "C:\Users\Docker\Desktop\Tier2Tasks\green_valley_baseline.t2s" -Force
Copy-Item "C:\workspace\data\chemical_reference.csv" -Destination "C:\Users\Docker\Desktop\Tier2Tasks\chemical_reference.csv" -Force -ErrorAction SilentlyContinue

# Record timestamp
$startTime = Record-TaskStart -TaskName "regulatory_notification_chemical_entry"

# Drop the regulatory notification document on the Desktop
# This is the specification document the agent must find and read.
# Uses real chemical data from EPA/NOAA reference sources.
$notificationContent = @"
VERMONT DEPARTMENT OF ENVIRONMENTAL CONSERVATION
Waste Management & Prevention Division
1 National Life Drive, Davis 1
Montpelier, VT 05620-3704

                    EPCRA TIER II CHEMICAL INVENTORY UPDATE NOTIFICATION

Date: January 8, 2025
Facility: Green Valley Water Facility
          123 First Avenue, Colchester, VT 05408
LEPC: LEPC 4 - Chittenden County

RE: New Chemical Inventory Reporting Requirements - Infrastructure Upgrade

Dear Facility Manager,

Following the facility's recent infrastructure upgrade, this notification confirms
the addition of two (2) new hazardous chemicals to on-site operations. Both
chemicals must be added to the facility's Tier II submission for the 2025
reporting year per EPCRA Section 312 requirements.

CHEMICAL 1: AMMONIA (ANHYDROUS)
  CAS Number: 7664-41-7
  Extremely Hazardous Substance (EHS): Yes (TPQ: 500 lbs)
  Type: Pure chemical
  Physical State: Gas
  GHS Hazard Classifications:
    - Acute toxicity (any route of exposure)
    - Skin corrosion or irritation
    - Serious eye damage or eye irritation
    - Gas under pressure (compressed gas)
  Maximum Amount On-Site: 8,000 lbs (Range Code 05)
  Average Daily Amount: 5,000 lbs (Range Code 04)
  Number of Days On-Site: 365
  Storage Location:
    Description: Refrigeration building - Pressurized vessel
    Storage Type: Tank inside building
    Pressure Conditions: Greater than ambient pressure
    Temperature Conditions: Less than ambient temperature but not cryogenic
    Amount at Location: 8,000 lbs
  Use: Refrigeration system for water treatment cold storage

CHEMICAL 2: PROPANE
  CAS Number: 74-98-6
  Extremely Hazardous Substance (EHS): No
  Type: Pure chemical
  Physical State: Gas
  GHS Hazard Classifications:
    - Flammable (gases, aerosols, liquids, or solids)
    - Gas under pressure (compressed gas)
  Maximum Amount On-Site: 15,000 lbs (Range Code 06)
  Average Daily Amount: 10,000 lbs (Range Code 05)
  Number of Days On-Site: 365
  Storage Location:
    Description: Outdoor tank farm - Bulk propane tank
    Storage Type: Above ground tank
    Pressure Conditions: Greater than ambient pressure
    Temperature Conditions: Ambient temperature
    Amount at Location: 15,000 lbs
  Use: Backup heating system and emergency generator fuel

Please update the facility's Tier II submission accordingly and submit the
revised file to this office by the annual reporting deadline.

For questions, contact the EPCRA Compliance Unit at (802) 828-1138.

Sincerely,
Environmental Compliance Division
Vermont DEC
"@

Set-Content -Path "C:\Users\Docker\Desktop\Chemical_Inventory_Update_Notification.txt" -Value $notificationContent -Encoding UTF8
Write-Host "Regulatory notification placed on Desktop."

# Launch Tier2 Submit
$t2sExe = Find-Tier2SubmitExe
Launch-Tier2SubmitInteractive -Tier2SubmitExe $t2sExe -WaitSeconds 20

# Dismiss dialogs
$dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
if (Test-Path $dismissScript) {
    schtasks /Create /TN "DismissT2S_RegNotif" /TR "powershell -ExecutionPolicy Bypass -File $dismissScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN "DismissT2S_RegNotif" 2>$null
    Start-Sleep -Seconds 15
    schtasks /Delete /TN "DismissT2S_RegNotif" /F 2>$null
}

Write-Host "=== regulatory_notification_chemical_entry setup complete ==="
