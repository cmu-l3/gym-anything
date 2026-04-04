###############################################################################
# task_utils.ps1 — Shared utility functions for TopoCal tasks
###############################################################################

Set-StrictMode -Version Latest

# --- Global Constants ---
$TOPOCAL_PYAG_PORT = 5555

# --- Find TopoCal Install Directory and Exe Name ---
function Get-TopoCalInstallDir {
    $markerFile = "C:\Windows\Temp\topocal_install_dir.txt"
    if (Test-Path $markerFile) {
        $dir = (Get-Content $markerFile -Raw).Trim()
        $exe = Get-TopoCalExeName
        if (Test-Path (Join-Path $dir $exe)) { return $dir }
    }
    $paths = @(
        "C:\Program Files (x86)\TopoCal 2025",
        "C:\Program Files\TopoCal 2025",
        "C:\Program Files (x86)\TopoCal",
        "C:\Program Files\TopoCal"
    )
    foreach ($p in $paths) {
        $candidates = Get-ChildItem $p -Filter "TopoCal*.exe" -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -notmatch "unins" }
        if ($candidates) {
            Set-Content -Path "C:\Windows\Temp\topocal_install_dir.txt" -Value $p
            Set-Content -Path "C:\Windows\Temp\topocal_exe_name.txt"    -Value $candidates[0].Name
            return $p
        }
    }
    return $null
}

function Get-TopoCalExeName {
    $exeMarker = "C:\Windows\Temp\topocal_exe_name.txt"
    if (Test-Path $exeMarker) { return (Get-Content $exeMarker -Raw).Trim() }
    return "TopoCal 2025.exe"
}

function Get-TopoCalExePath {
    $dir = Get-TopoCalInstallDir
    $exe = Get-TopoCalExeName
    if ($dir) { return Join-Path $dir $exe }
    return $null
}

# --- PyAutoGUI Communication ---
# Protocol: JSON line {"action":"...", ...} -> JSON response line
# Supports both "action" and "type" field for compatibility.
function Send-PyAutoGUICommand {
    param([string]$JsonCmd)
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect("127.0.0.1", $TOPOCAL_PYAG_PORT)
        $stream = $tcpClient.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        $writer.WriteLine($JsonCmd)
        $writer.Flush()
        $response = $reader.ReadLine()
        $tcpClient.Close()
        return $response
    } catch {
        Write-Host "PyAutoGUI command failed: $_"
        return $null
    }
}

function Invoke-PyAutoGUIClick {
    param([int]$X, [int]$Y)
    Send-PyAutoGUICommand ('{"action":"click","x":' + $X + ',"y":' + $Y + '}') | Out-Null
    Start-Sleep -Milliseconds 500
}

function Invoke-PyAutoGUIPress {
    param([string]$Key)
    Send-PyAutoGUICommand ('{"action":"press","key":"' + $Key + '"}') | Out-Null
    Start-Sleep -Milliseconds 300
}

function Invoke-PyAutoGUIType {
    param([string]$Text)
    $escaped = $Text -replace '"', '\"'
    Send-PyAutoGUICommand ('{"action":"typewrite","text":"' + $escaped + '"}') | Out-Null
    Start-Sleep -Milliseconds 300
}

function Invoke-PyAutoGUIHotkey {
    param([string[]]$Keys)
    $keysJson = ($Keys | ForEach-Object { "`"$_`"" }) -join ","
    Send-PyAutoGUICommand ('{"action":"hotkey","keys":[' + $keysJson + ']}') | Out-Null
    Start-Sleep -Milliseconds 300
}

# --- Ensure License HTTP Server Running ---
function Ensure-HTTPServer {
    # Try port 80
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect("127.0.0.1", 80)
        $tcp.Close()
        Write-Host "License HTTP server confirmed on port 80"
        return
    } catch {}
    # Not running — start it
    Write-Host "Starting HTTPServer scheduled task..."
    $ErrorActionPreference = "Continue"
    Start-ScheduledTask -TaskName "HTTPServer" -ErrorAction SilentlyContinue
    $ErrorActionPreference = "Stop"
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Seconds 2
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect("127.0.0.1", 80)
            $tcp.Close()
            Write-Host "HTTPServer started"
            return
        } catch {}
    }
    Write-Host "WARNING: HTTPServer may not have started"
}

# --- Ensure PyAutoGUI Server Running ---
function Ensure-PyAutoGUIServer {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect("127.0.0.1", $TOPOCAL_PYAG_PORT)
        $tcp.Close()
        Write-Host "PyAutoGUI server confirmed on port $TOPOCAL_PYAG_PORT"
        return
    } catch {}
    Write-Host "Starting PyAutoGUIServer scheduled task..."
    $ErrorActionPreference = "Continue"
    Start-ScheduledTask -TaskName "PyAutoGUIServer" -ErrorAction SilentlyContinue
    $ErrorActionPreference = "Stop"
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 2
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect("127.0.0.1", $TOPOCAL_PYAG_PORT)
            $tcp.Close()
            Write-Host "PyAutoGUI server started"
            return
        } catch {}
    }
    Write-Host "WARNING: PyAutoGUI server may not have started"
}

# --- Handle TopoCal Activation Dialog ---
# TopoCal shows an activation window on first launch. This function:
#  1. Clicks "Ejecutar Lite" to initiate HTTP-based license check
#  2. Clicks "No descargar" to dismiss the "Aviso importante" update dialog
#     (patched DLL keeps TopoCal open instead of exiting)
function Handle-TopoCalActivation {
    param([int]$WaitForDialog = 8)

    Write-Host "Handling TopoCal activation dialog..."
    Start-Sleep -Seconds $WaitForDialog

    # Step 1: Click "Ejecutar Lite" icon (activation dialog)
    Write-Host "Clicking 'Ejecutar Lite' (~835, 370)..."
    Invoke-PyAutoGUIClick -X 835 -Y 370
    Start-Sleep -Seconds 4

    # Step 2: Click the green checkmark icon to highlight it
    Write-Host "Clicking checkmark icon (~668, 200)..."
    Invoke-PyAutoGUIClick -X 668 -Y 200
    Start-Sleep -Seconds 2

    # Step 3: Click "Continuar" text to trigger Lite activation HTTP call
    # The text label (y~230) triggers activation, not the icon (y~200).
    Write-Host "Clicking 'Continuar' text (~668, 230)..."
    Invoke-PyAutoGUIClick -X 668 -Y 230
    Start-Sleep -Seconds 8

    # Step 4: Use win32 API to hide activation dialog and show main CAD window
    # NOTE: Do NOT press Escape or close the dialog normally — that triggers exit.
    Write-Host "Switching to main CAD window..."
    $showScript = @'
import ctypes
from ctypes import wintypes
import time
u = ctypes.windll.user32
WNDENUMPROC = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
def get_text(h):
    n = u.GetWindowTextLengthW(h)
    if n == 0: return ''
    b = ctypes.create_unicode_buffer(n+1)
    u.GetWindowTextW(h, b, n+1)
    return b.value
windows = {}
def enum_top(h, lp):
    t = get_text(h)
    if 'Activar TopoCal' in t: windows['activar'] = h
    elif 'TopoCal 2025' in t and 'Dibujo' in t: windows['main'] = h
    return True
u.EnumWindows(WNDENUMPROC(enum_top), 0)
if 'activar' in windows:
    u.ShowWindow(windows['activar'], 0)
    time.sleep(0.5)
if 'main' in windows:
    u.ShowWindow(windows['main'], 5)
    time.sleep(0.3)
    u.ShowWindow(windows['main'], 9)
    time.sleep(0.3)
    u.SetForegroundWindow(windows['main'])
    print('MAIN_WINDOW_VISIBLE')
else:
    print('MAIN_WINDOW_NOT_FOUND')
'@
    Set-Content -Path "C:\Windows\Temp\show_cad.py" -Value $showScript -Encoding UTF8
    $pyResult = python "C:\Windows\Temp\show_cad.py" 2>&1
    Write-Host "Window switch: $pyResult"

    Write-Host "Activation handling complete"
    Start-Sleep -Seconds 3
}

# --- Launch TopoCal via pre-registered schtask ---
function Start-TopoCalInteractive {
    param(
        [string]$FilePath = "",
        [int]$WaitSeconds = 15,
        [switch]$HandleActivation = $true
    )

    $exePath = Get-TopoCalExePath
    if (-not $exePath -or -not (Test-Path $exePath)) {
        Write-Host "ERROR: TopoCal executable not found"
        return $false
    }

    # Kill any existing TopoCal processes
    Get-Process | Where-Object { $_.ProcessName -match "TopoCal|Topo3" } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # If a specific file should be opened, update the launch batch file
    if ($FilePath -and (Test-Path $FilePath)) {
        $dir = Get-TopoCalInstallDir
        $exe = Get-TopoCalExeName
        $batchContent = "@echo off`r`ncd /d `"$dir`"`r`nstart `"`" `"$exe`" `"$FilePath`""
        Set-Content -Path "C:\Users\Docker\launch_topocal.bat" -Value $batchContent -Encoding ASCII
    } else {
        $dir = Get-TopoCalInstallDir
        $exe = Get-TopoCalExeName
        $batchContent = "@echo off`r`ncd /d `"$dir`"`r`nstart `"`" `"$exe`""
        Set-Content -Path "C:\Users\Docker\launch_topocal.bat" -Value $batchContent -Encoding ASCII
    }

    $ErrorActionPreference = "Continue"
    Start-ScheduledTask -TaskName "LaunchTC" -ErrorAction SilentlyContinue
    $ErrorActionPreference = "Stop"

    Write-Host "Waiting for TopoCal to launch ($WaitSeconds seconds)..."
    Start-Sleep -Seconds $WaitSeconds

    # Check if TopoCal process appeared
    $tcFound = $false
    for ($w = 0; $w -lt 15; $w++) {
        if (Get-Process | Where-Object { $_.ProcessName -match "TopoCal|Topo3" }) {
            $tcFound = $true
            break
        }
        Start-Sleep -Seconds 2
    }

    if (-not $tcFound) {
        Write-Host "WARNING: TopoCal process not detected"
        return $false
    }

    # Handle activation dialog (always present on launch)
    if ($HandleActivation) {
        Handle-TopoCalActivation
    }

    # Check if main window is now visible
    $windowFound = $false
    for ($w = 0; $w -lt 15; $w++) {
        $procs = Get-Process | Where-Object { $_.ProcessName -match "TopoCal|Topo3" -and $_.MainWindowTitle -ne "" }
        if ($procs) {
            Write-Host "TopoCal window detected: $($procs[0].MainWindowTitle)"
            $windowFound = $true
            break
        }
        Start-Sleep -Seconds 2
    }

    return $windowFound
}

# --- Close Browsers and Suppress Edge ---
function Close-Browsers {
    Get-Process -Name "msedge"   -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -Name "chrome"   -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -Name "firefox"  -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    $edgeProfiles = Get-ChildItem "C:\Users\Docker\AppData\Local\Microsoft\Edge\User Data" -Directory -ErrorAction SilentlyContinue
    foreach ($prof in $edgeProfiles) {
        $sessionDir = "$($prof.FullName)\Sessions"
        if (Test-Path $sessionDir) {
            Remove-Item "$sessionDir\*" -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}

# --- Start Edge Killer Background Task ---
function Start-EdgeKillerTask {
    $taskName = "KillEdge_$(Get-Random)"
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN $taskName /SC ONCE /ST "00:00" /IT /RL HIGHEST /TR "cmd /c `"for /L %%i in (1,1,60) do (taskkill /F /IM msedge.exe >nul 2>&1 & timeout /t 2 /nobreak >nul)`"" /F 2>$null
    schtasks /Run /TN $taskName 2>$null
    $ErrorActionPreference = "Stop"
    return @{ TaskName = $taskName }
}

function Stop-EdgeKillerTask {
    param([hashtable]$KillerInfo)
    if ($KillerInfo -and $KillerInfo.TaskName) {
        $ErrorActionPreference = "Continue"
        schtasks /Delete /TN $KillerInfo.TaskName /F 2>$null
        $ErrorActionPreference = "Stop"
    }
}

# --- Dismiss Generic Dialogs (legacy fallback) ---
function Dismiss-TopoCalDialogs {
    param([int]$Retries = 3)
    for ($r = 0; $r -lt $Retries; $r++) {
        Invoke-PyAutoGUIPress -Key "escape"
        Start-Sleep -Seconds 1
        Invoke-PyAutoGUIPress -Key "enter"
        Start-Sleep -Seconds 1
    }
}

# --- Bring TopoCal to Foreground ---
function Set-TopoCalForeground {
    $procs = Get-Process | Where-Object { $_.ProcessName -match "TopoCal|Topo3" -and $_.MainWindowTitle -ne "" }
    if ($procs) {
        try {
            Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Foreground {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
            $hwnd = $procs[0].MainWindowHandle
            if ($hwnd -ne [IntPtr]::Zero) {
                [Win32Foreground]::ShowWindow($hwnd, 9)  # SW_RESTORE
                [Win32Foreground]::SetForegroundWindow($hwnd)
                Write-Host "TopoCal brought to foreground"
                return $true
            }
        } catch {
            Write-Host "Win32 foreground failed: $_"
        }
    }
    return $false
}
