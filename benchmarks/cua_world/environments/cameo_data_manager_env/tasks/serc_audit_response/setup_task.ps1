Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Setting up serc_audit_response task ==="

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
if (-not (Test-Path "C:\workspace\data\lakeside_chemical.xml")) {
    throw "ERROR: Source data file not found: C:\workspace\data\lakeside_chemical.xml"
}
if (-not (Test-Path "C:\workspace\data\serc_audit_report.txt")) {
    throw "ERROR: Audit report not found: C:\workspace\data\serc_audit_report.txt"
}
Write-Host "Source files verified."

# 5. Ensure output directory exists
if (-not (Test-Path "C:\Users\Docker\Documents\CAMEO")) {
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents\CAMEO" | Out-Null
}

# 6. Record task start timestamp
$timestamp = (Get-Date).ToString("o")
$timestamp | Out-File "C:\Windows\Temp\serc_audit_response_start.txt" -Encoding utf8
Write-Host "Task start timestamp recorded: $timestamp"

# 7. Launch CAMEO in interactive session
Launch-CAMEOInteractive -WaitSeconds 15

# 8. Kill Edge again after CAMEO starts
Close-Browsers
Start-Sleep -Seconds 2

# 9. Dismiss any initial dialogs
Dismiss-CAMEODialogs -Retries 3

# 10. Ensure CAMEO is ready
Ensure-CAMEOReady -MaxAttempts 5

# 11. Stop Edge killer
Stop-EdgeKillerTask -KillerInfo $edgeKiller

Write-Host "=== serc_audit_response setup complete ==="
Write-Host "CAMEO is ready. Data file: C:\workspace\data\lakeside_chemical.xml"
Write-Host "Audit report: C:\workspace\data\serc_audit_report.txt"
