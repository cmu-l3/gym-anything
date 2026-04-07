Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Setting up regional_compliance_remediation task ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# 1. Start Edge killer background task
$edgeKiller = Start-EdgeKillerTask

# 2. Suppress OneDrive popup
Suppress-OneDrive

# 3. Close browsers and existing CAMEO instances
Close-Browsers
$ErrorActionPreference = "Continue"
Get-Process | Where-Object {
    $_.ProcessName -like "*CAMEO*" -or $_.ProcessName -like "*cameo*" -or $_.ProcessName -like "*DataManager*"
} | Stop-Process -Force -ErrorAction SilentlyContinue
$ErrorActionPreference = "Stop"
Start-Sleep -Seconds 2

# 4. Verify source files exist
if (-not (Test-Path "C:\workspace\data\greenfield_operations.xml")) {
    throw "ERROR: Source data file not found: C:\workspace\data\greenfield_operations.xml"
}
if (-not (Test-Path "C:\workspace\data\riverside_treatment.xml")) {
    throw "ERROR: Source data file not found: C:\workspace\data\riverside_treatment.xml"
}
if (-not (Test-Path "C:\workspace\data\compliance_order.txt")) {
    throw "ERROR: Compliance order not found: C:\workspace\data\compliance_order.txt"
}
Write-Host "Source files verified."

# 5. Ensure output directory exists
if (-not (Test-Path "C:\Users\Docker\Documents\CAMEO")) {
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents\CAMEO" | Out-Null
}

# 6. Delete stale outputs BEFORE recording timestamp
$stale_export = "C:\Users\Docker\Documents\CAMEO\regional_compliance_2025.xml"
if (Test-Path $stale_export) {
    Remove-Item $stale_export -Force -ErrorAction SilentlyContinue
    Write-Host "Removed stale export: $stale_export"
}
$stale_result = "C:\Windows\Temp\regional_compliance_result.json"
if (Test-Path $stale_result) {
    Remove-Item $stale_result -Force -ErrorAction SilentlyContinue
    Write-Host "Removed stale result JSON: $stale_result"
}

# 7. Record task start timestamp
$timestamp = (Get-Date).ToString("o")
$timestamp | Out-File "C:\Windows\Temp\regional_compliance_start.txt" -Encoding utf8
Write-Host "Task start timestamp recorded: $timestamp"

# 8. Launch CAMEO in interactive session
Launch-CAMEOInteractive -WaitSeconds 15

# 9. Kill Edge again after CAMEO starts
Close-Browsers
Start-Sleep -Seconds 2

# 10. Dismiss any initial dialogs
Dismiss-CAMEODialogs -Retries 3

# 11. Ensure CAMEO is ready
Ensure-CAMEOReady -MaxAttempts 5

# 12. Stop Edge killer
Stop-EdgeKillerTask -KillerInfo $edgeKiller

Write-Host "=== regional_compliance_remediation setup complete ==="
Write-Host "CAMEO is ready."
Write-Host "Data files: C:\workspace\data\greenfield_operations.xml"
Write-Host "            C:\workspace\data\riverside_treatment.xml"
Write-Host "Compliance order: C:\workspace\data\compliance_order.txt"
