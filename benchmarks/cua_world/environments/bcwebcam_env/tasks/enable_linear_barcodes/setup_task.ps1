# Setup script for enable_linear_barcodes task
# Ensures bcWebCam is running with its main window visible

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Setting up enable_linear_barcodes task ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# 1. Start a schtasks-based Edge killer in the interactive session
#    (runs in Session 1 like Edge, more reliable than Start-Job in Session 0)
$edgeKiller = Start-EdgeKillerTask

# 2. Kill existing bcWebCam and browsers
Close-Browsers
Get-Process bcWebCam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# 3. Launch bcWebCam in interactive session
Launch-BcWebCamInteractive -WaitSeconds 10

# 4. Kill Edge one more time before dialog dismissal
Close-Browsers
Start-Sleep -Seconds 3

# 5. Dismiss the "No WebCam" error dialog
Dismiss-BcWebCamDialogs -Retries 3 -InitialWaitSeconds 3

# 6. Ensure bcWebCam is in the foreground (minimize console, bring bcWebCam to front)
Ensure-BcWebCamReady -MaxAttempts 5

# 7. Stop the Edge killer task
Stop-EdgeKillerTask -KillerInfo $edgeKiller

Write-Host "=== enable_linear_barcodes task setup complete ==="
