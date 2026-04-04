# dismiss_dialogs.ps1 - Dismiss first-run dialogs for Vital Recorder
# This script runs in the interactive desktop session (via schtasks /IT)
# It handles any first-run dialogs, update prompts, or device configuration warnings

$ErrorActionPreference = "Continue"

Write-Host "=== Dismissing Vital Recorder dialogs ==="

# Load Win32 mouse helpers
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32Click {
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
}
"@

function Click-Position {
    param([int]$X, [int]$Y)
    [Win32Click]::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 200
    [Win32Click]::mouse_event([Win32Click]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    [Win32Click]::mouse_event([Win32Click]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}

# Wait for Vital Recorder to fully load
Start-Sleep -Seconds 5

# Phase 1: Press Escape to dismiss any modal dialog
Write-Host "Phase 1: Pressing Escape to dismiss modal dialogs..."
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
Start-Sleep -Seconds 1

# Phase 2: Press Escape again for stacked dialogs
Write-Host "Phase 2: Second Escape for stacked dialogs..."
[System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
Start-Sleep -Seconds 1

# Phase 3: Press Enter to dismiss any OK/confirmation dialogs
Write-Host "Phase 3: Enter for confirmation dialogs..."
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 1

# Phase 4: Press Escape once more for any remaining popups
Write-Host "Phase 4: Final Escape..."
[System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
Start-Sleep -Seconds 1

Write-Host "=== Dialog dismissal complete ==="
