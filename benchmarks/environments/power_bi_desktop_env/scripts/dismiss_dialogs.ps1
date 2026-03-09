# dismiss_dialogs.ps1 - Dismiss Power BI Desktop Home screen, first-run dialogs, and popups.
# Must run in the interactive desktop session (via schtasks /IT).
#
# Power BI Desktop startup flow:
#   Phase 1 - Home screen (always shows on launch):
#     - "Join us at FabCon Atlanta" banner — X at ~(1247, 64)
#     - "Blank report" card at ~(328, 243) → click to enter report canvas
#   Phase 2 - Report canvas dialogs (may appear on first launch from checkpoint):
#     1. "Dark mode is here" customization dialog — X at ~(884, 225)
#     2. "Two ways to use sample data" tutorial dialog — X at ~(930, 147)
#     3. "Live Edit semantic models in Direct Lake mode" green banner — X at ~(640, 32)
#   Phase 3 - Cleanup:
#     - OneDrive popup (on fresh Windows VMs)
#     - Click safe canvas area to ensure focus

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

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
    [Win32Mouse]::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 200
    [Win32Mouse]::mouse_event([Win32Mouse]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    [Win32Mouse]::mouse_event([Win32Mouse]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}

function Focus-PowerBI {
    $pbi = Get-Process PBIDesktop -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pbi -and $pbi.MainWindowHandle -ne [IntPtr]::Zero) {
        [Win32Mouse]::SetForegroundWindow($pbi.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 500
    }
}

# ========== PHASE 1: Handle Home Screen ==========
# Give Power BI time to fully render the Home screen
Start-Sleep -Seconds 3

# Dismiss OneDrive popup (if present)
Click-At -X 1166 -Y 627
Start-Sleep -Milliseconds 500
Click-At -X 1236 -Y 393
Start-Sleep -Seconds 1

# Close "FabCon Atlanta" promotional banner (X at top-right of banner)
# On canvas view, this hits harmless ribbon area
Focus-PowerBI
Click-At -X 1247 -Y 64
Start-Sleep -Seconds 1

# Click "Blank report" card to enter report canvas
# On canvas view, this clicks empty canvas area (harmless)
Focus-PowerBI
Click-At -X 328 -Y 243
Start-Sleep -Seconds 5

# ========== PHASE 2: Handle Report Canvas Dialogs ==========
# These may or may not appear (first launch from checkpoint only)

# Try Escape first — can dismiss the front-most modal dialog
Focus-PowerBI
[System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
Start-Sleep -Seconds 2

# Close "Dark mode is here" dialog X button
Focus-PowerBI
Click-At -X 884 -Y 225
Start-Sleep -Seconds 2

# Try Escape again for any dialog that appeared behind
Focus-PowerBI
[System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
Start-Sleep -Seconds 2

# Close "Two ways to use sample data" dialog X button
Focus-PowerBI
Click-At -X 930 -Y 147
Start-Sleep -Seconds 2

# Close green "Live Edit semantic models" banner X
Focus-PowerBI
Click-At -X 640 -Y 32
Start-Sleep -Seconds 2

# ========== PHASE 3: Cleanup ==========

# Escape to dismiss anything accidentally triggered
Focus-PowerBI
[System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
Start-Sleep -Seconds 1
Focus-PowerBI
[System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
Start-Sleep -Seconds 1

# Click safe empty canvas area (well below import buttons at y~400)
# IMPORTANT: (500, 400) hits "Import data from SQL Server" — use (535, 550) instead
Focus-PowerBI
Click-At -X 535 -Y 550
Start-Sleep -Milliseconds 500

# Final Escape for safety
Focus-PowerBI
[System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
Start-Sleep -Milliseconds 500
