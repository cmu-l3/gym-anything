Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Setup script for Crimson HMI environment.
# This script runs after Windows boots (post_start hook).

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up Crimson HMI environment ==="

    # Create working directory on Desktop
    $TasksDir = "C:\Users\Docker\Desktop\CrimsonTasks"
    New-Item -ItemType Directory -Force -Path $TasksDir | Out-Null

    # Create a projects directory for Crimson project files
    $ProjectsDir = "C:\Users\Docker\Documents\CrimsonProjects"
    New-Item -ItemType Directory -Force -Path $ProjectsDir | Out-Null

    # Copy data files from workspace to Desktop for easy access
    if (Test-Path "C:\workspace\data") {
        Copy-Item "C:\workspace\data\*" -Destination $TasksDir -Force -ErrorAction SilentlyContinue
        Write-Host "Data files copied to: $TasksDir"
    }

    # Copy data files also to Documents for Crimson project reference
    if (Test-Path "C:\workspace\data") {
        Copy-Item "C:\workspace\data\*" -Destination $ProjectsDir -Force -ErrorAction SilentlyContinue
        Write-Host "Data files also copied to: $ProjectsDir"
    }

    # Aggressively disable OneDrive
    Write-Host "Disabling OneDrive..."
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process OneDriveSetup -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    # Remove from startup
    $onedrivePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $onedrivePath -Name "OneDrive" -ErrorAction SilentlyContinue
    # Disable via Group Policy
    $onedrivePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $onedrivePolicyPath)) {
        New-Item -Path $onedrivePolicyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $onedrivePolicyPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force
    # Uninstall OneDrive silently (non-blocking)
    $oneDriveSetup = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    if (-not (Test-Path $oneDriveSetup)) {
        $oneDriveSetup = "$env:SystemRoot\System32\OneDriveSetup.exe"
    }
    if (Test-Path $oneDriveSetup) {
        $proc = Start-Process $oneDriveSetup -ArgumentList "/uninstall" -PassThru -ErrorAction SilentlyContinue
        if ($proc) {
            $finished = $proc.WaitForExit(30000)
            if ($finished) {
                Write-Host "OneDrive uninstalled."
            } else {
                Write-Host "OneDrive uninstall still running (continuing)."
            }
        }
    }

    # Disable Windows Backup notifications and consumer features
    $backupPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $backupPath)) {
        New-Item -Path $backupPath -Force | Out-Null
    }
    Set-ItemProperty -Path $backupPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $backupPath -Name "DisableSoftLanding" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $backupPath -Name "DisableCloudOptimizedContent" -Value 1 -Type DWord -Force

    # Disable Windows Backup prompts via Settings policy
    $backupSettingsPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsBackup"
    if (-not (Test-Path $backupSettingsPath)) {
        New-Item -Path $backupSettingsPath -Force | Out-Null
    }
    Set-ItemProperty -Path $backupSettingsPath -Name "DisableBackupUI" -Value 1 -Type DWord -Force

    # Disable toast notifications from Windows to reduce popups
    $toastPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications"
    if (-not (Test-Path $toastPath)) {
        New-Item -Path $toastPath -Force | Out-Null
    }
    Set-ItemProperty -Path $toastPath -Name "ToastEnabled" -Value 0 -Type DWord -Force

    # Disable notification center suggestions
    $suggestionsPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    if (-not (Test-Path $suggestionsPath)) {
        New-Item -Path $suggestionsPath -Force | Out-Null
    }
    Set-ItemProperty -Path $suggestionsPath -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $suggestionsPath -Name "SubscribedContent-310093Enabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $suggestionsPath -Name "SystemPaneSuggestionsEnabled" -Value 0 -Type DWord -Force

    # Find Crimson executable (c3.exe is the main binary)
    $crimsonExe = $null
    $knownPath = "C:\Program Files (x86)\Red Lion Controls\Crimson 3.0\c3.exe"
    if (Test-Path $knownPath) {
        $crimsonExe = $knownPath
    }
    if (-not $crimsonExe) {
        $searchPaths = @(
            "C:\Program Files\Red Lion Controls",
            "C:\Program Files (x86)\Red Lion Controls"
        )
        foreach ($sp in $searchPaths) {
            if (Test-Path $sp) {
                $found = Get-ChildItem $sp -Recurse -Filter "c3.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    $crimsonExe = $found.FullName
                    break
                }
            }
        }
    }

    if ($crimsonExe) {
        Write-Host "Crimson executable found at: $crimsonExe"

        # Save the path for task scripts to find
        $crimsonExe | Out-File -FilePath "C:\Users\Docker\crimson_exe_path.txt" -Encoding UTF8 -Force

        # Warm up Crimson: launch and close to complete any first-run setup
        Write-Host "Warming up Crimson (first-run cycle)..."
        # Convert to 8.3 short path to avoid batch file issues with parentheses in "Program Files (x86)"
        $fso = New-Object -ComObject Scripting.FileSystemObject
        $shortExePath = $fso.GetFile($crimsonExe).ShortPath
        $warmupScript = "C:\Windows\Temp\warmup_crimson.cmd"
        $warmupContent = "@echo off`r`nstart `"`" $shortExePath"
        [System.IO.File]::WriteAllText($warmupScript, $warmupContent)

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
        schtasks /Create /TN "WarmupCrimson" /TR "cmd /c $warmupScript" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN "WarmupCrimson" 2>$null
        Start-Sleep -Seconds 15

        # Dismiss registration dialog via PyAutoGUI
        Write-Host "Dismissing registration dialog during warm-up..."
        try {
            . "C:\workspace\scripts\task_utils.ps1"
            # Click Skip button at (554, 585), then confirm Yes at (630, 349)
            try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 554; y = 585} | Out-Null } catch { }
            Start-Sleep -Milliseconds 1500
            try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 630; y = 349} | Out-Null } catch { }
            Start-Sleep -Milliseconds 1000
            # Fallback: Alt+Y and Escape
            try { Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = @("alt", "y")} | Out-Null } catch { }
            Start-Sleep -Milliseconds 500
            try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }
            Start-Sleep -Seconds 2
        } catch {
            Write-Host "WARNING: Could not dismiss dialogs via PyAutoGUI: $($_.Exception.Message)"
        }

        # Kill Crimson to complete the warm-up cycle
        Get-Process -Name "c3" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        schtasks /Delete /TN "WarmupCrimson" /F 2>$null
        Remove-Item $warmupScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
        Write-Host "Crimson warm-up complete."
    } else {
        Write-Host "WARNING: Crimson executable not found. Tasks may need to locate it."
    }

    # Minimize any open terminal/command windows
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
}
"@
    Get-Process cmd -ErrorAction SilentlyContinue | ForEach-Object {
        [Win32]::ShowWindow($_.MainWindowHandle, 6) | Out-Null
    }

    # List available data files
    Write-Host "Available data files in $TasksDir :"
    Get-ChildItem $TasksDir | ForEach-Object { Write-Host "  - $($_.Name)" }

    Write-Host "Available project files in $ProjectsDir :"
    Get-ChildItem $ProjectsDir | ForEach-Object { Write-Host "  - $($_.Name)" }

    Write-Host "=== Crimson HMI environment setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
