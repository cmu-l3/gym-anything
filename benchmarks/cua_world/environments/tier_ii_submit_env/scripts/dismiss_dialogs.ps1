# dismiss_dialogs.ps1 - Dismisses Tier2 Submit startup dialogs and first-run prompts.
# This script runs in the interactive desktop session via schtasks.
#
# Tier2 Submit 2025 Rev 1 startup sequence:
#   1. Welcome splash screen with "Start Tier2 Submit" button at (640, 495) @1280x720
#   2. Quick Guide popup - dismissed via Escape key or clicking X button
#   3. Main interface ready (Facilities / Contacts / Chemical Inventory tabs)

$ErrorActionPreference = "Continue"

# Wait for Tier2 Submit window to appear
$maxWait = 45
$elapsed = 0
$appFound = $false
while ($elapsed -lt $maxWait) {
    $t2sProcs = Get-Process | Where-Object {
        $_.ProcessName -match "(?i)tier2|t2s|t2submit"
    }
    if ($t2sProcs | Where-Object { $_.MainWindowTitle -ne "" }) {
        $appFound = $true
        Write-Host "Tier2 Submit window detected."
        break
    }
    Start-Sleep -Seconds 2
    $elapsed += 2
}

if (-not $appFound) {
    Write-Host "WARNING: Tier2 Submit window not detected after ${maxWait}s."
    exit 0
}

# Wait for the welcome splash to fully render
Start-Sleep -Seconds 5

# Load Win32 mouse functions for dialog dismissal
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32Mouse {
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

function Click-At {
    param([int]$X, [int]$Y)
    [Win32Mouse]::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 200
    [Win32Mouse]::mouse_event([Win32Mouse]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    [Win32Mouse]::mouse_event([Win32Mouse]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 500
}

function Get-ForegroundWindowTitle {
    $hwnd = [Win32Mouse]::GetForegroundWindow()
    $sb = New-Object System.Text.StringBuilder 256
    [Win32Mouse]::GetWindowText($hwnd, $sb, 256) | Out-Null
    return $sb.ToString()
}

# Bring Tier2 Submit to foreground
$t2sProc = Get-Process | Where-Object {
    $_.ProcessName -match "(?i)tier2|t2s|t2submit" -and $_.MainWindowTitle -ne ""
} | Select-Object -First 1

if ($t2sProc) {
    [Win32Mouse]::SetForegroundWindow($t2sProc.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 500
}

$title = Get-ForegroundWindowTitle
Write-Host "Foreground window: $title"

Add-Type -AssemblyName System.Windows.Forms

# --- Step 1: Dismiss Welcome Splash ---
# The welcome screen shows "Start Tier2 Submit" button at center-bottom (640, 495) @1280x720.
Write-Host "Clicking 'Start Tier2 Submit' button..."
Click-At -X 640 -Y 495
Start-Sleep -Seconds 3

# --- Step 2: Dismiss Quick Guide ---
# After clicking Start, a Quick Guide popup appears. Escape closes it.
Write-Host "Dismissing Quick Guide with Escape..."
[System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
Start-Sleep -Seconds 1

# Extra Escape presses for any remaining dialogs
for ($i = 0; $i -lt 3; $i++) {
    [System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
    Start-Sleep -Milliseconds 500
}

# Press Enter to dismiss any "OK" confirmation dialogs
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Milliseconds 500

$title = Get-ForegroundWindowTitle
Write-Host "After dismissal, foreground window: $title"
Write-Host "Dialog dismissal complete."
