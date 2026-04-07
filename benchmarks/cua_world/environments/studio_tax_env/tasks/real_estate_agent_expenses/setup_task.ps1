# setup_task.ps1 — pre_task hook for real_estate_agent_expenses
# Sets up StudioTax with clean state for Rodrigo Espinoza real estate agent scenario

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up real_estate_agent_expenses task ==="

# 1. Kill any existing StudioTax instances
$ErrorActionPreference = "Continue"
Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$ErrorActionPreference = "Stop"

# 2. Remove any pre-existing output files
$targetFile = "C:\Users\Docker\Documents\StudioTax\rodrigo_espinoza.24t"
if (Test-Path $targetFile) {
    Remove-Item $targetFile -Force
}

$resultPath = "C:\Users\Docker\Desktop\realestate_result.json"
if (Test-Path $resultPath) {
    Remove-Item $resultPath -Force
}

# 3. Create scenario documents folder and copy tax documents
$scenarioDir = "C:\Users\Docker\Desktop\TaxDocuments\espinoza"
New-Item -ItemType Directory -Force -Path $scenarioDir | Out-Null
Copy-Item "C:\workspace\data\scenario_espinoza_realestate.txt" -Destination "$scenarioDir\" -Force

Set-Content -Path "C:\Users\Docker\Desktop\READ_ME_FIRST.txt" -Value "Tax documents for Rodrigo Espinoza are in: C:\Users\Docker\Desktop\TaxDocuments\espinoza\"

# 4. Ensure StudioTax output directory exists
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents\StudioTax" | Out-Null

# 5. Record start timestamp
$epoch = [int][double]::Parse((Get-Date -UFormat %s))
Set-Content -Path "C:\Users\Docker\task_start_timestamp_realestate.txt" -Value "$epoch"

$baselineInfo = @{
    target_exists_at_start = (Test-Path $targetFile)
    timestamp = $epoch
    task_id = "real_estate_agent_expenses"
}
$baselineInfo | ConvertTo-Json | Set-Content -Path "C:\Users\Docker\task_baseline_realestate.txt"

# 6. Launch StudioTax in interactive session
. "C:\workspace\scripts\task_utils.ps1"
$studioTaxExe = Find-StudioTaxExe
if (-not $studioTaxExe) {
    Write-Host "ERROR: StudioTax executable not found"
    exit 1
}

Launch-StudioTaxInteractive -StudioTaxExe $studioTaxExe -WaitSeconds 15

# 7. Dismiss startup dialogs
$taskName = "DismissDialogs_RE"
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

Write-Host "=== Task setup complete: Rodrigo Espinoza real estate agent return ==="
Write-Host "=== Documents at: C:\Users\Docker\Desktop\TaxDocuments\espinoza\ ==="
