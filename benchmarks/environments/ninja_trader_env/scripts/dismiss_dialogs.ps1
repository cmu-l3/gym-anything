# dismiss_dialogs.ps1 - Dismiss NinjaTrader 8 startup dialogs and popups.
#
# This script runs from SSH (Session 0) and uses the PyAutoGUI TCP server
# (port 5555) running in the interactive desktop session to send clicks and
# key presses. The Win32 API approach (used in Power BI env) does NOT work
# for NinjaTrader — clicks are not registered by NinjaTrader windows.
#
# NinjaTrader 8.1.x Enterprise Evaluation startup dialog sequence:
#   First launch:
#     1. "Get Connected" / "Connect to Live Data" dialog — click Skip
#     2. "Warning" about windows outside viewable range — click Yes
#     3. "Getting Started" tips panel — click X to close
#     4. SuperDOM / extra windows may open
#   Subsequent launches (from checkpoint):
#     1. "Warning" about windows outside viewable range — click Yes
#     2. "Getting Started" tips panel — click X to close
#     3. SuperDOM / extra windows may open
#
# Coordinates verified via interactive testing at 1280x720 resolution.

$ErrorActionPreference = "Continue"

# Load shared helpers (PyAutoGUI-Click, PyAutoGUI-Press, etc.)
$utils = "C:\workspace\scripts\task_utils.ps1"
if (Test-Path $utils) {
    . $utils
} else {
    Write-Host "ERROR: task_utils.ps1 not found at $utils"
    exit 1
}

Write-Host "=== Dismissing NinjaTrader startup dialogs ==="

# Verify PyAutoGUI server is reachable
$pingResult = Send-PyAutoGUI -Command @{action="ping"}
if (-not $pingResult -or -not $pingResult.success) {
    Write-Host "WARNING: PyAutoGUI server not responding on port 5555. Dialog dismissal may fail."
}

# ========== PHASE 1: "Get Connected" dialog (first launch only) ==========
# This dialog asks to connect to a live data feed.
# The "Skip" button is at the bottom of the dialog.
# On subsequent launches (from checkpoint) this dialog may not appear.
Write-Host "Phase 1: Attempting 'Get Connected' dismiss (may not be present)..."
Start-Sleep -Seconds 2

# Click "Skip" button (only effective if dialog is present)
PyAutoGUI-Click -X 749 -Y 463
Start-Sleep -Seconds 1

# Backup: press Escape
PyAutoGUI-Press -Key "escape"
Start-Sleep -Seconds 1

# ========== PHASE 2: "Warning" dialog ==========
# "NinjaTrader has detected there are windows outside the viewable range,
# reposition these to the primary monitor?"
# Click "Yes" to dismiss.
Write-Host "Phase 2: Dismissing 'Warning' dialog..."
PyAutoGUI-Click -X 677 -Y 372
Start-Sleep -Seconds 1

# Backup: press Enter (Yes is typically focused/default)
PyAutoGUI-Press -Key "enter"
Start-Sleep -Seconds 1

# ========== PHASE 3: "Getting Started" tips panel ==========
# A floating tips panel appears (e.g. "Tip 3 of 7").
# Click the red X button to close it.
# Position varies: ~(618, 167) on relaunch, ~(489, 37) when overlapping.
Write-Host "Phase 3: Closing 'Getting Started' tips..."

# Try the most common position first (relaunch position)
PyAutoGUI-Click -X 618 -Y 167
Start-Sleep -Seconds 1

# Also try the alternative position (in case panel is at a different spot)
PyAutoGUI-Click -X 489 -Y 37
Start-Sleep -Milliseconds 500

# ========== PHASE 4: Close extra windows ==========
# Close "Data Series" dialog, SuperDOM, or other default workspace windows.
Write-Host "Phase 4: Closing extra windows..."

# Press Escape to close any modal dialog (Data Series, etc.)
PyAutoGUI-Press -Key "escape"
Start-Sleep -Seconds 1

# Press Escape again for stacked modals
PyAutoGUI-Press -Key "escape"
Start-Sleep -Seconds 1

# Note: SuperDOM may be visible but we don't attempt to close it via
# fixed coordinates since that risks accidentally closing the PyAutoGUI
# server terminal. The workspace will be saved without the SuperDOM after
# the warm-up cycle.

# ========== PHASE 5: Final cleanup ==========
Write-Host "Phase 5: Final cleanup..."

# Click on the Control Center area to ensure focus
PyAutoGUI-Click -X 400 -Y 400
Start-Sleep -Milliseconds 500

# One more Escape for safety
PyAutoGUI-Press -Key "escape"
Start-Sleep -Milliseconds 500

Write-Host "=== Dialog dismissal complete ==="
