# task_utils.ps1 - shared utilities for all Garmin BaseCamp tasks
# Source this in each setup_task.ps1 with:
#   . "C:\workspace\scripts\task_utils.ps1"

$TOOL_DIR       = "C:\GarminTools"
$BACKUP_DIR     = "$TOOL_DIR\BaseCampBackup"
$PYAUTOGUI_PORT = 5555

# Win32 API for window management
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(int flags, int dx, int dy, int data, int info);
}
"@ -ErrorAction SilentlyContinue


# --- Find BaseCamp EXE ---
function Find-BaseCampExe {
    $cached = "$TOOL_DIR\basecamp_path.txt"
    if (Test-Path $cached) {
        $path = (Get-Content $cached -ErrorAction SilentlyContinue).Trim()
        if ($path -and (Test-Path $path)) { return $path }
    }
    $candidates = @(
        "C:\Program Files (x86)\Garmin\BaseCamp\BaseCamp.exe",
        "C:\Program Files\Garmin\BaseCamp\BaseCamp.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $c | Set-Content $cached
            return $c
        }
    }
    $found = Get-ChildItem "C:\Program Files*" -Recurse -Filter "BaseCamp.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        $found.FullName | Set-Content $cached
        return $found.FullName
    }
    return $null
}


# --- Kill BaseCamp ---
function Close-BaseCamp {
    Stop-Process -Name "BaseCamp" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}


# --- Kill browsers ---
function Close-Browsers {
    @("msedge","chrome","firefox") | ForEach-Object {
        Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1
}


# --- Send command to PyAutoGUI server (framework's server at port 5555) ---
function Invoke-PyAutoGUI {
    param([hashtable]$Command)
    $json  = $Command | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    try {
        $tcp    = New-Object System.Net.Sockets.TcpClient("127.0.0.1", $PYAUTOGUI_PORT)
        $stream = $tcp.GetStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        $buf  = New-Object byte[] 4096
        $read = $stream.Read($buf, 0, $buf.Length)
        $tcp.Close()
        return [System.Text.Encoding]::UTF8.GetString($buf, 0, $read) | ConvertFrom-Json
    } catch {
        Write-Host "PyAutoGUI send error: $_"
        return $null
    }
}


# --- Launch BaseCamp in interactive session via schtasks /IT ---
# Launches BaseCamp and dismisses the startup Task Launcher by clicking "Plan a Trip"
# NOTE: The Task Launcher in BaseCamp IS the main window - closing it closes BaseCamp.
# The correct way to dismiss it is to click "Plan a Trip" (not ESC/Close button).
function Launch-BaseCampInteractive {
    param([int]$WaitSeconds = 80)

    $bcExe = Find-BaseCampExe
    if (-not $bcExe) {
        Write-Host "ERROR: BaseCamp.exe not found!"
        return $false
    }

    # Write C# source to separate files (avoids nested here-string escaping issues)
    @'
using System;
using System.Runtime.InteropServices;
public class Win32Launch {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(int flags, int dx, int dy, int data, int info);
}
'@ | Set-Content "$TOOL_DIR\Win32Launch.cs" -Encoding UTF8

    # WinHelper.cs: EnumWindows to reliably find and minimize console windows in Session 1
    # (Get-Process.MainWindowHandle is 0 for console apps like the PyAutoGUI terminal)
    @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinHelper {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr lp);
    public static IntPtr bcHwnd = IntPtr.Zero;
    public static bool MinimizeConsolesAndFocusBC() {
        bcHwnd = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr lp) {
            if (!IsWindowVisible(h)) return true;
            StringBuilder cls = new StringBuilder(256);
            GetClassName(h, cls, 256);
            StringBuilder ttl = new StringBuilder(256);
            GetWindowText(h, ttl, 256);
            string c = cls.ToString(); string t = ttl.ToString();
            if (t.Contains("BaseCamp")) { bcHwnd = h; }
            if (c == "ConsoleWindowClass" || t.Contains("python") ||
                t.Contains("pyautogui") || t.Contains("cmd.exe") ||
                t.Contains("PowerShell") || t.Contains("Terminal") ||
                t.Contains("OneDrive") || t.Contains("Windows Backup")) {
                ShowWindow(h, 6);
            }
            return true;
        }, IntPtr.Zero);
        if (bcHwnd != IntPtr.Zero) {
            ShowWindow(bcHwnd, 9);
            SetForegroundWindow(bcHwnd);
        }
        return true;
    }
}
'@ | Set-Content "$TOOL_DIR\WinHelper.cs" -Encoding UTF8

    # Write a PS script that launches BaseCamp AND dismisses Task Launcher
    # Use Add-Type -Path to load the .cs file (avoids nested here-string escaping)
    $launchScript = @"
Add-Type -Path `"$TOOL_DIR\Win32Launch.cs`" -ErrorAction SilentlyContinue
Add-Type -Path `"$TOOL_DIR\WinHelper.cs`" -ErrorAction SilentlyContinue

# Kill OneDrive and close its notification windows
Get-Process | Where-Object { `$_.Name -match `"OneDrive`" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Start-Process -FilePath `"$bcExe`"
Start-Sleep -Seconds 8

`$bc = `$null
for (`$i = 0; `$i -lt 20; `$i++) {
    `$bc = Get-Process `"BaseCamp`" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (`$bc -and `$bc.MainWindowHandle -ne [IntPtr]::Zero) { break }
    Start-Sleep -Seconds 2
}
if (-not `$bc) { exit 1 }

[Win32Launch]::SetForegroundWindow(`$bc.MainWindowHandle) | Out-Null
[Win32Launch]::ShowWindow(`$bc.MainWindowHandle, 9) | Out-Null
Start-Sleep -Seconds 3

# Click Plan a Trip to dismiss Task Launcher (NOT ESC - that closes BaseCamp!)
# Plan a Trip is at approximately (443, 210) in 1280x720 screen coordinates
[Win32Launch]::SetCursorPos(443, 210) | Out-Null
Start-Sleep -Milliseconds 200
[Win32Launch]::mouse_event(0x02, 0, 0, 0, 0) | Out-Null
Start-Sleep -Milliseconds 100
[Win32Launch]::mouse_event(0x04, 0, 0, 0, 0) | Out-Null
Start-Sleep -Seconds 5

# Dismiss any tutorial/info dialog that appears (ESC to close it)
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait(`"{ESCAPE}`")
Start-Sleep -Seconds 2

# Dismiss Detailed Map Needed dialog if it appears (click OK at ~806,405)
[Win32Launch]::SetCursorPos(806, 405) | Out-Null
Start-Sleep -Milliseconds 200
[Win32Launch]::mouse_event(0x02, 0, 0, 0, 0) | Out-Null
Start-Sleep -Milliseconds 100
[Win32Launch]::mouse_event(0x04, 0, 0, 0, 0) | Out-Null
Start-Sleep -Seconds 2

# Press ESC once more to close Route Planner if still open (returns to main map view)
[System.Windows.Forms.SendKeys]::SendWait(`"{ESCAPE}`")
Start-Sleep -Seconds 2

# === CRITICAL: Minimize ALL console windows (PyAutoGUI terminal, SSH sessions) ===
# and bring BaseCamp to the foreground. This runs in Session 1 where we CAN access
# window handles. Get-Process.MainWindowHandle is 0 for console apps, so we use
# EnumWindows via WinHelper.cs to reliably find and minimize them.
[WinHelper]::MinimizeConsolesAndFocusBC() | Out-Null
Start-Sleep -Seconds 1

# Double-click fells_loop in library to zoom map to the Bellevue Fells data area
# (fells_loop item is at approximately (191, 236) in the library tree)
[Win32Launch]::SetCursorPos(191, 236) | Out-Null
Start-Sleep -Milliseconds 200
[Win32Launch]::mouse_event(0x02, 0, 0, 0, 0) | Out-Null
Start-Sleep -Milliseconds 80
[Win32Launch]::mouse_event(0x04, 0, 0, 0, 0) | Out-Null
Start-Sleep -Milliseconds 150
[Win32Launch]::mouse_event(0x02, 0, 0, 0, 0) | Out-Null
Start-Sleep -Milliseconds 80
[Win32Launch]::mouse_event(0x04, 0, 0, 0, 0) | Out-Null
Start-Sleep -Seconds 3

# Final focus: minimize any remaining consoles and ensure BaseCamp is on top
[WinHelper]::MinimizeConsolesAndFocusBC() | Out-Null
"@

    $psScript  = "$TOOL_DIR\launch_bc_task.ps1"
    $batchFile = "$TOOL_DIR\launch_bc_task.bat"
    $launchScript | Set-Content $psScript -Encoding UTF8
    "@echo off`r`npowershell -ExecutionPolicy Bypass -File `"$psScript`"`r`n" | Set-Content $batchFile -Encoding ASCII

    Write-Host "Scheduling BaseCamp launch via schtasks /IT..."
    $taskName = "LaunchBaseCamp_Task"
    $runTime  = (Get-Date).AddMinutes(1).ToString("HH:mm")
    schtasks /Create /SC ONCE /IT /TR "$batchFile" /TN $taskName /ST $runTime /F 2>&1 | Out-Null

    Write-Host "  Waiting $WaitSeconds seconds..."
    Start-Sleep -Seconds $WaitSeconds
    schtasks /Delete /TN $taskName /F 2>&1 | Out-Null

    $procs = Get-Process "BaseCamp" -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "  BaseCamp running (PID $($procs[0].Id))."
        return $true
    } else {
        Write-Host "  WARNING: BaseCamp not detected after launch."
        return $false
    }
}


# --- Dismiss Windows dialogs (OneDrive, notifications) ---
function Dismiss-BackgroundDialogs {
    # Kill OneDrive popup if present
    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}


# --- Restore BaseCamp database from backup ---
function Restore-BaseCampData {
    $bcDataBase = "C:\Users\Docker\AppData\Roaming\Garmin\BaseCamp\Database"
    $backupDb   = "$BACKUP_DIR\Database"

    if (-not (Test-Path $backupDb)) {
        Write-Host "WARNING: No backup found at $backupDb"
        return $false
    }

    Close-BaseCamp
    if (Test-Path $bcDataBase) { Remove-Item $bcDataBase -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path (Split-Path $bcDataBase) | Out-Null
    Copy-Item $backupDb $bcDataBase -Recurse -Force
    Write-Host "BaseCamp database restored."
    return $true
}


# --- Clear BaseCamp database (for import_gpx_file task) ---
function Clear-BaseCampData {
    Close-BaseCamp
    $bcDataBase = "C:\Users\Docker\AppData\Roaming\Garmin\BaseCamp\Database"
    if (Test-Path $bcDataBase) {
        Remove-Item $bcDataBase -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "BaseCamp database cleared."
    }
}


# --- Take screenshot using PyAutoGUI ---
function Take-Screenshot {
    param([string]$Path = "C:\GarminTools\screenshot.png")
    $result = Invoke-PyAutoGUI @{ action = "screenshot"; path = $Path }
    if ($result -and $result.status -eq "ok") { return $Path }
    Write-Host "Screenshot via PyAutoGUI failed; trying .NET..."
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp    = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
        $gfx    = [System.Drawing.Graphics]::FromImage($bmp)
        $gfx.CopyFromScreen($screen.X, $screen.Y, 0, 0, $screen.Size)
        $bmp.Save($Path)
        $gfx.Dispose(); $bmp.Dispose()
        return $Path
    } catch { Write-Host "Screenshot failed: $_"; return $null }
}


# --- Bring BaseCamp to foreground ---
function Set-BaseCampForeground {
    $proc = Get-Process "BaseCamp" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
        [Win32]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 500
        return $true
    }
    return $false
}


# --- Minimize console windows that may cover BaseCamp ---
function Minimize-ConsoleWindows {
    # Include WindowsTerminal/wt which hosts SSH sessions and may cover BaseCamp
    @("python","cmd","powershell","WindowsTerminal","wt") | ForEach-Object {
        $procs = Get-Process $_ -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
                [Win32]::ShowWindow($p.MainWindowHandle, 6) | Out-Null
            }
        }
    }
}

Write-Host "task_utils.ps1 loaded."
