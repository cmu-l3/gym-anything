# ==========================================================================
# task_utils.ps1 — Shared utility functions for bcWebCam environment tasks
# ==========================================================================

Set-StrictMode -Version Latest

# --------------------------------------------------------------------------
# Win32 helpers for window management (minimize console, bring bcWebCam
# to foreground, verify foreground state)
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

    public const int SW_MINIMIZE = 6;
    public const int SW_RESTORE = 9;

    public static string GetWindowTitle(IntPtr hWnd) {
        StringBuilder sb = new StringBuilder(256);
        GetWindowText(hWnd, sb, 256);
        return sb.ToString();
    }
}
"@

# --------------------------------------------------------------------------
# Close-Browsers: Kill Edge and other browsers, clear session restore data,
# and set registry policies to prevent Edge from auto-launching.
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

        # Clear Edge session restore data across ALL profiles
        $edgeUserData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
        if (Test-Path $edgeUserData) {
            Get-ChildItem $edgeUserData -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                foreach ($f in @("Current Session","Current Tabs","Last Session","Last Tabs")) {
                    Remove-Item (Join-Path $_.FullName $f) -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # Set Edge Group Policy: disable startup boost, background mode, session restore
        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force 2>$null | Out-Null }
        New-ItemProperty -Path $regPath -Name "StartupBoostEnabled" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
        New-ItemProperty -Path $regPath -Name "BackgroundModeEnabled" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
        # RestoreOnStartup=5 = open new tab page (do NOT restore previous session)
        New-ItemProperty -Path $regPath -Name "RestoreOnStartup" -Value 5 -PropertyType DWord -Force 2>$null | Out-Null

        Start-Sleep -Seconds 1
        taskkill /F /IM msedge.exe 2>$null
    } finally {
        $ErrorActionPreference = $prevEAP
    }
}

# --------------------------------------------------------------------------
# Start-EdgeKillerTask: Create a scheduled task in the INTERACTIVE session
# that kills Edge every 2 seconds for 120 seconds. Uses schtasks /IT so
# it runs in Session 1 (same session as Edge), which is more reliable than
# Start-Job (runs in SSH Session 0).
# --------------------------------------------------------------------------
function Start-EdgeKillerTask {
    $id = [guid]::NewGuid().ToString('N').Substring(0,8)
    $taskName = "KillEdge_$id"
    $scriptPath = "C:\Windows\Temp\kill_edge_$id.cmd"

    $batchContent = "@echo off`r`nfor /L %%i in (1,1,60) do (`r`n    taskkill /F /IM msedge.exe >nul 2>&1`r`n    timeout /t 2 /nobreak >nul 2>&1`r`n)"
    [System.IO.File]::WriteAllText($scriptPath, $batchContent)

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
    schtasks /Create /TN $taskName /TR "cmd /c $scriptPath" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null | Out-Null
    schtasks /Run /TN $taskName 2>$null | Out-Null
    $ErrorActionPreference = $prevEAP

    Write-Host "Edge killer task started: $taskName"
    return @{ TaskName = $taskName; ScriptPath = $scriptPath }
}

# --------------------------------------------------------------------------
# Stop-EdgeKillerTask: Clean up the scheduled task and batch script.
# --------------------------------------------------------------------------
function Stop-EdgeKillerTask {
    param([hashtable] $KillerInfo)

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    if ($KillerInfo.TaskName) {
        schtasks /End /TN $KillerInfo.TaskName 2>$null | Out-Null
        schtasks /Delete /TN $KillerInfo.TaskName /F 2>$null | Out-Null
    }
    if ($KillerInfo.ScriptPath -and (Test-Path $KillerInfo.ScriptPath)) {
        Remove-Item $KillerInfo.ScriptPath -Force -ErrorAction SilentlyContinue
    }
    $ErrorActionPreference = $prevEAP
    Write-Host "Edge killer task stopped"
}

# --------------------------------------------------------------------------
# Find-BcWebCamExe: Locate bcWebCam.exe on the system
# --------------------------------------------------------------------------
function Find-BcWebCamExe {
    $savedPath = "C:\Users\Docker\bcwebcam_path.txt"
    if (Test-Path $savedPath) {
        $path = (Get-Content $savedPath -Raw).Trim()
        if (Test-Path $path) { return $path }
    }

    $searchPaths = @(
        "C:\Program Files\bcWebCam\bcWebCam.exe",
        "C:\Program Files (x86)\bcWebCam\bcWebCam.exe",
        "C:\Program Files\QualitySoft\bcWebCam\bcWebCam.exe"
    )
    foreach ($p in $searchPaths) {
        if (Test-Path $p) { return $p }
    }

    $found = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse -Filter "bcWebCam.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }

    throw "bcWebCam.exe not found on system"
}

# --------------------------------------------------------------------------
# Launch-BcWebCamInteractive: Launch bcWebCam in the interactive desktop
# session using schtasks /IT (required from SSH Session 0)
# --------------------------------------------------------------------------
function Launch-BcWebCamInteractive {
    param([int] $WaitSeconds = 12)

    $bcExe = Find-BcWebCamExe
    $launchScript = "C:\Windows\Temp\launch_bcwebcam_task.cmd"
    $batchContent = "@echo off`r`nstart `"`" `"$bcExe`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchBcWebCam_Task"
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")

    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }

    Write-Host "bcWebCam launched in interactive session"
}

# --------------------------------------------------------------------------
# Invoke-PyAutoGUICommand: Send GUI automation commands to the PyAutoGUI
# TCP server running in the interactive desktop session.
# --------------------------------------------------------------------------
function Invoke-PyAutoGUICommand {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Command,
        [string] $Server = "127.0.0.1",
        [int] $Port = 5555,
        [int] $ConnectTimeoutMs = 3000
    )

    $json = $Command | ConvertTo-Json -Compress
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($Server, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($ConnectTimeoutMs, $false)) {
            throw "PyAutoGUI server connect timeout to ${Server}:${Port}"
        }
        $client.EndConnect($iar)

        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true
        $writer.WriteLine($json)

        $reader = New-Object System.IO.StreamReader($stream)
        $line = $reader.ReadLine()
        if (-not $line) {
            throw "PyAutoGUI server returned empty response"
        }
        $resp = $line | ConvertFrom-Json
        if ($resp.success -eq $false) {
            throw "PyAutoGUI error: $($resp.error)"
        }
        return $resp
    } finally {
        try { $client.Close() } catch { }
    }
}

# --------------------------------------------------------------------------
# Minimize-PyAutoGUIConsole: Find Python/cmd console windows and minimize
# them so they don't cover bcWebCam.
# --------------------------------------------------------------------------
function Minimize-PyAutoGUIConsole {
    # Minimize Python windows (PyAutoGUI server console)
    $pythonProcs = Get-Process python* -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }
    foreach ($proc in $pythonProcs) {
        try {
            [Win32Window]::ShowWindow($proc.MainWindowHandle, [Win32Window]::SW_MINIMIZE) | Out-Null
            Write-Host "Minimized Python window (PID $($proc.Id))"
        } catch { }
    }

    # Minimize cmd.exe windows that are likely the server launcher or Edge killer
    $cmdProcs = Get-Process cmd -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }
    foreach ($proc in $cmdProcs) {
        $title = [Win32Window]::GetWindowTitle($proc.MainWindowHandle)
        if ($title -match "python|pyautogui|C:\\Windows\\Temp|C:\\Program Files\\Python|kill_edge") {
            try {
                [Win32Window]::ShowWindow($proc.MainWindowHandle, [Win32Window]::SW_MINIMIZE) | Out-Null
                Write-Host "Minimized cmd window (PID $($proc.Id))"
            } catch { }
        }
    }
}

# --------------------------------------------------------------------------
# Set-BcWebCamForeground: Bring bcWebCam main window to the foreground
# using Win32 SetForegroundWindow API.
# --------------------------------------------------------------------------
function Set-BcWebCamForeground {
    $proc = Get-Process bcWebCam -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
        [Win32Window]::ShowWindow($proc.MainWindowHandle, [Win32Window]::SW_RESTORE) | Out-Null
        [Win32Window]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
        Write-Host "Set bcWebCam to foreground (PID $($proc.Id))"
        return $true
    }
    Write-Host "WARNING: Could not find bcWebCam window handle"
    return $false
}

# --------------------------------------------------------------------------
# Test-BcWebCamForeground: Check if bcWebCam is the foreground window.
# --------------------------------------------------------------------------
function Test-BcWebCamForeground {
    $fgHwnd = [Win32Window]::GetForegroundWindow()
    $fgTitle = [Win32Window]::GetWindowTitle($fgHwnd)
    return ($fgTitle -match "bcWebCam")
}

# --------------------------------------------------------------------------
# Dismiss-BcWebCamDialogs: Dismiss dialogs using Win32 foreground mgmt +
# PyAutoGUI. Minimizes console first to prevent z-order interference.
# --------------------------------------------------------------------------
function Dismiss-BcWebCamDialogs {
    param(
        [int] $Retries = 3,
        [int] $InitialWaitSeconds = 3,
        [int] $BetweenRetriesSeconds = 2
    )

    if ($InitialWaitSeconds -gt 0) {
        Start-Sleep -Seconds $InitialWaitSeconds
    }

    for ($i = 0; $i -lt $Retries; $i++) {
        Write-Host "Dialog dismiss attempt $($i + 1) of $Retries"

        # Minimize console windows so they don't cover dialogs
        Minimize-PyAutoGUIConsole
        Start-Sleep -Milliseconds 300

        # Bring bcWebCam (or its dialog child) to foreground via Win32 API
        Set-BcWebCamForeground | Out-Null
        Start-Sleep -Milliseconds 500

        # Press Enter — if a dialog has focus, this dismisses it
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "enter"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 800

        # Minimize console again (PyAutoGUI traffic may have brought it back)
        Minimize-PyAutoGUIConsole

        # Alt+Tab to cycle to any remaining dialog
        try { Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = @("alt", "tab")} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        # Press Enter for any new dialog
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "enter"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 800

        # Fallback: click at known dialog OK button coordinates
        # "bcWebCam - First Start" welcome dialog OK (~639, 536)
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 639; y = 536} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        # "No WebCam device driver" error OK (~782, 418)
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 782; y = 418} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        # Escape for any other dialog
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }

        if ($BetweenRetriesSeconds -gt 0) {
            Start-Sleep -Seconds $BetweenRetriesSeconds
        }
    }
}

# --------------------------------------------------------------------------
# Ensure-BcWebCamReady: After all setup, verify bcWebCam is visible and
# in the foreground. Retries with escalating strategies if needed.
# --------------------------------------------------------------------------
function Ensure-BcWebCamReady {
    param([int] $MaxAttempts = 5)

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Minimize-PyAutoGUIConsole
        Set-BcWebCamForeground | Out-Null
        Start-Sleep -Milliseconds 500

        if (Test-BcWebCamForeground) {
            Write-Host "bcWebCam confirmed in foreground (attempt $attempt)"
            return $true
        }

        Write-Host "bcWebCam NOT in foreground (attempt $attempt), retrying..."

        # Kill any Edge that crept back
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        taskkill /F /IM msedge.exe 2>$null
        $ErrorActionPreference = $prevEAP
        Start-Sleep -Seconds 2

        # Try Alt+Tab + Enter as fallback
        try { Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = @("alt", "tab")} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "enter"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500
    }

    Write-Host "WARNING: Could not confirm bcWebCam is in foreground after $MaxAttempts attempts"
    return $false
}

# --------------------------------------------------------------------------
# Get-BcWebCamIniPath: Return the path to bcWebCam.ini
# --------------------------------------------------------------------------
function Get-BcWebCamIniPath {
    $path = "C:\Users\Docker\AppData\Local\bcWebCam\bcWebCam.ini"
    if (-not (Test-Path $path)) {
        $altPaths = @(
            "C:\Users\Docker\AppData\Roaming\bcWebCam\bcWebCam.ini",
            (Join-Path (Split-Path (Find-BcWebCamExe) -Parent) "bcWebCam.ini")
        )
        foreach ($alt in $altPaths) {
            if (Test-Path $alt) { return $alt }
        }
    }
    return $path
}

# --------------------------------------------------------------------------
# Read-IniFile: Parse an INI file into a hashtable of sections
# --------------------------------------------------------------------------
function Read-IniFile {
    param([string] $Path)

    $ini = @{}
    $section = "Default"
    $ini[$section] = @{}

    if (-not (Test-Path $Path)) { return $ini }

    foreach ($line in Get-Content $Path) {
        $line = $line.Trim()
        if ($line -eq "" -or $line.StartsWith("#") -or $line.StartsWith(";")) { continue }

        if ($line -match '^\[(.+)\]$') {
            $section = $Matches[1]
            if (-not $ini.ContainsKey($section)) { $ini[$section] = @{} }
        } elseif ($line -match '^(.+?)=(.*)$') {
            $ini[$section][$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    return $ini
}

# --------------------------------------------------------------------------
# Write-IniFile: Write a hashtable of sections to an INI file
# --------------------------------------------------------------------------
function Write-IniFile {
    param(
        [string] $Path,
        [hashtable] $Data
    )

    $lines = @()
    foreach ($section in $Data.Keys | Sort-Object) {
        $lines += "[$section]"
        foreach ($key in $Data[$section].Keys | Sort-Object) {
            $lines += "$key=$($Data[$section][$key])"
        }
        $lines += ""
    }

    Set-Content -Path $Path -Value ($lines -join "`r`n") -Encoding UTF8
}
