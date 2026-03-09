# dismiss_dialogs.ps1 - Dismiss Copper POS startup dialogs.
# Called during warm-up (post_start) and before each task (pre_task).
# Uses PyAutoGUI TCP server (port 5555) for all GUI automation.
#
# Known Copper POS dialogs:
# 1. Quick Start Wizard (first run only - handled in setup_copper.ps1)
# 2. "Click here to start" tooltip (harmless, auto-dismisses on click)
# 3. Registration/Upgrade prompts (Escape dismisses)
# 4. NCH bundled software offers (Escape dismisses)
#
# Strategy: Press Escape to close popups, click neutral area to dismiss tooltips.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Dismissing Copper POS dialogs ==="

# Load PyAutoGUI helpers
$utils = "C:\workspace\scripts\task_utils.ps1"
if (Test-Path $utils) {
    . $utils
}

# Verify PyAutoGUI server is reachable
$pingResult = Send-PyAutoGUI -Command @{action="ping"}
if (-not $pingResult) {
    Write-Host "WARNING: PyAutoGUI server not responding on port 5555."
}

# Give the app time to render dialogs
Start-Sleep -Seconds 3

# Phase 1: Click neutral area to dismiss tooltips and ensure focus
# The main POS area below toolbar is safe
PyAutoGUI-Click -X 640 -Y 350
Start-Sleep -Seconds 1

# Phase 2: Press Escape to dismiss any NCH popup/offer dialogs
for ($i = 0; $i -lt 3; $i++) {
    PyAutoGUI-Press -Key "escape"
    Start-Sleep -Seconds 1
}

# Phase 3: Press Enter to accept any OK/Continue buttons
Start-Sleep -Seconds 1
PyAutoGUI-Press -Key "enter"
Start-Sleep -Seconds 1

# Phase 4: Final Escape round for any remaining popups
for ($i = 0; $i -lt 2; $i++) {
    PyAutoGUI-Press -Key "escape"
    Start-Sleep -Seconds 1
}

# Phase 5: Click neutral area again to ensure main app is focused
PyAutoGUI-Click -X 640 -Y 350
Start-Sleep -Seconds 1

Write-Host "=== Dialog dismissal complete ==="
