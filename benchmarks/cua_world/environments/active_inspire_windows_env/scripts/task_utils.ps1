# Shared utility functions for ActivInspire Windows environment tasks.

# ---- Paths ----
$Script:FlipchartsDir = "C:\Users\Docker\Documents\Flipcharts"
$Script:PicturesDir = "C:\Users\Docker\Pictures\ActivInspire"
$Script:DesktopDir = "C:\Users\Docker\Desktop"

function Find-ActivInspireExe {
    <#
    .SYNOPSIS
    Locates the ActivInspire executable.
    #>

    # Check saved path first
    $savedPath = "C:\Users\Docker\activinspire_path.txt"
    if (Test-Path $savedPath) {
        $candidate = (Get-Content $savedPath -Raw).Trim()
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    # Search known paths (Activ Software is the actual install location)
    $searchPaths = @(
        "C:\Program Files (x86)\Activ Software\Inspire\Inspire.exe",
        "C:\Program Files\Activ Software\Inspire\Inspire.exe",
        "C:\Program Files\Promethean\ActivInspire\Inspire.exe",
        "C:\Program Files (x86)\Promethean\ActivInspire\Inspire.exe",
        "C:\Program Files\ActivInspire\Inspire.exe",
        "C:\Program Files (x86)\ActivInspire\Inspire.exe"
    )
    foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            return $p
        }
    }

    # Broader search
    $found = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse `
        -Filter "Inspire.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        return $found.FullName
    }

    throw "Could not find ActivInspire executable"
}

function Launch-ActivInspireInteractive {
    <#
    .SYNOPSIS
    Launches ActivInspire in the interactive desktop session (Session 1) via schtasks.
    Must launch from the install directory for DLL dependencies.
    #>
    param(
        [string] $InspireExe = "",
        [int] $WaitSeconds = 20
    )

    if (-not $InspireExe) {
        $InspireExe = Find-ActivInspireExe
    }

    if (-not (Test-Path $InspireExe)) {
        throw "ActivInspire executable not found at: $InspireExe"
    }

    # Kill any existing instances first
    Close-ActivInspire

    # Must cd to install dir so ActivInspire can find its DLLs
    $inspireDir = Split-Path $InspireExe -Parent
    $launchScript = "C:\Windows\Temp\launch_activinspire.bat"
    $batchContent = "@echo off`r`ncd /d `"$inspireDir`"`r`nstart `"`" `"$InspireExe`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchActivInspire_GA"

    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN $taskName /TR $launchScript `
            /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }

    # Wait for window to appear
    Wait-ForActivInspireWindow -TimeoutSeconds 60

    # Dismiss any dialogs that appear
    Dismiss-ActivInspireDialogs
}

function Launch-ActivInspireWithFile {
    <#
    .SYNOPSIS
    Launches ActivInspire with a specific flipchart file in the interactive session.
    Must launch from the install directory for DLL dependencies.
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $FilePath,
        [int] $WaitSeconds = 20
    )

    $inspireExe = Find-ActivInspireExe
    $inspireDir = Split-Path $inspireExe -Parent

    # Kill any existing instances first
    Close-ActivInspire

    $launchScript = "C:\Windows\Temp\launch_activinspire_file.bat"
    $batchContent = "@echo off`r`ncd /d `"$inspireDir`"`r`nstart `"`" `"$inspireExe`" `"$FilePath`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchActivInspireFile_GA"

    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN $taskName /TR $launchScript `
            /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }

    Wait-ForActivInspireWindow -TimeoutSeconds 60
    Dismiss-ActivInspireDialogs
}

function Close-ActivInspire {
    <#
    .SYNOPSIS
    Cleanly closes all ActivInspire processes.
    #>
    $processNames = @("Inspire", "ActivInspire", "activinspire", "QtWebEngineProcess")
    foreach ($name in $processNames) {
        Get-Process $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

function Wait-ForActivInspireWindow {
    <#
    .SYNOPSIS
    Polls for an ActivInspire window to appear.
    #>
    param(
        [int] $TimeoutSeconds = 60
    )

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $procs = Get-Process -Name "Inspire", "ActivInspire", "activinspire" -ErrorAction SilentlyContinue
        if ($procs | Where-Object { $_.MainWindowTitle -ne "" }) {
            Write-Host "ActivInspire window detected"
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    Write-Host "WARNING: ActivInspire window not detected within ${TimeoutSeconds}s"
    return $false
}

function Test-ActivInspireRunning {
    <#
    .SYNOPSIS
    Checks if ActivInspire is currently running with a visible window.
    #>
    $procs = Get-Process -Name "Inspire", "ActivInspire", "activinspire" -ErrorAction SilentlyContinue
    return ($procs | Where-Object { $_.MainWindowTitle -ne "" }) -ne $null
}

function Ensure-ActivInspireRunning {
    <#
    .SYNOPSIS
    Ensures ActivInspire is running. Launches it if not already running.
    Retries up to 2 times.
    #>
    if (Test-ActivInspireRunning) {
        Write-Host "ActivInspire is already running"
        Dismiss-ActivInspireDialogs
        return
    }

    $maxAttempts = 2
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Write-Host "Starting ActivInspire (attempt $attempt of $maxAttempts)..."
        try {
            Launch-ActivInspireInteractive
            if (Test-ActivInspireRunning) {
                Write-Host "ActivInspire started successfully"
                return
            }
        } catch {
            Write-Host "Launch attempt $attempt failed: $_"
        }

        if ($attempt -lt $maxAttempts) {
            Write-Host "Retrying..."
            Start-Sleep -Seconds 5
        }
    }

    Write-Host "WARNING: ActivInspire may not have started after $maxAttempts attempts"
}

function Dismiss-ActivInspireDialogs {
    <#
    .SYNOPSIS
    Dismisses common ActivInspire first-run dialogs (EULA, registration, updates, welcome).
    Uses PyAutoGUI TCP server and keyboard shortcuts.
    #>

    # Try running the dedicated dismiss script
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        $prevEAP = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            & powershell -ExecutionPolicy Bypass -File $dismissScript 2>$null
        } finally {
            $ErrorActionPreference = $prevEAP
        }
    }

    # Also try generic dismissals via PyAutoGUI
    # Use Escape only (not Enter, which could trigger unwanted actions like update downloads)
    Start-Sleep -Seconds 2
    try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "escape"} } catch { }
    Start-Sleep -Seconds 1
    try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "escape"} } catch { }
    Start-Sleep -Seconds 1

    # Dismiss OneDrive notification if present (X button at approx 1238, 392)
    try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 1238; y = 392} } catch { }
    Start-Sleep -Seconds 1
}

# ---- PyAutoGUI Helper Functions ----

function Invoke-PyAutoGUICommand {
    <#
    .SYNOPSIS
    Sends a command to the PyAutoGUI TCP server running on port 5555.
    #>
    param(
        [Parameter(Mandatory = $true)] [hashtable] $Command,
        [string] $ServerHost = "127.0.0.1",
        [int] $Port = 5555,
        [int] $ConnectTimeoutMs = 3000
    )

    $json = $Command | ConvertTo-Json -Compress
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($ServerHost, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($ConnectTimeoutMs, $false)) {
            throw "PyAutoGUI server connection timeout"
        }
        $client.EndConnect($iar)

        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true
        $writer.WriteLine($json)

        $reader = New-Object System.IO.StreamReader($stream)
        $line = $reader.ReadLine()
        if (-not $line) { throw "Empty response from PyAutoGUI server" }
        $resp = $line | ConvertFrom-Json
        if ($resp.success -eq $false) {
            throw "PyAutoGUI error: $($resp.error)"
        }
        return $resp
    } finally {
        try { $client.Close() } catch { }
    }
}

function PyAutoGUI-Click {
    <#
    .SYNOPSIS
    Clicks at the given coordinates via PyAutoGUI server.
    Coordinates are in 1280x720 screen space.
    #>
    param(
        [Parameter(Mandatory = $true)] [int] $X,
        [Parameter(Mandatory = $true)] [int] $Y
    )
    Invoke-PyAutoGUICommand -Command @{action = "click"; x = $X; y = $Y}
}

function PyAutoGUI-DoubleClick {
    <#
    .SYNOPSIS
    Double-clicks at the given coordinates via PyAutoGUI server.
    #>
    param(
        [Parameter(Mandatory = $true)] [int] $X,
        [Parameter(Mandatory = $true)] [int] $Y
    )
    Invoke-PyAutoGUICommand -Command @{action = "doubleClick"; x = $X; y = $Y}
}

function PyAutoGUI-Press {
    <#
    .SYNOPSIS
    Presses a key via PyAutoGUI server.
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $Keys
    )
    Invoke-PyAutoGUICommand -Command @{action = "press"; keys = $Keys}
}

function PyAutoGUI-Type {
    <#
    .SYNOPSIS
    Types text via PyAutoGUI server.
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $Text
    )
    Invoke-PyAutoGUICommand -Command @{action = "typewrite"; text = $Text}
}

function PyAutoGUI-Hotkey {
    <#
    .SYNOPSIS
    Presses a hotkey combination via PyAutoGUI server.
    #>
    param(
        [Parameter(Mandatory = $true)] [string[]] $Keys
    )
    Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = $Keys}
}

function Minimize-TerminalWindows {
    <#
    .SYNOPSIS
    Minimizes all cmd.exe windows to keep the desktop clean.
    #>
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Min {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
    Get-Process cmd -ErrorAction SilentlyContinue | ForEach-Object {
        [Win32Min]::ShowWindow($_.MainWindowHandle, 6) | Out-Null
    }
}

# ---- Flipchart Utility Functions ----

function Test-FlipchartFile {
    <#
    .SYNOPSIS
    Checks if a flipchart file exists and appears valid.
    Flipchart files are ZIP archives containing XML.
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $FilePath
    )

    if (-not (Test-Path $FilePath)) {
        return $false
    }

    $fileInfo = Get-Item $FilePath
    return ($fileInfo.Length -gt 0)
}

function Get-FlipchartCount {
    <#
    .SYNOPSIS
    Counts flipchart files in a directory.
    #>
    param(
        [string] $Directory = $Script:FlipchartsDir
    )

    if (-not (Test-Path $Directory)) {
        return 0
    }

    $files = Get-ChildItem $Directory -Filter "*.flipchart" -ErrorAction SilentlyContinue
    $flpFiles = Get-ChildItem $Directory -Filter "*.flp" -ErrorAction SilentlyContinue
    return ($files.Count + $flpFiles.Count)
}
