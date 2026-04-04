# ==========================================================================
# task_utils.ps1 - Shared utility functions for Epi Info 7 environment tasks
# ==========================================================================

Set-StrictMode -Version Latest

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
    public static extern bool BringWindowToTop(IntPtr hWnd);

    public const int SW_MINIMIZE = 6;
    public const int SW_RESTORE = 9;
    public const int SW_MAXIMIZE = 3;

    public static string GetWindowTitle(IntPtr hWnd) {
        StringBuilder sb = new StringBuilder(512);
        GetWindowText(hWnd, sb, 512);
        return sb.ToString();
    }
}
"@

# --------------------------------------------------------------------------
# Find-EpiInfoLauncher: Locate the Epi Info 7 launcher executable
# --------------------------------------------------------------------------
function Find-EpiInfoLauncher {
    $savedPath = "C:\Users\Docker\epi_info_launcher_path.txt"
    if (Test-Path $savedPath) {
        $path = (Get-Content $savedPath -Raw).Trim()
        if (Test-Path $path) { return $path }
    }

    $knownPaths = @(
        "C:\EpiInfo7\Launch Epi Info 7.exe",
        "C:\EpiInfo7\Analysis.exe",
        "C:\EpiInfo7\EpiInfo7Launcher.exe",
        "C:\EpiInfo7\EpiInfo7.exe",
        "C:\Program Files\CDC\Epi Info 7\EpiInfo7Launcher.exe",
        "C:\Program Files (x86)\CDC\Epi Info 7\EpiInfo7Launcher.exe"
    )
    foreach ($p in $knownPaths) {
        if (Test-Path $p) { return $p }
    }

    $found = Get-ChildItem "C:\EpiInfo7" -Recurse -Filter "Launch Epi Info 7.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    $found = Get-ChildItem "C:\EpiInfo7" -Recurse -Filter "EpiInfo7Launcher.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    $found = Get-ChildItem "C:\EpiInfo7" -Recurse -Filter "Analysis.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }

    throw "Epi Info 7 launcher not found on system"
}

# --------------------------------------------------------------------------
# Find-EcoliPrj: Locate the EColi.PRJ sample dataset file
# --------------------------------------------------------------------------
function Find-EcoliPrj {
    $savedPath = "C:\Users\Docker\ecoli_prj_path.txt"
    if (Test-Path $savedPath) {
        $path = (Get-Content $savedPath -Raw).Trim()
        if (Test-Path $path) { return $path }
    }

    $found = Get-ChildItem "C:\EpiInfo7" -Recurse -Include "EColi.prj","EColi.PRJ" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }

    throw "EColi.PRJ not found. Epi Info 7 may not have been installed correctly."
}

# --------------------------------------------------------------------------
# Close-Browsers: Kill Edge and other browsers
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

        $edgeUserData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
        if (Test-Path $edgeUserData) {
            Get-ChildItem $edgeUserData -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                foreach ($f in @("Current Session","Current Tabs","Last Session","Last Tabs")) {
                    Remove-Item (Join-Path $_.FullName $f) -Force -ErrorAction SilentlyContinue
                }
            }
        }

        $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
        if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force 2>$null | Out-Null }
        New-ItemProperty -Path $regPath -Name "StartupBoostEnabled" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
        New-ItemProperty -Path $regPath -Name "BackgroundModeEnabled" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
        New-ItemProperty -Path $regPath -Name "RestoreOnStartup" -Value 5 -PropertyType DWord -Force 2>$null | Out-Null

        Start-Sleep -Seconds 1
        taskkill /F /IM msedge.exe 2>$null
    } finally {
        $ErrorActionPreference = $prevEAP
    }
}

# --------------------------------------------------------------------------
# Start-EdgeKillerTask: Create a scheduled task that kills Edge every 2s
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
# Stop-EdgeKillerTask: Clean up the scheduled task and batch script
# --------------------------------------------------------------------------
function Stop-EdgeKillerTask {
    param([hashtable] $KillerInfo)

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    if ($KillerInfo -and $KillerInfo.TaskName) {
        schtasks /End /TN $KillerInfo.TaskName 2>$null | Out-Null
        schtasks /Delete /TN $KillerInfo.TaskName /F 2>$null | Out-Null
    }
    if ($KillerInfo -and $KillerInfo.ScriptPath -and (Test-Path $KillerInfo.ScriptPath)) {
        Remove-Item $KillerInfo.ScriptPath -Force -ErrorAction SilentlyContinue
    }
    $ErrorActionPreference = $prevEAP
    Write-Host "Edge killer task stopped"
}

# --------------------------------------------------------------------------
# Launch-EpiInfoInteractive: Launch Epi Info 7 in the interactive session
# using schtasks /IT (required from SSH Session 0)
# --------------------------------------------------------------------------
function Launch-EpiInfoInteractive {
    param([int] $WaitSeconds = 20)

    $launcherExe = Find-EpiInfoLauncher
    $launchDir = Split-Path $launcherExe -Parent
    $launchScript = "C:\Windows\Temp\launch_epi_info_task.cmd"
    $batchContent = "@echo off`r`ncd /d `"$launchDir`"`r`nstart `"`" `"$launcherExe`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchEpiInfo_Task"
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")

    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Write-Host "Epi Info 7 launched. Waiting $WaitSeconds seconds for startup..."
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }

    Write-Host "Epi Info 7 launched in interactive session"
}

# --------------------------------------------------------------------------
# Launch-EpiInfoModuleInteractive: Launch a specific Epi Info module directly
# in the interactive session (bypasses the hub)
# Module examples: "Analysis.exe", "Enter.exe", "StatCalc.exe"
# --------------------------------------------------------------------------
function Launch-EpiInfoModuleInteractive {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ModuleExe,
        [int] $WaitSeconds = 15
    )

    $exePath = "C:\EpiInfo7\$ModuleExe"
    if (-not (Test-Path $exePath)) {
        throw "Epi Info module not found: $exePath"
    }
    $launchDir = "C:\EpiInfo7"
    $launchScript = "C:\Windows\Temp\launch_epi_module.cmd"
    $batchContent = "@echo off`r`ncd /d `"$launchDir`"`r`nstart `"`" `"$exePath`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchEpiModule_Task"
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")

    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Write-Host "$ModuleExe launched. Waiting $WaitSeconds seconds for startup..."
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }
    Write-Host "Epi Info module $ModuleExe launched in interactive session"
}

# --------------------------------------------------------------------------
# Stop-EpiInfo: Kill all Epi Info 7 processes
# --------------------------------------------------------------------------
function Stop-EpiInfo {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    # Kill all Epi Info related processes (hub, modules, and any legacy names)
    Get-Process "EpiInfo7*","EpiInfo*","Analysis","Enter","StatCalc","MakeView","Mapping","Menu","AnalysisDashboard" -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like "*EpiInfo*" -or $_.Path -like "*Epi Info*" -or $_.ProcessName -like "EpiInfo*" } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    # Also kill by C:\EpiInfo7 path
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -like "C:\EpiInfo7\*"
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $ErrorActionPreference = $prevEAP
    Write-Host "Epi Info 7 processes stopped"
}

# --------------------------------------------------------------------------
# Invoke-PyAutoGUICommand: Send GUI automation commands to the PyAutoGUI
# TCP server running in the interactive desktop session (port 5555)
# --------------------------------------------------------------------------
function Invoke-PyAutoGUICommand {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Command,
        [string] $Server = "127.0.0.1",
        [int] $Port = 5555,
        [int] $ConnectTimeoutMs = 5000
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
        if (-not $line) { throw "PyAutoGUI server returned empty response" }
        $resp = $line | ConvertFrom-Json
        if ($resp.success -eq $false) { throw "PyAutoGUI error: $($resp.error)" }
        return $resp
    } finally {
        try { $client.Close() } catch { }
    }
}

# --------------------------------------------------------------------------
# Set-EpiInfoForeground: Bring the Epi Info 7 main window to foreground
# --------------------------------------------------------------------------
function Set-EpiInfoForeground {
    # Include direct module process names (Analysis, Enter, StatCalc) as well as hub names
    $epiProcs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        ($_.ProcessName -match "^(EpiInfo|Analysis|Enter|StatCalc|MakeView|Mapping|Menu)$" -or $_.ProcessName -like "EpiInfo*") -and
        $_.MainWindowHandle -ne [IntPtr]::Zero -and
        ($_.Path -like "C:\EpiInfo7\*" -or $_.Path -like "*Epi Info*" -or $_.ProcessName -like "EpiInfo*")
    }
    foreach ($proc in $epiProcs) {
        try {
            [Win32Window]::ShowWindow($proc.MainWindowHandle, [Win32Window]::SW_RESTORE) | Out-Null
            [Win32Window]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
            [Win32Window]::BringWindowToTop($proc.MainWindowHandle) | Out-Null
            Write-Host "Set Epi Info to foreground (PID $($proc.Id), title: $([Win32Window]::GetWindowTitle($proc.MainWindowHandle)))"
            return $true
        } catch { }
    }
    Write-Host "WARNING: Could not find Epi Info window handle"
    return $false
}

# --------------------------------------------------------------------------
# Minimize-ConsoleWindows: Minimize Python/cmd console windows
# --------------------------------------------------------------------------
function Minimize-ConsoleWindows {
    $pythonProcs = Get-Process python* -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }
    foreach ($proc in $pythonProcs) {
        try { [Win32Window]::ShowWindow($proc.MainWindowHandle, [Win32Window]::SW_MINIMIZE) | Out-Null } catch { }
    }
    $cmdProcs = Get-Process cmd -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }
    foreach ($proc in $cmdProcs) {
        try { [Win32Window]::ShowWindow($proc.MainWindowHandle, [Win32Window]::SW_MINIMIZE) | Out-Null } catch { }
    }
}

# --------------------------------------------------------------------------
# Dismiss-EpiInfoDialogs: Dismiss any dialogs that appear on Epi Info launch
# (license dialog, update check dialog, splash screens)
# --------------------------------------------------------------------------
function Dismiss-EpiInfoDialogs {
    param([int] $Retries = 4, [int] $WaitSeconds = 3)

    Start-Sleep -Seconds $WaitSeconds

    for ($i = 0; $i -lt $Retries; $i++) {
        Write-Host "Dialog dismiss attempt $($i + 1)/$Retries"
        Minimize-ConsoleWindows

        # Try pressing Escape to dismiss
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 400

        # Try pressing Enter to accept/OK dialog
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "enter"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 400

        # Tab + Enter pattern for dialogs with focus on a button
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "tab"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 200
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "enter"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 400

        # Space bar to click focused button
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "space"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 400

        Start-Sleep -Seconds 2
    }
}

# --------------------------------------------------------------------------
# Ensure-EpiInfoReady: Verify Epi Info is visible and in foreground
# --------------------------------------------------------------------------
function Ensure-EpiInfoReady {
    param([int] $MaxAttempts = 5)

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Minimize-ConsoleWindows
        $result = Set-EpiInfoForeground
        Start-Sleep -Milliseconds 500

        $fgHwnd = [Win32Window]::GetForegroundWindow()
        $fgTitle = [Win32Window]::GetWindowTitle($fgHwnd)

        if ($fgTitle -match "Epi Info" -or $fgTitle -match "EpiInfo" -or $fgTitle -match "Classic Analysis" -or $fgTitle -match "StatCalc" -or $fgTitle -match "Enter") {
            Write-Host "Epi Info confirmed in foreground (attempt $attempt): $fgTitle"
            return $true
        }

        Write-Host "Epi Info NOT in foreground (attempt $attempt), fg title: $fgTitle"

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        taskkill /F /IM msedge.exe 2>$null
        $ErrorActionPreference = $prevEAP
        Start-Sleep -Seconds 2
    }

    Write-Host "WARNING: Could not confirm Epi Info is in foreground"
    return $false
}
