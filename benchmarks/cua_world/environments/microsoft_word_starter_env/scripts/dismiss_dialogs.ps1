# Dismiss Word 2010 startup dialogs using PyAutoGUI TCP server.
#
# Word 2010 (from Office 2010 Pro Plus ISO) may show:
# - First-run welcome/tips
# - Office update notifications
# - Activation reminder (suppressed via registry in setup script)
#
# This script uses the PyAutoGUI TCP server (port 5555) running in the
# interactive desktop session. Coordinates are for 1280x720 resolution.

$ErrorActionPreference = "Continue"

# Load shared helpers
$utils = "C:\workspace\scripts\task_utils.ps1"
if (Test-Path $utils) {
    . $utils
} else {
    Write-Host "ERROR: task_utils.ps1 not found at $utils"
    exit 1
}

Write-Host "=== Dismissing Word 2010 dialogs ==="

# Verify PyAutoGUI server is reachable
$pingOk = $false
try {
    $pingResult = Invoke-PyAutoGUICommand -Command @{action = "screenshot"}
    if ($pingResult -and $pingResult.success) {
        $pingOk = $true
        Write-Host "PyAutoGUI server is responding."
    }
} catch {
    Write-Host "WARNING: PyAutoGUI server not responding: $($_.Exception.Message)"
}

if (-not $pingOk) {
    Write-Host "PyAutoGUI server not available. Attempting Escape keys only..."
}

# Phase 1: Multiple Escape keys to close any modal dialogs
Write-Host "Phase 1: Sending Escape keys..."
for ($i = 0; $i -lt 3; $i++) {
    try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }
    Start-Sleep -Milliseconds 500
}

# Phase 2: Click on document area to ensure focus
Write-Host "Phase 2: Clicking document area for focus..."
try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 640; y = 400} | Out-Null } catch { }
Start-Sleep -Milliseconds 500

# Phase 3: More Escape keys for any remaining modals
Write-Host "Phase 3: Final Escape keys..."
for ($i = 0; $i -lt 2; $i++) {
    try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }
    Start-Sleep -Milliseconds 500
}

# Phase 4: Click safe area to ensure Word document has focus
try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 400; y = 350} | Out-Null } catch { }
Start-Sleep -Milliseconds 300

Write-Host "=== Dialog dismissal complete ==="
