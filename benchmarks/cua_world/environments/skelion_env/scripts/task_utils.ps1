# task_utils.ps1 — Shared utilities for Skelion environment tasks
# Source this file at the top of each setup_task.ps1

# -------------------------------------------------------------------
# Find-SketchUp: Locate the SketchUp.exe path
# -------------------------------------------------------------------
function Find-SketchUp {
    $savedPath = "C:\Users\Docker\sketchup_path.txt"
    if (Test-Path $savedPath) {
        $p = (Get-Content $savedPath -Raw).Trim()
        if (Test-Path $p) { return $p }
    }
    $found = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse -Filter "SketchUp.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "2017" } | Select-Object -First 1
    if ($found) { return $found.FullName }
    throw "SketchUp.exe not found"
}

# -------------------------------------------------------------------
# Launch-SketchUpInteractive: Launch SketchUp in the interactive VNC session
#   Uses schtasks /IT pattern (REQUIRED for GUI from Session 0/SSH)
#
#   CRITICAL: schtasks /TR cannot handle quoted paths with spaces reliably.
#   Solution: write a .bat wrapper and pass that to /TR instead.
#
#   Optionally pass a file to open: -FilePath "C:\path\to\file.skp"
# -------------------------------------------------------------------
function Launch-SketchUpInteractive {
    param(
        [string]$FilePath = "",
        [int]$WaitSeconds = 40,
        [string]$TaskName = "SketchUp_Task"
    )

    $suExe = Find-SketchUp

    # Kill any existing SketchUp processes before launching
    Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Write a batch file wrapper to avoid schtasks quoting issues with spaces in paths
    New-Item -ItemType Directory -Force -Path "C:\temp" | Out-Null
    $batPath = "C:\temp\launch_su_task.bat"
    if ($FilePath -ne "" -and (Test-Path $FilePath)) {
        Set-Content -Path $batPath -Value "@echo off`r`nstart `"`" `"$suExe`" `"$FilePath`"" -Encoding ASCII
    } else {
        Set-Content -Path $batPath -Value "@echo off`r`nstart `"`" `"$suExe`"" -Encoding ASCII
    }

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    schtasks /Delete /TN $TaskName /F 2>$null
    schtasks /Create /TN $TaskName /TR $batPath /SC ONCE /ST "00:00" /RL HIGHEST /IT /F 2>$null
    schtasks /Run    /TN $TaskName 2>$null

    Write-Host "SketchUp launched via schtasks (TaskName: $TaskName). Waiting ${WaitSeconds}s..."
    Start-Sleep -Seconds $WaitSeconds

    schtasks /Delete /TN $TaskName /F 2>$null
    $ErrorActionPreference = $prevEAP
}

# -------------------------------------------------------------------
# Wait-ForSketchUp: Poll until SketchUp process is running
# -------------------------------------------------------------------
function Wait-ForSketchUp {
    param([int]$TimeoutSec = 60)
    $elapsed = 0
    while ($elapsed -lt $TimeoutSec) {
        if (Get-Process SketchUp -ErrorAction SilentlyContinue) {
            Write-Host "SketchUp is running"
            return $true
        }
        Start-Sleep -Seconds 3
        $elapsed += 3
    }
    Write-Host "WARNING: SketchUp did not start within $TimeoutSec seconds"
    return $false
}

# -------------------------------------------------------------------
# Send-PyAutoGUICommand: Send a single JSON command to the PyAutoGUI TCP server
#   Returns the response string, or $null on failure
# -------------------------------------------------------------------
function Send-PyAutoGUICommand {
    param(
        [string]$Command,
        [int]$Port = 5555,
        [int]$TimeoutMs = 5000
    )
    try {
        $sock = New-Object System.Net.Sockets.TcpClient
        $iar  = $sock.BeginConnect("127.0.0.1", $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            $sock.EndConnect($iar)
            $stream = $sock.GetStream()
            $writer = New-Object System.IO.StreamWriter($stream)
            $writer.AutoFlush = $true
            $reader = New-Object System.IO.StreamReader($stream)
            $writer.WriteLine($Command)
            $response = $reader.ReadLine()
            $sock.Close()
            return $response
        }
        $sock.Close()
        return $null
    } catch {
        return $null
    }
}

# -------------------------------------------------------------------
# Dismiss-SketchUpDialogs: Click through dialogs that may appear after
#   opening Solar_Project.skp (task resets, not first launch).
#
#   On first launch (setup_sketchup_skelion.ps1), the Welcome screen,
#   Skelion EULA, and Skelion notification are dismissed there.
#   On subsequent task resets (opening an existing .skp directly),
#   only the 2D Bool plugin dialog may occasionally appear.
#   All coordinate clicks are safe on an open SketchUp workspace.
# -------------------------------------------------------------------
function Dismiss-SketchUpDialogs {
    param([int]$Retries = 3)

    for ($i = 0; $i -lt $Retries; $i++) {
        Write-Host "Dialog dismissal attempt $($i + 1)..."
        $r = Send-PyAutoGUICommand '{"action":"click","x":640,"y":400}'
        if ($r) {
            # Dismiss 2D Bool plugin dialog (close X at top-right of dialog)
            Send-PyAutoGUICommand '{"action":"click","x":277,"y":123}' | Out-Null
            Start-Sleep -Milliseconds 600
            # Dismiss Skelion EULA if unexpectedly shown (Accept at left side)
            Send-PyAutoGUICommand '{"action":"click","x":191,"y":396}' | Out-Null
            Start-Sleep -Milliseconds 600
            # Dismiss Skelion notification (OK button)
            Send-PyAutoGUICommand '{"action":"click","x":793,"y":326}' | Out-Null
            Start-Sleep -Milliseconds 600
            # Click workspace to clear focus
            Send-PyAutoGUICommand '{"action":"click","x":640,"y":400}' | Out-Null
            Write-Host "Dialog dismissal sequence sent"
            return
        }
        Start-Sleep -Seconds 3
    }
    Write-Host "WARNING: PyAutoGUI server unreachable for dialog dismissal"
}

# -------------------------------------------------------------------
# Ensure-SketchUpForeground: Bring the SketchUp window to the
#   foreground using Win32 API (SetForegroundWindow / ShowWindow).
#
#   This is necessary because the PyAutoGUI TCP server terminal window
#   may be covering SketchUp. Simply clicking at workspace coordinates
#   would hit the terminal instead. We run a small PowerShell script
#   via schtasks /IT (Session 1) that finds the SketchUp process and
#   forces its main window to the front.
# -------------------------------------------------------------------
function Ensure-SketchUpForeground {
    New-Item -ItemType Directory -Force -Path "C:\temp" | Out-Null

    # Write a PowerShell script that uses Win32 API to activate SketchUp
    $focusPs1 = "C:\temp\focus_sketchup.ps1"
    $focusContent = @'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
$p = Get-Process SketchUp -ErrorAction SilentlyContinue | Select-Object -First 1
if ($p -and $p.MainWindowHandle -ne [IntPtr]::Zero) {
    [WinAPI]::ShowWindow($p.MainWindowHandle, 9)
    [WinAPI]::SetForegroundWindow($p.MainWindowHandle)
}
'@
    [System.IO.File]::WriteAllText($focusPs1, $focusContent, [System.Text.Encoding]::UTF8)

    # Batch wrapper for schtasks (handles path quoting)
    $focusBat = "C:\temp\focus_sketchup.bat"
    Set-Content -Path $focusBat -Value "@echo off`r`npowershell -ExecutionPolicy Bypass -File C:\temp\focus_sketchup.ps1" -Encoding ASCII

    # Run in Session 1 via schtasks /IT
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    schtasks /Delete /TN "FocusSU" /F 2>$null
    schtasks /Create /TN "FocusSU" /TR $focusBat /SC ONCE /ST "00:00" /RL HIGHEST /IT /F 2>$null
    schtasks /Run    /TN "FocusSU" 2>$null
    Start-Sleep -Seconds 3
    schtasks /Delete /TN "FocusSU" /F 2>$null
    $ErrorActionPreference = $prevEAP

    Write-Host "SketchUp window activated via Win32 SetForegroundWindow"

    # Final click on SketchUp workspace to confirm focus
    Send-PyAutoGUICommand '{"action":"click","x":640,"y":400}' | Out-Null
    Start-Sleep -Milliseconds 500
}

# -------------------------------------------------------------------
# Close-Browsers: Kill Edge and any other browser processes
# -------------------------------------------------------------------
function Close-Browsers {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    taskkill /F /IM msedge.exe   2>$null
    taskkill /F /IM chrome.exe   2>$null
    taskkill /F /IM firefox.exe  2>$null
    Start-Sleep -Seconds 1
    $ErrorActionPreference = $prevEAP
}

# -------------------------------------------------------------------
# Reset-SketchUpModel: Kill SketchUp, relaunch with Solar_Project.skp,
#   dismiss any dialogs, leave SketchUp in ready state.
#
#   WaitAfterLaunch: seconds to wait after launch before dismissing dialogs.
#   40s is sufficient when opening an existing .skp file (no Welcome screen).
# -------------------------------------------------------------------
function Reset-SketchUpModel {
    param([int]$WaitAfterLaunch = 40)

    $projectFile = "C:\Users\Docker\Desktop\Solar_Project.skp"

    Write-Host "--- Resetting SketchUp with Solar_Project.skp ---"

    # Kill existing SketchUp
    Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Launch with the project file
    Launch-SketchUpInteractive -FilePath $projectFile -WaitSeconds $WaitAfterLaunch

    # Dismiss any residual dialogs
    Dismiss-SketchUpDialogs

    # Bring SketchUp to foreground / confirm focus
    Ensure-SketchUpForeground

    Write-Host "SketchUp is ready with Solar_Project.skp"
}

# -------------------------------------------------------------------
# Verify-SolarProjectExists: Ensure the building model file exists.
#   If missing, triggers a fresh SketchUp launch so the Ruby plugin
#   can auto-create it.
# -------------------------------------------------------------------
function Verify-SolarProjectExists {
    $projectFile = "C:\Users\Docker\Desktop\Solar_Project.skp"
    if (Test-Path $projectFile) { return $true }

    Write-Host "WARNING: Solar_Project.skp not found. Launching SketchUp to recreate..."

    # Delete the creation flag so the Ruby script will re-run
    Remove-Item "C:\Users\Docker\solar_project_created.flag" -Force -ErrorAction SilentlyContinue

    Launch-SketchUpInteractive -WaitSeconds 60
    Dismiss-SketchUpDialogs

    # Wait for Ruby timer
    for ($w = 0; $w -lt 12; $w++) {
        if (Test-Path $projectFile) {
            Write-Host "Solar_Project.skp created"
            break
        }
        Start-Sleep -Seconds 5
    }

    # Close SketchUp
    Send-PyAutoGUICommand '{"action":"hotkey","keys":["ctrl","s"]}' | Out-Null
    Start-Sleep -Seconds 2
    Send-PyAutoGUICommand '{"action":"hotkey","keys":["alt","F4"]}' | Out-Null
    Start-Sleep -Seconds 3
    Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    return (Test-Path $projectFile)
}
