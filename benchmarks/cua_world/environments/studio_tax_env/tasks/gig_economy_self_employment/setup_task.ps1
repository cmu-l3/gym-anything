# setup_task.ps1 — pre_task hook for gig_economy_self_employment
# Sets up StudioTax with clean state for Dimitri Papadopoulos gig economy scenario

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up gig_economy_self_employment task ==="

# 1. Kill any existing StudioTax instances
$ErrorActionPreference = "Continue"
Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$ErrorActionPreference = "Stop"

# 2. Remove any pre-existing output files to enforce wrong-target rejection
$targetFile = "C:\Users\Docker\Documents\StudioTax\dimitri_papadopoulos.24t"
if (Test-Path $targetFile) {
    Remove-Item $targetFile -Force
}

# Also remove any stale result JSON from prior runs
$resultPath = "C:\Users\Docker\Desktop\gig_economy_result.json"
if (Test-Path $resultPath) {
    Remove-Item $resultPath -Force
}

# 3. Create scenario documents folder and copy tax documents
$scenarioDir = "C:\Users\Docker\Desktop\TaxDocuments\papadopoulos"
New-Item -ItemType Directory -Force -Path $scenarioDir | Out-Null
Copy-Item "C:\workspace\data\scenario_papadopoulos.txt" -Destination "$scenarioDir\" -Force

# Create a desktop shortcut hint file so agent can locate documents
Set-Content -Path "C:\Users\Docker\Desktop\READ_ME_FIRST.txt" -Value "Tax documents for Dimitri Papadopoulos are in: C:\Users\Docker\Desktop\TaxDocuments\papadopoulos\"

# 4. Ensure StudioTax output directory exists
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents\StudioTax" | Out-Null

# 5. Record start timestamp for verifier
$epoch = [int][double]::Parse((Get-Date -UFormat %s))
Set-Content -Path "C:\Users\Docker\task_start_timestamp_gig_economy.txt" -Value "$epoch"

# 6. Record baseline state (do-nothing check — target file must NOT exist at start)
$baselineInfo = @{
    target_exists_at_start = (Test-Path $targetFile)
    timestamp = $epoch
    task_id = "gig_economy_self_employment"
}
$baselineInfo | ConvertTo-Json | Set-Content -Path "C:\Users\Docker\task_baseline_gig_economy.txt"

# 7. Launch StudioTax in interactive session
. "C:\workspace\scripts\task_utils.ps1"
$studioTaxExe = Find-StudioTaxExe
if (-not $studioTaxExe) {
    Write-Host "ERROR: StudioTax executable not found"
    exit 1
}

Launch-StudioTaxInteractive -StudioTaxExe $studioTaxExe -WaitSeconds 15

# 8. Dismiss startup dialogs
$taskName = "DismissDialogs_GE"
$ErrorActionPreference = "Continue"
schtasks /Create /TN $taskName /TR "powershell -ExecutionPolicy Bypass -File C:\workspace\scripts\dismiss_dialogs.ps1" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
schtasks /Run /TN $taskName 2>$null
Start-Sleep -Seconds 15
schtasks /Delete /TN $taskName /F 2>$null
$ErrorActionPreference = "Stop"

# 9. Verify StudioTax is running
$proc = Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc) {
    Write-Host "StudioTax running (PID: $($proc.Id))"
} else {
    Write-Host "WARNING: StudioTax process not detected"
}

Write-Host "=== Task setup complete: Dimitri Papadopoulos gig economy return ==="
Write-Host "=== Documents at: C:\Users\Docker\Desktop\TaxDocuments\papadopoulos\ ==="
