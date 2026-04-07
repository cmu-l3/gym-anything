Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Setting up generate_responder_summary task ==="

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

# 4. Ensure output directory and data file exist
Copy-TierIIData

# 5. Launch CAMEO in interactive session
Launch-CAMEOInteractive -WaitSeconds 15

# 6. Kill Edge again
Close-Browsers
Start-Sleep -Seconds 2

# 7. Dismiss any dialogs
Dismiss-CAMEODialogs -Retries 3

# 8. Import Tier II data so facility is available for report generation
Import-TierIIData

# 9. Ensure CAMEO is ready
Ensure-CAMEOReady -MaxAttempts 5

# 10. Stop Edge killer
Stop-EdgeKillerTask -KillerInfo $edgeKiller

Write-Host "=== generate_responder_summary task setup complete ==="
