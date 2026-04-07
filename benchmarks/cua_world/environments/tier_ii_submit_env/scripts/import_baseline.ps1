# import_baseline.ps1 - Imports a .t2s baseline file into Tier2 Submit via GUI automation.
# This script must run in the interactive desktop session (via schtasks /IT).
#
# Import flow in Tier2 Submit 2025 Rev 1:
#   1. Click "Import" button in top menu bar
#   2. Import page opens with "Browse to file" and file type options
#   3. Click "Browse to file" button
#   4. Open File dialog appears - type the file path and press Enter
#   5. File path appears in the text field
#   6. Click "Continue" button
#   7. Import runs; summary dialog shows results
#   8. Click "Close" or press Escape to dismiss summary
#
# Coordinates are in 1280x720 screen resolution.

param(
    [string]$BaselineFile = "C:\Users\Docker\Desktop\Tier2Tasks\green_valley_baseline.t2s"
)

$ErrorActionPreference = "Continue"

# Load Win32 mouse functions
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32Import {
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

Add-Type -AssemblyName System.Windows.Forms

function Click-At {
    param([int]$X, [int]$Y)
    [Win32Import]::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 200
    [Win32Import]::mouse_event([Win32Import]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    [Win32Import]::mouse_event([Win32Import]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 500
}

function Get-ForegroundTitle {
    $hwnd = [Win32Import]::GetForegroundWindow()
    $sb = New-Object System.Text.StringBuilder 256
    [Win32Import]::GetWindowText($hwnd, $sb, 256) | Out-Null
    return $sb.ToString()
}

# Ensure Tier2 Submit is in foreground
$t2sProc = Get-Process | Where-Object {
    $_.ProcessName -match "(?i)tier2|t2s|t2submit" -and $_.MainWindowTitle -ne ""
} | Select-Object -First 1

if (-not $t2sProc) {
    Write-Host "ERROR: Tier2 Submit not found. Cannot import."
    exit 1
}

[Win32Import]::SetForegroundWindow($t2sProc.MainWindowHandle) | Out-Null
Start-Sleep -Seconds 1

$title = Get-ForegroundTitle
Write-Host "Foreground: $title"
Write-Host "Importing baseline: $BaselineFile"

# --- Step 1: Click Import button in top menu bar ---
# Import is at approximately x=991, y=55 in 1280x720
Write-Host "Step 1: Clicking Import..."
Click-At -X 991 -Y 55
Start-Sleep -Seconds 2

# --- Step 2: The Import page opens ---
# It shows options: "Browse to file" button and file type dropdown.
# "Browse to file" button is on the left side of the import page.
# Click "Browse to file" button - approximately at (260, 180)
Write-Host "Step 2: Clicking 'Browse to file'..."
Click-At -X 260 -Y 180
Start-Sleep -Seconds 2

# --- Step 3: Open File dialog should appear ---
# Type the file path into the filename field at the bottom of the dialog.
# The filename field is usually auto-focused in Open File dialogs.
# Clear any existing text first, then type the path.
Write-Host "Step 3: Typing file path..."
[System.Windows.Forms.SendKeys]::SendWait("^a")
Start-Sleep -Milliseconds 200
[System.Windows.Forms.SendKeys]::SendWait("{DELETE}")
Start-Sleep -Milliseconds 200

# Type the file path - SendKeys needs special escaping for backslashes
$escapedPath = $BaselineFile -replace '\\', '\\'
# Use clipboard for reliable path entry (SendKeys has issues with special chars)
[System.Windows.Forms.Clipboard]::SetText($BaselineFile)
Start-Sleep -Milliseconds 200
[System.Windows.Forms.SendKeys]::SendWait("^v")
Start-Sleep -Milliseconds 500

# Press Enter to confirm the file selection (equivalent to clicking Open)
Write-Host "Step 3b: Pressing Enter to select file..."
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 3

# --- Step 4: File is selected, now click Continue ---
# The Continue button should be visible on the import page.
# After file selection, "Continue" appears at approximately (640, 600) or similar.
# Try clicking Continue - it's typically a prominent button.
Write-Host "Step 4: Clicking Continue..."
Click-At -X 640 -Y 600
Start-Sleep -Seconds 1
# Also try pressing Enter as Continue may be the default button
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 5

# --- Step 5: Import summary shows ---
# The summary dialog shows counts (facilities, contacts, chemicals).
# Dismiss it by pressing Escape or Enter.
Write-Host "Step 5: Dismissing import summary..."
$title = Get-ForegroundTitle
Write-Host "After import, foreground: $title"

# Try multiple dismissal methods
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 1
[System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
Start-Sleep -Seconds 1

# Click in a neutral area to dismiss any remaining dialogs
Click-At -X 640 -Y 400
Start-Sleep -Seconds 1

Write-Host "Import automation complete."

# Verify: check the foreground window title
$finalTitle = Get-ForegroundTitle
Write-Host "Final foreground window: $finalTitle"
