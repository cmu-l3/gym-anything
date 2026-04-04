# dismiss_dialogs.ps1 - Dismiss Multiecuscan startup dialogs and OS notifications
# This script runs in the interactive desktop session via schtasks.
# It writes C:\Temp\dismiss_complete.txt when done so the caller can synchronize.
#
# KEY INSIGHT: The Multiecuscan "Disclaimer" is NOT a separate top-level window.
# It is an embedded panel INSIDE the main MES window (title "Multiecuscan 5.4").
# FindWindow("Disclaimer") won't find it. We must focus the MES window and
# click the Close button or use keyboard shortcuts to dismiss it.

$ErrorActionPreference = "Continue"

Remove-Item "C:\Temp\dismiss_complete.txt" -Force -ErrorAction SilentlyContinue

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32MES {
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    public const uint MOUSEEVENTF_LEFTDOWN = 0x02;
    public const uint MOUSEEVENTF_LEFTUP   = 0x04;

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left, Top, Right, Bottom;
    }

    public static void Click(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(100);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(50);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
    }
}
"@

function Send-KeyPress {
    param([string]$Key)
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    [System.Windows.Forms.SendKeys]::SendWait($Key)
    Start-Sleep -Milliseconds 200
}

function Hide-AllTerminals {
    Get-Process | Where-Object {
        ($_.ProcessName -match "cmd|powershell|WindowsTerminal|conhost") -and
        $_.MainWindowHandle -ne [IntPtr]::Zero
    } | ForEach-Object {
        [Win32MES]::ShowWindow($_.MainWindowHandle, 0) | Out-Null  # SW_HIDE
    }
}

function Kill-OneDrive {
    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "OneDriveSetup" -Force -ErrorAction SilentlyContinue
}

# ── Phase 0: Kill OneDrive, hide terminals, dismiss OneDrive popup ─────────
Kill-OneDrive
Start-Sleep -Milliseconds 500
[Win32MES]::Click(1166, 626)
Start-Sleep -Milliseconds 200
[Win32MES]::Click(1237, 392)
Start-Sleep -Milliseconds 200
Hide-AllTerminals

# ── Phase 1: Wait for Multiecuscan window with handle ──────────────────────
$maxWait = 45
$waited = 0
$mesHwnd = [IntPtr]::Zero
while ($waited -lt $maxWait) {
    $mesProc = Get-Process | Where-Object {
        $_.ProcessName -match "Multiecuscan" -and $_.MainWindowHandle -ne [IntPtr]::Zero
    }
    if ($mesProc) {
        $mesHwnd = $mesProc[0].MainWindowHandle
        break
    }
    Start-Sleep -Seconds 1
    $waited++
}
if ($mesHwnd -eq [IntPtr]::Zero) {
    "FAIL: no MES window after ${maxWait}s" | Out-File "C:\Temp\dismiss_complete.txt"
    exit 0
}

# ── Phase 2: Maximize MES and dismiss the Disclaimer embedded panel ────────
# First maximize the MES window to ensure consistent positioning
[Win32MES]::ShowWindow($mesHwnd, 3) | Out-Null  # SW_MAXIMIZE
[Win32MES]::SetForegroundWindow($mesHwnd) | Out-Null
Start-Sleep -Seconds 3

# The Disclaimer panel is embedded INSIDE the MES window. It is centered in the
# window with a "Close" button near the bottom-right of the panel.
#
# In a maximized 1280x720 window:
#   Panel is ~430px wide × ~410px tall, centered
#   Close button is at approximately (810, 524) in screen coordinates
#
# We try multiple strategies to dismiss it:

for ($attempt = 1; $attempt -le 10; $attempt++) {
    # Re-focus MES window each attempt
    [Win32MES]::SetForegroundWindow($mesHwnd) | Out-Null
    Start-Sleep -Milliseconds 300

    # Get current MES window rect
    $rect = New-Object Win32MES+RECT
    [Win32MES]::GetWindowRect($mesHwnd, [ref]$rect) | Out-Null
    $winW = $rect.Right - $rect.Left
    $winH = $rect.Bottom - $rect.Top
    $centerX = $rect.Left + [int]($winW / 2)
    $centerY = $rect.Top + [int]($winH / 2)

    # The Disclaimer panel is ~430×410 and centered in the client area.
    # Close button is at approximately (panel_right - 40, panel_bottom - 15).
    # Panel right ≈ centerX + 215, panel bottom ≈ centerY + 195 (from window center)
    $closeBtnX = $centerX + 175  # ~630 + 175 = ~805 for maximized
    $closeBtnY = $centerY + 175  # ~360 + 175 = ~535 for maximized

    # Strategy 1: Click the Close button
    [Win32MES]::Click($closeBtnX, $closeBtnY)
    Start-Sleep -Milliseconds 500

    # Strategy 2: Click slightly different positions (the button is ~70×20px)
    [Win32MES]::Click($closeBtnX - 20, $closeBtnY - 5)
    Start-Sleep -Milliseconds 300
    [Win32MES]::Click($closeBtnX + 10, $closeBtnY + 5)
    Start-Sleep -Milliseconds 300

    # Strategy 3: Click the X button on the Disclaimer panel title bar
    # X is at approximately (panel_right - 10, panel_top + 10)
    $panelXBtnX = $centerX + 210
    $panelXBtnY = $centerY - 195
    [Win32MES]::Click($panelXBtnX, $panelXBtnY)
    Start-Sleep -Milliseconds 300

    # Strategy 4: Keyboard - ESCAPE should dismiss the panel
    [Win32MES]::SetForegroundWindow($mesHwnd) | Out-Null
    Start-Sleep -Milliseconds 200
    Send-KeyPress "{ESCAPE}"
    Start-Sleep -Milliseconds 300

    # Strategy 5: Tab to Close button and press Enter/Space
    # The Close button might not have initial focus, so TAB to it
    Send-KeyPress "{TAB}"
    Send-KeyPress "{TAB}"
    Send-KeyPress "{TAB}"
    Send-KeyPress " "  # Space activates focused button
    Start-Sleep -Milliseconds 300
    Send-KeyPress "{ENTER}"
    Start-Sleep -Milliseconds 300

    Start-Sleep -Seconds 2

    # Check if the panel was dismissed by looking at the window title
    # After dismissal, the main UI should be visible (title stays "Multiecuscan 5.4")
    # We can't easily check if the panel is gone from Session 1, so just try multiple times
}

# ── Phase 3: Wait for any loading to complete ──────────────────────────────
Start-Sleep -Seconds 5

# Extra ESCAPE presses to dismiss any remaining popups
for ($i = 0; $i -lt 5; $i++) {
    [Win32MES]::SetForegroundWindow($mesHwnd) | Out-Null
    Start-Sleep -Milliseconds 100
    Send-KeyPress "{ESCAPE}"
    Start-Sleep -Milliseconds 500
}

# ── Phase 4: Final cleanup ─────────────────────────────────────────────────
Kill-OneDrive
Start-Sleep -Milliseconds 200
[Win32MES]::Click(1166, 626)
Start-Sleep -Milliseconds 200
[Win32MES]::Click(1237, 392)
Start-Sleep -Milliseconds 200

# Focus and maximize MES
$mesProc = Get-Process | Where-Object {
    $_.ProcessName -match "Multiecuscan" -and $_.MainWindowHandle -ne [IntPtr]::Zero
}
if ($mesProc) {
    $main = $mesProc | Select-Object -First 1
    [Win32MES]::SetForegroundWindow($main.MainWindowHandle) | Out-Null
    [Win32MES]::ShowWindow($main.MainWindowHandle, 3) | Out-Null  # SW_MAXIMIZE
}

# Hide all terminals
Hide-AllTerminals

# ── Write completion marker ────────────────────────────────────────────────
"DONE" | Out-File "C:\Temp\dismiss_complete.txt"
