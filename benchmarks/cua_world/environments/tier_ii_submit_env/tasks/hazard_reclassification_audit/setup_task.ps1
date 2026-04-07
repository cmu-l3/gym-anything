[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up hazard_reclassification_audit task ==="

. C:\workspace\scripts\task_utils.ps1

# Stop any running Tier2 Submit
Stop-Tier2Submit

# Clean output files FIRST
$targetFile = "C:\Users\Docker\Desktop\Tier2Output\corrected_hazards.t2s"
Remove-Item $targetFile -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\Desktop\hazard_reclassification_audit_result.json" -Force -ErrorAction SilentlyContinue

# Ensure directories
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop\Tier2Output" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop\Tier2Tasks" | Out-Null

# Copy baseline data
$baselineFile = "C:\Users\Docker\Desktop\Tier2Tasks\green_valley_baseline.t2s"
Copy-Item "C:\workspace\data\green_valley_baseline.t2s" -Destination $baselineFile -Force

# Copy chemical reference
Copy-Item "C:\workspace\data\chemical_reference.csv" -Destination "C:\Users\Docker\Desktop\Tier2Tasks\chemical_reference.csv" -Force -ErrorAction SilentlyContinue

# Record start timestamp AFTER cleanup
$startTime = Record-TaskStart -TaskName "hazard_reclassification_audit"

# Record baseline state for anti-gaming: the baseline has incomplete hazards
# Chlorine (7782-50-5): only Oxidizer=true, Serious eye damage=true
#   Missing: Acute toxicity, Gas under pressure, Skin corrosion
# Fluorosilic Acid (16961-83-4): only Hazard Not Otherwise Classified=true
#   Missing: Acute toxicity, Skin corrosion, Serious eye damage
Set-Content -Path "C:\Users\Docker\task_baseline_hazard_audit.txt" -Value @"
baseline_chlorine_hazards=Oxidizer;Serious_eye_damage
baseline_fluorosilic_hazards=Hazard_Not_Otherwise_Classified
target_file_exists_at_start=false
"@

# Launch Tier2 Submit
$t2sExe = Find-Tier2SubmitExe
Write-Host "Launching Tier2 Submit: $t2sExe"
Launch-Tier2SubmitInteractive -Tier2SubmitExe $t2sExe -WaitSeconds 20

# Dismiss startup dialogs
$dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
if (Test-Path $dismissScript) {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN "DismissT2S_HazAudit" /TR "powershell -ExecutionPolicy Bypass -File $dismissScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN "DismissT2S_HazAudit" 2>$null
    Start-Sleep -Seconds 15
    schtasks /Delete /TN "DismissT2S_HazAudit" /F 2>$null
    $ErrorActionPreference = $prevEAP
}

Write-Host "=== hazard_reclassification_audit setup complete ==="
Write-Host "Agent must: Import baseline, audit hazard classifications, correct them, export"
