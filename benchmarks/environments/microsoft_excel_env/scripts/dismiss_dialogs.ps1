# dismiss_dialogs.ps1 - Dismiss Excel trial nag and OneDrive popup
# Must run in the interactive desktop session (via schtasks /IT)
#
# After the warm-up launch in post_start, subsequent launches show a
# "Create and edit ends soon" trial nag with an X close button (not the
# mandatory sign-in dialog). This script dismisses that and any other popups.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# All coordinates in this script are authored in the "CUA" 1280x720 space
# (matching ask_cua / typical VLM grounding). Scale to the VM's actual screen
# resolution before sending Win32 mouse events.
$refWidth = 1280
$refHeight = 720
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$actualWidth = [int]$bounds.Width
$actualHeight = [int]$bounds.Height

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32Mouse {
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
}
"@

function Click-At {
    param([int]$X, [int]$Y)
    $sx = [int]([Math]::Round($X * $actualWidth / $refWidth))
    $sy = [int]([Math]::Round($Y * $actualHeight / $refHeight))
    [Win32Mouse]::SetCursorPos($sx, $sy)
    Start-Sleep -Milliseconds 150
    [Win32Mouse]::mouse_event([Win32Mouse]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 50
    [Win32Mouse]::mouse_event([Win32Mouse]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 200
}

function Focus-Excel {
    $excel = Get-Process EXCEL -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($excel -and $excel.MainWindowHandle -ne [IntPtr]::Zero) {
        [Win32Mouse]::SetForegroundWindow($excel.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 300
    }
}

Start-Sleep -Seconds 1

# --- Step 1: Dismiss OneDrive popup ---
Click-At -X 1166 -Y 627
Start-Sleep -Milliseconds 500
Click-At -X 1236 -Y 393
Start-Sleep -Seconds 1

# --- Step 2: Dismiss "Create and edit ends soon" trial nag ---
# X close button at approximately (1042, 72)
Focus-Excel
Click-At -X 1042 -Y 72
Start-Sleep -Seconds 2

# --- Step 2b: Dismiss "Sign in to get started with Excel" overlay ---
# This dialog can block the worksheet on fresh launches. Dismiss it using the
# dialog's top-right X (preferred) and/or the "Close" button (NOT "Close Excel").
Focus-Excel
Click-At -X 1040 -Y 75
Start-Sleep -Milliseconds 500
Click-At -X 234 -Y 624
Start-Sleep -Seconds 1

# --- Step 3: Send Escape keys for any remaining dialogs ---
Focus-Excel
[System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
Start-Sleep -Seconds 2

Focus-Excel
[System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
Start-Sleep -Seconds 1

Focus-Excel
[System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
Start-Sleep -Seconds 1

# --- Step 4: Ensure spreadsheet has focus ---
Focus-Excel
Click-At -X 150 -Y 300
Start-Sleep -Milliseconds 500
