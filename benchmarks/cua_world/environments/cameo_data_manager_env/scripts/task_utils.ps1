# ============================================================
# Shared task utilities for CAMEO Data Manager environment
# ============================================================

Set-StrictMode -Version Latest

# --- Win32 Window Management ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class Win32Window {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    public const int SW_MINIMIZE = 6;
    public const int SW_RESTORE = 9;
    public const int SW_MAXIMIZE = 3;

    public static string GetTitle(IntPtr hWnd) {
        StringBuilder sb = new StringBuilder(256);
        GetWindowText(hWnd, sb, 256);
        return sb.ToString();
    }
}
"@

# --- Find CAMEO Executable ---
function Find-CAMEOExe {
    $savedPath = "C:\Users\Docker\cameo_path.txt"
    if (Test-Path $savedPath) {
        $path = (Get-Content $savedPath -Raw).Trim()
        if (Test-Path $path) { return $path }
    }

    # Check known install paths with version suffix
    $knownPaths = @(
        "C:\Program Files (x86)\CAMEO Data Manager 4.5.1\CAMEO Data Manager.exe",
        "C:\Program Files\CAMEO Data Manager 4.5.1\CAMEO Data Manager.exe",
        "C:\Program Files (x86)\CAMEO Data Manager\CAMEO Data Manager.exe",
        "C:\Program Files\CAMEO Data Manager\CAMEO Data Manager.exe"
    )

    foreach ($path in $knownPaths) {
        if (Test-Path $path) { return $path }
    }

    # Broad search
    $found = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse -Filter "CAMEO Data Manager.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) { return $found.FullName }

    throw "CAMEO Data Manager executable not found"
}

# --- PyAutoGUI TCP Command ---
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
            throw "PyAutoGUI server connect timeout"
        }
        $client.EndConnect($iar)

        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true
        $writer.WriteLine($json)

        $reader = New-Object System.IO.StreamReader($stream)
        $resp = $reader.ReadLine() | ConvertFrom-Json
        if ($resp.success -eq $false) {
            throw "PyAutoGUI error: $($resp.error)"
        }
        return $resp
    } finally {
        $client.Close()
    }
}

# --- Launch CAMEO in Interactive Session ---
function Launch-CAMEOInteractive {
    param([int] $WaitSeconds = 15)

    $cameoExe = Find-CAMEOExe

    # Kill any existing instances
    $ErrorActionPreference = "Continue"
    Get-Process | Where-Object {
        $_.ProcessName -like "*CAMEO*" -or $_.ProcessName -like "*cameo*" -or $_.ProcessName -like "*DataManager*"
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $ErrorActionPreference = "Stop"

    # Create VBScript launcher (invisible — no cmd.exe window)
    $launchVbs = "C:\Windows\Temp\launch_cameo_task.vbs"
    $vbsContent = "CreateObject(`"Wscript.Shell`").Run `"`"`"$cameoExe`"`"`", 1, False"
    [System.IO.File]::WriteAllText($launchVbs, $vbsContent)

    # Schedule in interactive session
    $taskName = "LaunchCAMEO_Task"
    $ErrorActionPreference = "Continue"
    schtasks /Delete /TN $taskName /F 2>$null | Out-Null
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
    schtasks /Create /TN $taskName /TR "wscript.exe $launchVbs" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null | Out-Null
    schtasks /Run /TN $taskName 2>$null | Out-Null
    $ErrorActionPreference = "Stop"

    Write-Host "Waiting $WaitSeconds seconds for CAMEO to start..."
    Start-Sleep -Seconds $WaitSeconds

    # Clean up scheduled task and launcher
    $ErrorActionPreference = "Continue"
    schtasks /Delete /TN $taskName /F 2>$null | Out-Null
    Remove-Item $launchVbs -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = "Stop"
}

# --- Start Edge Killer Background Task ---
function Start-EdgeKillerTask {
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $taskName = "KillEdge_$id"
    $batchPath = "C:\Windows\Temp\kill_edge_$id.cmd"
    $vbsPath = "C:\Windows\Temp\kill_edge_$id.vbs"

    $batchContent = "@echo off`r`nfor /L %%i in (1,1,60) do (`r`n    taskkill /F /IM msedge.exe >nul 2>&1`r`n    timeout /t 2 /nobreak >nul 2>&1`r`n)"
    [System.IO.File]::WriteAllText($batchPath, $batchContent)

    # VBScript wrapper runs the batch hidden (window style 0)
    $vbsContent = "CreateObject(`"Wscript.Shell`").Run `"cmd /c $batchPath`", 0, False"
    [System.IO.File]::WriteAllText($vbsPath, $vbsContent)

    $ErrorActionPreference = "Continue"
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
    schtasks /Create /TN $taskName /TR "wscript.exe $vbsPath" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null | Out-Null
    schtasks /Run /TN $taskName 2>$null | Out-Null
    $ErrorActionPreference = "Stop"

    return @{ TaskName = $taskName; BatchPath = $batchPath; VbsPath = $vbsPath }
}

# --- Stop Edge Killer Task ---
function Stop-EdgeKillerTask {
    param([hashtable] $KillerInfo)

    if ($KillerInfo) {
        $ErrorActionPreference = "Continue"
        schtasks /Delete /TN $KillerInfo.TaskName /F 2>$null | Out-Null
        Remove-Item $KillerInfo.BatchPath -Force -ErrorAction SilentlyContinue
        Remove-Item $KillerInfo.VbsPath -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = "Stop"
    }
}

# --- Close Browsers ---
function Close-Browsers {
    $ErrorActionPreference = "Continue"
    taskkill /F /IM msedge.exe 2>$null
    taskkill /F /IM chrome.exe 2>$null
    taskkill /F /IM firefox.exe 2>$null
    $ErrorActionPreference = "Stop"
    Start-Sleep -Seconds 1
}

# --- Dismiss CAMEO Dialogs ---
function Dismiss-CAMEODialogs {
    param(
        [int] $Retries = 3,
        [int] $BetweenRetriesSeconds = 2
    )

    for ($i = 0; $i -lt $Retries; $i++) {
        Write-Host "  Dialog dismissal attempt $($i + 1)..."

        # Press Escape to close any modal dialog
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "escape"} } catch { }
        Start-Sleep -Milliseconds 800

        # Press Enter as fallback
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "enter"} } catch { }
        Start-Sleep -Seconds $BetweenRetriesSeconds
    }

    # Dismiss OneDrive "Turn On Windows Backup" popup if present (can reappear after checkpoint restore)
    Write-Host "  Dismissing OneDrive popup if present..."
    try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 1135; y = 627} } catch { }
    Start-Sleep -Seconds 1
}

# --- Ensure CAMEO Is Ready (foreground, no dialogs) ---
function Ensure-CAMEOReady {
    param([int] $MaxAttempts = 5)

    for ($i = 0; $i -lt $MaxAttempts; $i++) {
        # Try Alt+Tab to bring CAMEO to foreground
        try { Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = @("alt", "tab")} } catch { }
        Start-Sleep -Seconds 1

        # Check if any CAMEO process is running
        $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -like "*CAMEO*" -or $_.ProcessName -like "*cameo*" -or $_.ProcessName -like "*DataManager*"
        }
        if ($procs) {
            Write-Host "CAMEO process found: $($procs[0].ProcessName) (PID: $($procs[0].Id))"
            return $true
        }

        Write-Host "  CAMEO not found, attempt $($i + 1)/$MaxAttempts"
        Start-Sleep -Seconds 2
    }

    Write-Host "WARNING: Could not confirm CAMEO is running"
    return $false
}

# --- Copy Tier II Data to Working Directory ---
function Copy-TierIIData {
    param(
        [string] $SourceDir = "C:\workspace\data",
        [string] $DestDir = "C:\Users\Docker\Documents\CAMEO"
    )

    if (-not (Test-Path $DestDir)) {
        New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    }

    if (Test-Path "$SourceDir\epcra_tier2_data.xml") {
        Copy-Item "$SourceDir\epcra_tier2_data.xml" "$DestDir\epcra_tier2_data.xml" -Force
        Write-Host "Tier II data copied to $DestDir"
    }
}

# --- Suppress OneDrive Popup ---
function Suppress-OneDrive {
    Write-Host "Suppressing OneDrive..."
    $ErrorActionPreference = "Continue"

    # Kill OneDrive process
    Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # Disable OneDrive via Group Policy registry key
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $policyPath)) {
        New-Item -Path $policyPath -Force | Out-Null
    }
    New-ItemProperty -Path $policyPath -Name "DisableFileSyncNGSC" -Value 1 -PropertyType DWord -Force | Out-Null

    # Remove OneDrive from startup
    $startupKey = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $startupKey -Name "OneDrive" -Force -ErrorAction SilentlyContinue

    # Click dismiss on any existing popup (coordinates for "No thanks" button at 1280x720)
    try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 1135; y = 627} } catch { }
    Start-Sleep -Seconds 1

    $ErrorActionPreference = "Stop"
    Write-Host "OneDrive suppression complete"
}

# --- Import Tier II Data Into CAMEO Via GUI Automation ---
function Import-TierIIData {
    param(
        [string] $XmlPath = "C:\Users\Docker\Documents\CAMEO\epcra_tier2_data.xml"
    )

    Write-Host "=== Auto-importing Tier II data ==="

    # Ensure data file exists
    if (-not (Test-Path $XmlPath)) {
        Copy-TierIIData
    }
    if (-not (Test-Path $XmlPath)) {
        Write-Host "ERROR: Tier II data file not found at $XmlPath"
        return $false
    }

    # Click Import button on toolbar (~1001, 54)
    Write-Host "  Clicking Import button..."
    try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 1001; y = 54} } catch {
        Write-Host "  ERROR: Failed to click Import button: $_"
        return $false
    }
    Start-Sleep -Seconds 3

    # Click "Browse To File" button (~237, 369)
    Write-Host "  Clicking Browse To File..."
    try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 237; y = 369} } catch {
        Write-Host "  ERROR: Failed to click Browse To File: $_"
        return $false
    }
    Start-Sleep -Seconds 3

    # Click in the file name field (~345, 442) and type the path
    Write-Host "  Typing file path..."
    try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 345; y = 442} } catch { }
    Start-Sleep -Milliseconds 500
    try { Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = @("ctrl", "a")} } catch { }
    Start-Sleep -Milliseconds 300
    try { Invoke-PyAutoGUICommand -Command @{action = "typewrite"; text = $XmlPath} } catch {
        Write-Host "  ERROR: Failed to type file path: $_"
        return $false
    }
    Start-Sleep -Seconds 2

    # Click Select button (~510, 472)
    Write-Host "  Clicking Select..."
    try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 510; y = 472} } catch { }
    Start-Sleep -Seconds 3

    # Click Continue on file-selected screen (~577, 582)
    Write-Host "  Clicking Continue (file selected)..."
    try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 577; y = 582} } catch { }
    Start-Sleep -Seconds 3

    # Click Continue on Import File Information screen (~577, 614)
    Write-Host "  Clicking Continue (import file info)..."
    try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 577; y = 614} } catch { }
    Start-Sleep -Seconds 5

    # Click OK on Import Summary (~640, 421)
    Write-Host "  Clicking OK (import summary)..."
    try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 640; y = 421} } catch { }
    Start-Sleep -Seconds 2

    Write-Host "=== Tier II data import complete ==="
    return $true
}
