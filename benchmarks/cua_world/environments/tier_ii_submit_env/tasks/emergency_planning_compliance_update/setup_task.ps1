[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

Write-Host "=== Setting up emergency_planning_compliance_update task ==="

. C:\workspace\scripts\task_utils.ps1

Stop-Tier2Submit

Remove-Item "C:\Users\Docker\Desktop\Tier2Output\compliance_updated.t2s" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\Desktop\emergency_planning_compliance_update_result.json" -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop\Tier2Output" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop\Tier2Tasks" | Out-Null

Copy-Item "C:\workspace\data\green_valley_baseline.t2s" -Destination "C:\Users\Docker\Desktop\Tier2Tasks\green_valley_baseline.t2s" -Force
Copy-Item "C:\workspace\data\chemical_reference.csv" -Destination "C:\Users\Docker\Desktop\Tier2Tasks\chemical_reference.csv" -Force -ErrorAction SilentlyContinue

$startTime = Record-TaskStart -TaskName "emergency_planning_compliance_update"

# Baseline state for anti-gaming:
# subjectToEmergencyPlanning = false (WRONG - Chlorine 20000 lbs >> TPQ 100 lbs)
# certifier = "Debra Monaco, President" with dateSigned 2020-01-13 (outdated)
# maxNumOccupants = 18 (needs to be 22)

# Launch Tier2 Submit
$t2sExe = Find-Tier2SubmitExe
Launch-Tier2SubmitInteractive -Tier2SubmitExe $t2sExe -WaitSeconds 20

$dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
if (Test-Path $dismissScript) {
    schtasks /Create /TN "DismissT2S_EmPlan" /TR "powershell -ExecutionPolicy Bypass -File $dismissScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN "DismissT2S_EmPlan" 2>$null
    Start-Sleep -Seconds 15
    schtasks /Delete /TN "DismissT2S_EmPlan" /F 2>$null
}

Write-Host "=== emergency_planning_compliance_update setup complete ==="
