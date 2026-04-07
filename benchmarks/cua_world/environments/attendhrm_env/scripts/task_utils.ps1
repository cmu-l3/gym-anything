# ==========================================================================
# task_utils.ps1 — Shared utility functions for AttendHRM environment tasks
# ==========================================================================
# NOTE: Do NOT use Set-StrictMode here; this file is sourced by setup_task.ps1
# scripts and strict mode can cause issues when sourcing.

# --------------------------------------------------------------------------
# Win32 helpers for window management
# --------------------------------------------------------------------------
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class Win32Window {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    public const int SW_MINIMIZE  = 6;
    public const int SW_RESTORE   = 9;
    public const int SW_MAXIMIZE  = 3;
    public const int SW_SHOWNORMAL = 1;

    public static string GetWindowTitle(IntPtr hWnd) {
        StringBuilder sb = new StringBuilder(512);
        GetWindowText(hWnd, sb, 512);
        return sb.ToString();
    }
}
"@

# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------
$ATTENDHRM_PROCESS_NAME = "Attend"
$ATTENDHRM_PATH_FILE    = "C:\Users\Docker\attendhrm_path.txt"
$ATTENDHRM_READY_MARKER = "C:\Users\Docker\attendhrm_ready.marker"
$PYAUTOGUI_PORT         = 5555
$PYAUTOGUI_HOST         = "127.0.0.1"

# --------------------------------------------------------------------------
# Find-AttendHRMExe: Return the path to Attend.exe
# --------------------------------------------------------------------------
function Find-AttendHRMExe {
    # Check saved path from install script
    if (Test-Path $ATTENDHRM_PATH_FILE) {
        try {
            $path = (Get-Content $ATTENDHRM_PATH_FILE -Raw).Trim([char]0, ' ', "`r", "`n")
            if ($path -and $path.Length -gt 3 -and (Test-Path $path)) {
                return $path
            }
        } catch {
            Write-Host "Warning: Could not read saved path file: $_"
        }
    }

    # Known install locations (Bin\Attend.exe verified as actual install path)
    $candidates = @(
        "C:\Program Files (x86)\Attend HRM\Bin\Attend.exe",
        "C:\Program Files (x86)\Attend HRM\Attend.exe",
        "C:\Program Files\Attend HRM\Bin\Attend.exe",
        "C:\Program Files\Attend HRM\Attend.exe",
        "C:\Program Files (x86)\AttendHRM\Attend.exe",
        "C:\Program Files\AttendHRM\Attend.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }

    # Recursive search
    $found = Get-ChildItem "C:\Program Files (x86)", "C:\Program Files" `
        -Recurse -Filter "Attend.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -notmatch "unins" } | Select-Object -First 1
    if ($found) { return $found.FullName }

    throw "Attend.exe not found on system"
}

# --------------------------------------------------------------------------
# Stop-AttendHRM: Kill any running AttendHRM process
# --------------------------------------------------------------------------
function Stop-AttendHRM {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Get-Process -Name $ATTENDHRM_PROCESS_NAME -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    # Second kill pass in case of slow shutdown
    Get-Process -Name $ATTENDHRM_PROCESS_NAME -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP
    Write-Host "AttendHRM stopped"
}

# --------------------------------------------------------------------------
# Close-Browsers: Kill Edge and other browsers, clear session restore data
# --------------------------------------------------------------------------
function Close-Browsers {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        taskkill /F /IM msedge.exe 2>$null
        taskkill /F /IM chrome.exe 2>$null
        taskkill /F /IM firefox.exe 2>$null
        Start-Sleep -Seconds 2
        taskkill /F /IM msedge.exe 2>$null

        # Clear Edge session restore data
        $edgeUserData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
        if (Test-Path $edgeUserData) {
            Get-ChildItem $edgeUserData -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                foreach ($f in @("Current Session","Current Tabs","Last Session","Last Tabs")) {
                    Remove-Item (Join-Path $_.FullName $f) -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # Set Edge Group Policy: disable startup boost and session restore
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force 2>$null | Out-Null }
        New-ItemProperty -Path $regPath -Name "StartupBoostEnabled"  -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
        New-ItemProperty -Path $regPath -Name "BackgroundModeEnabled" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
        New-ItemProperty -Path $regPath -Name "RestoreOnStartup"      -Value 5 -PropertyType DWord -Force 2>$null | Out-Null
    } finally {
        $ErrorActionPreference = $prevEAP
    }
}

# --------------------------------------------------------------------------
# Start-EdgeKillerTask: Create a background schtask that kills Edge every 2s.
# Uses a VBS wrapper to launch the batch file HIDDEN (windowStyle=0) so that
# no visible CMD window appears on the interactive desktop.
# Returns task info hashtable for use with Stop-EdgeKillerTask.
# --------------------------------------------------------------------------
function Start-EdgeKillerTask {
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $taskName   = "KillEdge_$id"
    $batchPath  = "C:\Windows\Temp\kill_edge_$id.cmd"
    $vbsPath    = "C:\Windows\Temp\kill_edge_$id.vbs"

    # Batch file: kill Edge every 2s for ~2 minutes
    $batchContent = "@echo off`r`nfor /L %%i in (1,1,60) do (`r`n    taskkill /F /IM msedge.exe >nul 2>&1`r`n    timeout /t 2 /nobreak >nul 2>&1`r`n)"
    [System.IO.File]::WriteAllText($batchPath, $batchContent)

    # VBS wrapper: launches the batch in a HIDDEN window (0 = vbHide)
    $vbsContent = 'CreateObject("WScript.Shell").Run "cmd /c ' + $batchPath + '", 0, False'
    [System.IO.File]::WriteAllText($vbsPath, $vbsContent)

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
    schtasks /Create /TN $taskName /TR "wscript.exe `"$vbsPath`"" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null | Out-Null
    schtasks /Run /TN $taskName 2>$null | Out-Null
    $ErrorActionPreference = $prevEAP

    Write-Host "Edge killer task started: $taskName"
    return @{ TaskName = $taskName; ScriptPath = $batchPath; VbsPath = $vbsPath }
}

# --------------------------------------------------------------------------
# Stop-EdgeKillerTask: Clean up the Edge killer scheduled task and hidden
# cmd.exe process spawned by the VBS wrapper.
# --------------------------------------------------------------------------
function Stop-EdgeKillerTask {
    param([hashtable] $KillerInfo)
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    if ($KillerInfo -and $KillerInfo.TaskName) {
        schtasks /End    /TN $KillerInfo.TaskName 2>$null | Out-Null
        schtasks /Delete /TN $KillerInfo.TaskName /F 2>$null | Out-Null
    }
    # Kill any lingering hidden cmd.exe running the Edge killer batch
    if ($KillerInfo -and $KillerInfo.ScriptPath) {
        $batchFile = Split-Path $KillerInfo.ScriptPath -Leaf
        Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match [regex]::Escape($batchFile) } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    # Clean up batch and VBS files
    foreach ($key in @("ScriptPath", "VbsPath")) {
        if ($KillerInfo -and $KillerInfo[$key] -and (Test-Path $KillerInfo[$key])) {
            Remove-Item $KillerInfo[$key] -Force -ErrorAction SilentlyContinue
        }
    }
    $ErrorActionPreference = $prevEAP
    Write-Host "Edge killer task stopped"
}

# --------------------------------------------------------------------------
# Invoke-PyAutoGUICommand: Send a command to the PyAutoGUI TCP server (port 5555).
# The server runs in the interactive desktop session and accepts JSON commands.
# --------------------------------------------------------------------------
function Invoke-PyAutoGUICommand {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Command,
        [string]    $Server           = $PYAUTOGUI_HOST,
        [int]       $Port             = $PYAUTOGUI_PORT,
        [int]       $ConnectTimeoutMs = 5000
    )

    $json = $Command | ConvertTo-Json -Compress
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($Server, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($ConnectTimeoutMs, $false)) {
            throw "PyAutoGUI connect timeout to ${Server}:${Port}"
        }
        $client.EndConnect($iar)

        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true
        $writer.WriteLine($json)

        $reader = New-Object System.IO.StreamReader($stream)
        $line = $reader.ReadLine()
        if (-not $line) { throw "PyAutoGUI returned empty response" }

        $resp = $line | ConvertFrom-Json
        if ($resp.success -eq $false) { throw "PyAutoGUI error: $($resp.error)" }
        return $resp
    } finally {
        try { $client.Close() } catch { }
    }
}

# --------------------------------------------------------------------------
# PyAG: Shorthand wrappers for common PyAutoGUI commands
# --------------------------------------------------------------------------
function PyAG-Click {
    param([int]$x, [int]$y, [int]$DelayMs = 200)
    try {
        Invoke-PyAutoGUICommand -Command @{action="click"; x=$x; y=$y} | Out-Null
    } catch { Write-Host "PyAG-Click ($x,$y) failed: $($_.Exception.Message)" }
    Start-Sleep -Milliseconds $DelayMs
}

function PyAG-Type {
    param([string]$text, [double]$Interval = 0.04, [int]$DelayMs = 300)
    try {
        Invoke-PyAutoGUICommand -Command @{action="typewrite"; text=$text; interval=$Interval} | Out-Null
    } catch { Write-Host "PyAG-Type '$text' failed: $($_.Exception.Message)" }
    Start-Sleep -Milliseconds $DelayMs
}

function PyAG-Press {
    param([string]$key, [int]$DelayMs = 200)
    try {
        Invoke-PyAutoGUICommand -Command @{action="press"; keys=$key} | Out-Null
    } catch { Write-Host "PyAG-Press '$key' failed: $($_.Exception.Message)" }
    Start-Sleep -Milliseconds $DelayMs
}

function PyAG-Hotkey {
    param([string[]]$keys, [int]$DelayMs = 300)
    try {
        Invoke-PyAutoGUICommand -Command @{action="hotkey"; keys=$keys} | Out-Null
    } catch { Write-Host "PyAG-Hotkey '$($keys -join '+')' failed: $($_.Exception.Message)" }
    Start-Sleep -Milliseconds $DelayMs
}

# --------------------------------------------------------------------------
# Launch-AttendHRMInteractive: Launch AttendHRM via double-click on the
# desktop shortcut icon. PyAutoGUI runs in Session 1 (interactive desktop),
# so the resulting window is automatically in the foreground.
#
# The AttendHRM icon is at (30, 469) on the left side of the desktop,
# visible even when the terminal window is open (terminal starts at x≈52).
# --------------------------------------------------------------------------
function Launch-AttendHRMInteractive {
    param([int]$WaitSeconds = 30)

    # Wait for Firebird service (critical after cold boot from checkpoint)
    Write-Host "Waiting for Firebird service..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $fbElapsed = 0
    while ($fbElapsed -lt 120) {
        $fbSvc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*Firebird*" -and $_.Status -eq "Running" }
        if ($fbSvc) {
            Write-Host "Firebird running after ${fbElapsed}s"
            break
        }
        $stoppedFb = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*Firebird*" }
        if ($stoppedFb) { Start-Service $stoppedFb.Name -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 5
        $fbElapsed += 5
    }
    $ErrorActionPreference = $prevEAP
    # Give Firebird extra time to fully initialize after service reports Running
    Start-Sleep -Seconds 10

    Write-Host "Double-clicking AttendHRM desktop icon to launch in foreground..."

    # Double-click the AttendHRM desktop shortcut via PyAutoGUI (Session 1).
    # This launches Attend.exe AND brings the window to the foreground.
    Invoke-PyAutoGUICommand -Command @{action="doubleClick"; x=30; y=469} | Out-Null

    Write-Host "AttendHRM launch triggered, waiting ${WaitSeconds}s..."
    Start-Sleep -Seconds $WaitSeconds
    Write-Host "AttendHRM launched in interactive session"
}


# --------------------------------------------------------------------------
# Wait-ForAttendHRM: Poll until the Attend.exe process is running.
# Returns $true if ready within timeout, $false otherwise.
# --------------------------------------------------------------------------
function Wait-ForAttendHRM {
    param([int]$TimeoutSec = 60)

    $elapsed = 0
    while ($elapsed -lt $TimeoutSec) {
        $proc = Get-Process -Name $ATTENDHRM_PROCESS_NAME -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "AttendHRM process found (PID $($proc.Id | Select-Object -First 1))"
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    Write-Host "WARNING: AttendHRM process not found within ${TimeoutSec}s"
    return $false
}

# --------------------------------------------------------------------------
# Set-AttendHRMForeground: Bring the AttendHRM main window to the foreground
# --------------------------------------------------------------------------
function Set-AttendHRMForeground {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $proc = Get-Process -Name $ATTENDHRM_PROCESS_NAME -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
        [Win32Window]::ShowWindow($proc.MainWindowHandle, [Win32Window]::SW_RESTORE)  | Out-Null
        [Win32Window]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
        Write-Host "AttendHRM set to foreground"
        $ErrorActionPreference = $prevEAP
        return $true
    }
    Write-Host "WARNING: Could not find AttendHRM window handle"
    $ErrorActionPreference = $prevEAP
    return $false
}

# --------------------------------------------------------------------------
# Login-AttendHRM: Perform coordinate-based login to AttendHRM.
#
# Verified login screen coordinates (1280x720):
#   Password field: (665, 381) — username "admin" is pre-populated
#   Login button:   (618, 491)
#
# CEF error dialog appears on EVERY launch at x:533-752, y:0 (top of screen).
#   Close button (title bar X): (737, 13)
# Demo warning dialog (after login):
#   OK button: (639, 371)
# --------------------------------------------------------------------------
function Login-AttendHRM {
    param([int]$WaitAfterLoginSec = 6)

    Write-Host "Logging in to AttendHRM (admin/admin)..."

    # Dismiss "CEF binaries missing" error dialog that appears on every launch.
    # It appears at the TOP of the screen (title bar at y=0-20). Click its X button
    # to close it before attempting login. If no CEF dialog is present, this click
    # lands on empty desktop space (harmless).
    Write-Host "Dismissing CEF error dialog (if present)..."
    PyAG-Click -x 737 -y 13 -DelayMs 500   # Click X on CEF error dialog title bar
    Start-Sleep -Seconds 2                   # Wait for login dialog to appear in front

    # Click the password field (username "admin" is pre-filled)
    PyAG-Click -x 665 -y 381 -DelayMs 500

    # Type password: admin
    PyAG-Type -text "admin" -DelayMs 400

    # Click Login button
    PyAG-Click -x 618 -y 491 -DelayMs 1000

    # Dismiss Windows Firewall dialog for AttendHRMAPI.exe (first launch only).
    # The dialog asks "Do you want to allow AttendHRMAPI on all networks?"
    # Allow button position varies by dialog layout:
    #   - Compact (no checkboxes): (538, 502)
    #   - Expanded (with checkboxes): (538, 579)
    # Click both to handle either layout. Harmless if dialog not present.
    Write-Host "Handling Windows Firewall dialog for AttendHRMAPI (if present)..."
    Start-Sleep -Seconds 3                   # Wait for firewall dialog to appear
    PyAG-Click -x 538 -y 502 -DelayMs 500   # Click Allow (compact layout)
    PyAG-Click -x 538 -y 579 -DelayMs 500   # Click Allow (expanded layout)

    Write-Host "Login submitted, waiting ${WaitAfterLoginSec}s for main window..."
    Start-Sleep -Seconds $WaitAfterLoginSec

    # Dismiss "You have chosen Database as Demo" warning dialog (OK at 639, 371).
    # This dialog appears every login with the Demo database selected.
    # Press Enter first then click OK explicitly.
    PyAG-Press -key "return" -DelayMs 500
    PyAG-Click -x 639 -y 371 -DelayMs 500   # Click OK on Demo warning dialog
    Start-Sleep -Seconds 2

    # Handle Employer Details dialog (first-run only).
    # Fill and save. If dialog isn't present, clicks land harmlessly on dashboard.
    Write-Host "Handling Employer Details dialog (if present)..."
    PyAG-Click -x 700 -y 303 -DelayMs 300
    PyAG-Type -text "Demo Company" -DelayMs 300
    PyAG-Click -x 700 -y 330 -DelayMs 300
    PyAG-Type -text "New York" -DelayMs 300
    PyAG-Click -x 700 -y 357 -DelayMs 300
    PyAG-Type -text "USA" -DelayMs 300
    PyAG-Click -x 767 -y 393 -DelayMs 1000
    Start-Sleep -Seconds 2
    PyAG-Click -x 639 -y 371 -DelayMs 500
    PyAG-Click -x 767 -y 393 -DelayMs 1000
    Start-Sleep -Seconds 2

    Write-Host "Login complete"
}

# --------------------------------------------------------------------------
# Handle-ConfirmDialog: Click "Yes" if an "All open screens should be closed"
# confirmation dialog is present. Safe to call even if dialog is not visible.
#
# Confirm dialog "Yes" button: (558, 371)
# --------------------------------------------------------------------------
function Handle-ConfirmDialog {
    param([int]$DelayMs = 500)
    # Click Yes — harmless if dialog isn't showing (just clicks background)
    PyAG-Click -x 558 -y 371 -DelayMs $DelayMs
    Write-Host "Confirm dialog handled (Yes clicked)"
}

# --------------------------------------------------------------------------
# Navigate-ToDepartment: Open Modules > Employer > Department
#
# Verified coordinates (1280x720):
#   Modules menu:    (118, 29)
#   Employer item:   (152, 84)
#   Department item: (307, 144)
# --------------------------------------------------------------------------
function Navigate-ToDepartment {
    Write-Host "Navigating to Modules > Employer > Department..."
    Set-AttendHRMForeground | Out-Null
    Start-Sleep -Milliseconds 300

    PyAG-Click -x 118 -y 29 -DelayMs 400    # Open Modules menu
    PyAG-Click -x 152 -y 84 -DelayMs 400    # Hover/click Employer
    PyAG-Click -x 307 -y 144 -DelayMs 500   # Click Department
    Start-Sleep -Seconds 2                   # Wait for screen to load

    Write-Host "Navigated to Department screen"
}

# --------------------------------------------------------------------------
# Navigate-ToEmployeeList: Open Modules > Employee > Employee
#
# Verified coordinates (1280x720):
#   Modules menu:  (118, 29)
#   Employee item: (153, 114)
#   Employee list: (299, 144)
# --------------------------------------------------------------------------
function Navigate-ToEmployeeList {
    Write-Host "Navigating to Modules > Employee > Employee..."
    Set-AttendHRMForeground | Out-Null
    Start-Sleep -Milliseconds 300

    PyAG-Click -x 118 -y 29 -DelayMs 400    # Open Modules menu
    PyAG-Click -x 153 -y 114 -DelayMs 400   # Hover/click Employee
    PyAG-Click -x 299 -y 144 -DelayMs 500   # Click Employee (list)
    Start-Sleep -Seconds 2                   # Wait for screen to load

    Write-Host "Navigated to Employee list screen"
}

# --------------------------------------------------------------------------
# Navigate-ToEmployeeImport: Open Modules > Employee > Import
#
# Verified coordinates (1280x720):
#   Modules menu:  (118, 29)
#   Employee item: (153, 114)
#   Import item:   (293, 565)
# --------------------------------------------------------------------------
function Navigate-ToEmployeeImport {
    Write-Host "Navigating to Modules > Employee > Import..."
    Set-AttendHRMForeground | Out-Null
    Start-Sleep -Milliseconds 300

    PyAG-Click -x 118 -y 29 -DelayMs 400    # Open Modules menu
    PyAG-Click -x 153 -y 114 -DelayMs 400   # Hover/click Employee
    PyAG-Click -x 293 -y 565 -DelayMs 500   # Click Import
    Start-Sleep -Seconds 2                   # Wait for wizard to open

    Write-Host "Navigated to Employee Import wizard"
}

# --------------------------------------------------------------------------
# Navigate-ToAttendanceReports: Open Modules > Reports > Attendance Reports
#
# Verified coordinates (1280x720):
#   Modules menu:          (118, 29)
#   Reports item:          (147, 354)
#   Attendance Reports:    (329, 474)
# --------------------------------------------------------------------------
function Navigate-ToAttendanceReports {
    Write-Host "Navigating to Modules > Reports > Attendance Reports..."
    Set-AttendHRMForeground | Out-Null
    Start-Sleep -Milliseconds 300

    PyAG-Click -x 118 -y 29 -DelayMs 400    # Open Modules menu
    PyAG-Click -x 147 -y 354 -DelayMs 400   # Hover/click Reports
    PyAG-Click -x 329 -y 474 -DelayMs 500   # Click Attendance Reports
    Start-Sleep -Seconds 2                   # Wait for screen to load

    Write-Host "Navigated to Attendance Reports screen"
}

# --------------------------------------------------------------------------
# (Legacy stubs - kept for compatibility, replaced by specific functions above)
# --------------------------------------------------------------------------
function Navigate-ToMastersMenu {
    Write-Host "WARNING: Navigate-ToMastersMenu is deprecated; use Navigate-ToDepartment"
    Navigate-ToDepartment
}

function Navigate-ToEmployeesMenu {
    Write-Host "WARNING: Navigate-ToEmployeesMenu is deprecated; use Navigate-ToEmployeeList"
    Navigate-ToEmployeeList
}

function Navigate-ToReportsMenu {
    Write-Host "WARNING: Navigate-ToReportsMenu is deprecated; use Navigate-ToAttendanceReports"
    Navigate-ToAttendanceReports
}

# --------------------------------------------------------------------------
# Close-AttendHRM: Gracefully close AttendHRM via Alt+F4.
# Handles any save confirmation dialog with Enter (default = No/Cancel = safe).
# --------------------------------------------------------------------------
function Close-AttendHRM {
    Write-Host "Closing AttendHRM..."
    Set-AttendHRMForeground | Out-Null
    Start-Sleep -Milliseconds 300

    # Alt+F4 to close the window
    PyAG-Hotkey -keys @("alt", "F4") -DelayMs 1500

    # Handle any "Save?" confirmation dialog — press Escape/No to cancel safely
    PyAG-Press -key "escape" -DelayMs 500
    PyAG-Press -key "n" -DelayMs 500

    # Force kill if still running after 5 seconds
    Start-Sleep -Seconds 3
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Get-Process -Name $ATTENDHRM_PROCESS_NAME -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP

    Write-Host "AttendHRM closed"
}

Write-Host "task_utils.ps1 loaded"
