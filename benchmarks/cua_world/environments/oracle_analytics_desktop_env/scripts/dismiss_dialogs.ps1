# Dismiss Oracle Analytics Desktop first-run dialogs, OneDrive popups, and other system notifications.
# Uses Win32 API for GUI automation from Session 0.
# All coordinates are at 1280x720 resolution (QEMU virtio-vga).

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

# Wait a moment for dialogs to render
Start-Sleep -Seconds 3

# --- Phase 1: Dismiss OneDrive "Turn On Windows Backup" dialog ---
Write-Host "Phase 1: Dismissing OneDrive backup dialog..."
# Try common locations for "No thanks" or X close buttons
Click-At -X 1166 -Y 627
Start-Sleep -Seconds 1
Click-At -X 1237 -Y 393
Start-Sleep -Seconds 1

# --- Phase 2: Dismiss any OAD first-run welcome dialog ---
# Oracle Analytics Desktop may show a "Getting Started" or "What's New" dialog
Write-Host "Phase 2: Dismissing OAD first-run dialogs..."
# Try pressing Escape to close modal dialogs
Send-Keys "{ESCAPE}"
Start-Sleep -Seconds 2
Send-Keys "{ESCAPE}"
Start-Sleep -Seconds 1

# --- Phase 3: Dismiss any license/EULA dialogs ---
Write-Host "Phase 3: Handling license dialogs..."
# If there's an Accept button, try Enter key
Send-Keys "{ENTER}"
Start-Sleep -Seconds 2

# --- Phase 4: Close any notification toasts ---
Write-Host "Phase 4: Closing notifications..."
# Click away from any notification area
Click-At -X 640 -Y 360
Start-Sleep -Seconds 1

# --- Phase 5: Bring OAD to foreground ---
Write-Host "Phase 5: Bringing OAD to foreground..."
$focused = Focus-OADWindow
if ($focused) {
    Write-Host "OAD window focused successfully"
} else {
    Write-Host "WARNING: Could not find OAD window to focus"
    # Try Alt+Tab as fallback
    Send-Keys "%{TAB}"
    Start-Sleep -Seconds 1
}

# --- Phase 6: Final Escape pass for any remaining modals ---
Write-Host "Phase 6: Final Escape pass..."
Send-Keys "{ESCAPE}"
Start-Sleep -Seconds 1
Send-Keys "{ESCAPE}"
Start-Sleep -Seconds 1

Write-Host "=== Dialog dismissal complete ==="
