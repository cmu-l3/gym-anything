# setup_task.ps1 — pre_task hook for claim_rrsp_and_tips
# Ensures StudioTax is running with a clean state for Terry Lee scenario

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up claim_rrsp_and_tips task ==="

# 1. Kill any existing StudioTax instances
$ErrorActionPreference = "Continue"
Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$ErrorActionPreference = "Stop"

# 2. Remove any pre-existing output files
$targetFile = "C:\Users\Docker\Documents\StudioTax\terry_lee.24t"
if (Test-Path $targetFile) {
    Remove-Item $targetFile -Force
}

# 3. Ensure scenario file is on Desktop
$scenarioDir = "C:\Users\Docker\Desktop\TaxScenarios"
New-Item -ItemType Directory -Force -Path $scenarioDir | Out-Null
if (-not (Test-Path "$scenarioDir\scenario_terry_lee.txt")) {
    Copy-Item "C:\workspace\data\scenario_terry_lee.txt" -Destination "$scenarioDir\" -Force
}

New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents\StudioTax" | Out-Null

# 4. Record start timestamp
$epoch = [int][double]::Parse((Get-Date -UFormat %s))
Set-Content -Path "C:\Users\Docker\task_start_timestamp_rrsp_tips.txt" -Value "$epoch"

# 5. Record baseline state
$baselineInfo = @{
    target_exists_at_start = (Test-Path $targetFile)
    timestamp = $epoch
}
$baselineInfo | ConvertTo-Json | Set-Content -Path "C:\Users\Docker\task_baseline_rrsp_tips.txt"

# 6. Source shared utilities and launch StudioTax
. "C:\workspace\scripts\task_utils.ps1"
$studioTaxExe = Find-StudioTaxExe
if (-not $studioTaxExe) {
    Write-Host "ERROR: StudioTax executable not found"
    exit 1
}

Launch-StudioTaxInteractive -StudioTaxExe $studioTaxExe -WaitSeconds 15

# 7. Dismiss startup dialogs
$taskName = "DismissDialogs_RRT"
$ErrorActionPreference = "Continue"
schtasks /Create /TN $taskName /TR "powershell -ExecutionPolicy Bypass -File C:\workspace\scripts\dismiss_dialogs.ps1" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
schtasks /Run /TN $taskName 2>$null
Start-Sleep -Seconds 15
schtasks /Delete /TN $taskName /F 2>$null
$ErrorActionPreference = "Stop"

# 8. Verify StudioTax is running
$proc = Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc) {
    Write-Host "StudioTax running (PID: $($proc.Id))"
} else {
    Write-Host "WARNING: StudioTax process not detected"
}

Write-Host "=== Task setup complete ==="
