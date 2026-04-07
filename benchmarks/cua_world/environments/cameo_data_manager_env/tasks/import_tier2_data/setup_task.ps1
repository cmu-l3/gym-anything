Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Setting up import_tier2_data task ==="

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

# 3. Ensure Tier II data file is in place
Copy-TierIIData

# 4. Launch CAMEO in interactive session
Launch-CAMEOInteractive -WaitSeconds 15

# 5. Kill Edge again
Close-Browsers
Start-Sleep -Seconds 2

# 6. Dismiss any dialogs
Dismiss-CAMEODialogs -Retries 3

# 7. Ensure CAMEO is ready
Ensure-CAMEOReady -MaxAttempts 5

# 8. Stop Edge killer
Stop-EdgeKillerTask -KillerInfo $edgeKiller

Write-Host "=== import_tier2_data task setup complete ==="
