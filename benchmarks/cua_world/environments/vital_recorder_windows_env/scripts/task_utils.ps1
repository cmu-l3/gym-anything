# task_utils.ps1 - Shared utility functions for Vital Recorder tasks
# IMPORTANT: Vital Recorder installs to AppData\Roaming\VitalRecorder\
# The main executable is Vital.exe (NOT VitalRecorder.exe)
# Process name in Task Manager: Vital

# Find the Vital Recorder executable
function Find-VitalRecorderExe {
    # Primary path: AppData\Roaming (where MSI installs)
    $primaryPath = "C:\Users\Docker\AppData\Roaming\VitalRecorder\Vital.exe"
    if (Test-Path $primaryPath) {
        return $primaryPath
    }

    # Fallback paths
    $fallbackPaths = @(
        "C:\Program Files\VitalRecorder\Vital.exe",
        "C:\Program Files (x86)\VitalRecorder\Vital.exe",
        "C:\Program Files\Vital Recorder\Vital.exe"
    )
    foreach ($p in $fallbackPaths) {
        if (Test-Path $p) { return $p }
    }

    throw "Vital.exe not found. Expected at: $primaryPath"
}

# Launch Vital Recorder in the interactive desktop session using schtasks /IT
function Launch-VitalRecorderInteractive {
    param(
        [string]$VitalRecorderExe,
        [string]$FileToOpen = "",
        [int]$WaitSeconds = 15
    )

    $launchScript = "C:\Windows\Temp\launch_vitalrecorder.cmd"

    if ($FileToOpen -and (Test-Path $FileToOpen)) {
        $batchContent = "@echo off`r`nstart `"`" `"$VitalRecorderExe`" `"$FileToOpen`""
    } else {
        $batchContent = "@echo off`r`nstart `"`" `"$VitalRecorderExe`""
    }

    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchVitalRecorder_GA"
    $schedTime = (Get-Date).AddMinutes(1).ToString("HH:mm")

    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        schtasks /Delete /TN $taskName /F 2>$null
        schtasks /Create /TN $taskName /TR "cmd /c `"$launchScript`"" /SC ONCE /ST $schedTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }
}

# Launch a script in the interactive session using schtasks /IT
function Run-InteractiveScript {
    param(
        [string]$ScriptPath,
        [string]$TaskName = "RunScript_GA",
        [int]$WaitSeconds = 15
    )

    $schedTime = (Get-Date).AddMinutes(1).ToString("HH:mm")

    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        schtasks /Delete /TN $TaskName /F 2>$null
        schtasks /Create /TN $TaskName /TR "powershell -ExecutionPolicy Bypass -File `"$ScriptPath`"" /SC ONCE /ST $schedTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $TaskName 2>$null
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $TaskName /F 2>$null
        $ErrorActionPreference = $prevEAP
    }
}

# Click at coordinates using Win32 API (works for most Windows apps from Session 0)
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
    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
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

# Send keystrokes using SendKeys
function Send-Keys {
    param([string]$Keys)
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
    Start-Sleep -Milliseconds 300
}

# Check if Vital Recorder process is running (process name is "Vital", not "VitalRecorder")
function Test-VitalRecorderRunning {
    $proc = Get-Process -Name "Vital" -ErrorAction SilentlyContinue | Select-Object -First 1
    return ($null -ne $proc)
}

# Wait for Vital Recorder window to appear
function Wait-ForVitalRecorder {
    param([int]$TimeoutSeconds = 30)

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        if (Test-VitalRecorderRunning) {
            Write-Host "Vital Recorder is running (waited ${elapsed}s)"
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    Write-Host "WARNING: Vital Recorder not detected after ${TimeoutSeconds}s"
    return $false
}
