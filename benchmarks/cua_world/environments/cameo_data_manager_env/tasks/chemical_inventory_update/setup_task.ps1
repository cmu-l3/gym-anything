Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Setting up chemical_inventory_update task ==="

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

# 4. Verify source data file exists
if (-not (Test-Path "C:\workspace\data\epcra_tier2_data.xml")) {
    throw "ERROR: Source data file not found: C:\workspace\data\epcra_tier2_data.xml"
}
Write-Host "Source data file verified."

# 5. Copy data file to CAMEO documents directory
Copy-TierIIData

# 6. Ensure output directory exists
if (-not (Test-Path "C:\Users\Docker\Documents\CAMEO")) {
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents\CAMEO" | Out-Null
}

# 7. Record task start timestamp (BEFORE importing, so agent must make changes after this time)
$timestamp = (Get-Date).ToString("o")
$timestamp | Out-File "C:\Windows\Temp\chemical_inventory_update_start.txt" -Encoding utf8
Write-Host "Task start timestamp recorded: $timestamp"

# 8. Launch CAMEO in interactive session
Launch-CAMEOInteractive -WaitSeconds 15

# 9. Kill Edge again after CAMEO starts
Close-Browsers
Start-Sleep -Seconds 2

# 10. Dismiss any initial dialogs
Dismiss-CAMEODialogs -Retries 3

# 11. Import the base Tier II data (Green Valley Water Facility)
Import-TierIIData -XmlPath "C:\Users\Docker\Documents\CAMEO\epcra_tier2_data.xml"

# 12. Ensure CAMEO is ready
Ensure-CAMEOReady -MaxAttempts 5

# 13. Stop Edge killer
Stop-EdgeKillerTask -KillerInfo $edgeKiller

Write-Host "=== chemical_inventory_update setup complete ==="
Write-Host "CAMEO has Green Valley Water Facility loaded and ready for updates."
