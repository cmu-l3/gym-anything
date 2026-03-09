# Dismiss Blue Sky Plan dialogs after launch.
# Uses PyAutoGUI TCP server for GUI automation from Session 0.
#
# Dialog types and how they're handled:
# - Hardware warning ("Your hardware doesn't meet..."): Click "Don't show again" + OK
#   * Checkbox at (398, 355), OK at (835, 355)
#   * When no dialog, clicks hit hex grid — but Back button click reverts
# - Crash report dialog (after force-kill): Click X button at (957, 71)
#   * When no crash dialog, (957,71) hits empty toolbar area — harmless
# - Login popup ("Please login"): Click X button at (814, 255)
#   * ONLY clicked when Edge was detected (indicates login flow is active)
#   * When no popup, hits hex grid area — avoided by gating on Edge detection
# - Edge browser (opened by login flow): Kill process
# - Update notification: Escape closes it
#
# IMPORTANT: Escape does NOT close crash dialog, login popup, or project type view.
# Must use specific click coordinates for crash/login, and Back button for project type.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Load shared utilities
$utils = "C:\workspace\scripts\task_utils.ps1"
if (Test-Path $utils) {
    . $utils
} else {
    Write-Host "WARNING: task_utils.ps1 not found"
    return
}

Write-Host "=== Dismissing dialogs ==="

# --- Phase 0: Dismiss hardware warning (if present) ---
# The hardware warning dialog appears when Mesa software rendering isn't active.
# "Don't show again" checkbox at (398, 355), OK button at (835, 355).
# When no dialog is present, these clicks hit the hex grid area.
Write-Host "Phase 0: Hardware warning (if present)..."
PyAutoGUI-Click -X 398 -Y 355
Start-Sleep -Milliseconds 500
PyAutoGUI-Click -X 835 -Y 355
Start-Sleep -Seconds 3

# --- Phase 1: Kill Edge browser first ---
# Edge may be open from BSP's login flow. Kill it so clicks go to BSP.
Write-Host "Phase 1: Killing Edge browser..."
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$edgeProcs = Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue
$edgeFound = ($null -ne $edgeProcs -and @($edgeProcs).Count -gt 0)
if ($edgeFound) {
    $edgeProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "  Edge killed"
}
$ErrorActionPreference = $prevEAP
Start-Sleep -Seconds 3

# --- Phase 2: Close crash report dialog (if present) ---
# The crash dialog X button is at (957, 71).
# When no crash dialog is present, (957, 71) hits empty toolbar space (between
# "Help" and "Credits: 0") — completely harmless.
# Closing the crash dialog triggers BSP to continue loading and open Edge login page.
Write-Host "Phase 2: Closing crash report dialog..."
PyAutoGUI-Click -X 957 -Y 71
Start-Sleep -Seconds 5

# --- Phase 3: Kill Edge (opened by crash dialog close or login flow) ---
Write-Host "Phase 3: Killing Edge..."
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$edgeProcs = Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue
$edgeWasRunning = ($null -ne $edgeProcs -and @($edgeProcs).Count -gt 0)
if ($edgeWasRunning) {
    $edgeProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "  Edge killed"
}
$ErrorActionPreference = $prevEAP
Start-Sleep -Seconds 2

# --- Phase 4: Close login popup (ONLY if Edge was detected) ---
# The login popup X button is at (814, 255).
# IMPORTANT: Only click this if we detected Edge, meaning login flow was active.
# If no login flow, (814, 255) hits hex grid and opens project type view.
if ($edgeFound -or $edgeWasRunning) {
    Write-Host "Phase 4: Closing login popup (Edge was detected)..."
    PyAutoGUI-Click -X 814 -Y 255
    Start-Sleep -Seconds 2

    # Kill Edge again (login popup close may open Edge)
    Write-Host "Phase 5: Killing Edge..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP
    Start-Sleep -Seconds 1
} else {
    Write-Host "Phase 4: Skipped (no Edge detected, no login popup expected)"
}

# --- Phase 5: Clean up any accidentally opened views ---
# If Phase 0 clicks hit hex grid (no hardware warning), a project type may be open.
# Click Back button at (322, 104) which is harmless on START NEW PROJECT screen
# but navigates back if a project type view was opened.
Write-Host "Phase 5: Back button cleanup..."
PyAutoGUI-Click -X 322 -Y 104
Start-Sleep -Seconds 1

# --- Phase 6: Escape for any remaining dialogs ---
# Handles: update notification, etc.
Write-Host "Phase 6: Final Escape..."
PyAutoGUI-Press -Key "escape"
Start-Sleep -Seconds 1
PyAutoGUI-Press -Key "escape"
Start-Sleep -Seconds 1

# --- Phase 7: Wait and catch late-opening Edge ---
# BSP's login flow may open Edge AFTER earlier phases complete.
# Wait 5s, then check if Edge appeared and handle it.
Write-Host "Phase 7: Late Edge cleanup..."
Start-Sleep -Seconds 5
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$lateEdge = Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue
$ErrorActionPreference = $prevEAP

if ($null -ne $lateEdge -and @($lateEdge).Count -gt 0) {
    Write-Host "  Late Edge detected, cleaning up..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $lateEdge | Stop-Process -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP
    Start-Sleep -Seconds 2
    # Close login popup
    PyAutoGUI-Click -X 814 -Y 255
    Start-Sleep -Seconds 1
    # Kill Edge one more time
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Get-Process -Name "msedge", "msedgewebview2" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP
    Start-Sleep -Seconds 1
    # Click Back in case login popup X hit hex grid
    PyAutoGUI-Click -X 322 -Y 104
    Start-Sleep -Seconds 1
} else {
    Write-Host "  No late Edge detected"
}

# Final escape for any remaining overlay
PyAutoGUI-Press -Key "escape"
Start-Sleep -Seconds 1

Write-Host "=== Dialog dismissal complete ==="
