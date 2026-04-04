Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Setup script for Microsoft Word 2010 environment.
# This script runs after Windows boots (post_start hook).
# Word 2010 is installed via MSI from Office 2010 Professional Plus ISO.
# No login or activation required.

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up Word 2010 environment ==="

    # Create working directory on Desktop
    $TasksDir = "C:\Users\Docker\Desktop\WordTasks"
    New-Item -ItemType Directory -Force -Path $TasksDir | Out-Null

    # Copy data files from workspace to Desktop for easy access
    if (Test-Path "C:\workspace\data") {
        Get-ChildItem "C:\workspace\data" -Filter "*.docx" | ForEach-Object {
            Copy-Item $_.FullName -Destination $TasksDir -Force
        }
        Write-Host "Data files copied to: $TasksDir"
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
    # Uninstall OneDrive silently (non-blocking with timeout)
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
    # Disable Windows Backup/Consumer notifications
    $backupPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $backupPath)) {
        New-Item -Path $backupPath -Force | Out-Null
    }
    Set-ItemProperty -Path $backupPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force

    # Set Office 14.0 registry keys to suppress first-run dialogs and activation
    Write-Host "Setting Office 14.0 registry keys..."
    $regPaths = @(
        "HKCU:\Software\Microsoft\Office\14.0\Common\General",
        "HKCU:\Software\Microsoft\Office\14.0\FirstRun",
        "HKCU:\Software\Microsoft\Office\14.0\Word\Options",
        "HKCU:\Software\Microsoft\Office\14.0\Registration"
    )
    foreach ($rp in $regPaths) {
        if (-not (Test-Path $rp)) {
            New-Item -Path $rp -Force | Out-Null
        }
    }
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\14.0\Common\General" -Name "ShownFirstRunOptin" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\14.0\FirstRun" -Name "BootedRTM" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\14.0\FirstRun" -Name "DisableMovie" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\14.0\Word\Options" -Name "DisableBootToOfficeStart" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\14.0\Registration" -Name "AcceptAllEulas" -Value 1 -Type DWord -Force

    # Machine-wide policies
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Office\14.0\Common\General"
    if (-not (Test-Path $policyPath)) {
        New-Item -Path $policyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $policyPath -Name "ShownFirstRunOptin" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $policyPath -Name "DisableBootToOfficeStart" -Value 1 -Type DWord -Force

    # Disable Office 2010 automatic updates
    $updatePath = "HKCU:\Software\Microsoft\Office\14.0\Common"
    if (-not (Test-Path $updatePath)) {
        New-Item -Path $updatePath -Force | Out-Null
    }
    Set-ItemProperty -Path $updatePath -Name "UpdatesEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

    # Warm up Word: launch, dismiss dialogs, and close to complete first-run cycle
    Write-Host "Warming up Word 2010 (first-run cycle)..."

    # Load task_utils for Find-WordExe and Launch-WordDocumentInteractive
    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (Test-Path $utils) {
        . $utils
    } else {
        Write-Host "WARNING: task_utils.ps1 not found. Skipping warm-up."
        return
    }

    $wordExe = $null
    try {
        $wordExe = Find-WordExe
        Write-Host "Word executable: $wordExe"
    } catch {
        Write-Host "WARNING: Could not find Word executable. Skipping warm-up."
        Write-Host "Error: $($_.Exception.Message)"
    }

    if ($wordExe) {
        # Launch Word via schtasks (interactive session)
        $warmupScript = "C:\Windows\Temp\warmup_word.cmd"
        $warmupContent = "@echo off`r`nstart `"`" `"$wordExe`""
        [System.IO.File]::WriteAllText($warmupScript, $warmupContent)

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN "WarmupWord" /TR "cmd /c $warmupScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN "WarmupWord" 2>$null
        Start-Sleep -Seconds 15

        # Try to dismiss any first-run dialogs via PyAutoGUI
        try {
            Dismiss-WordDialogsBestEffort -Retries 2 -InitialWaitSeconds 2 -BetweenRetriesSeconds 1
            Write-Host "First-run dialog dismissal attempted."
        } catch {
            Write-Host "WARNING: Dialog dismissal failed: $($_.Exception.Message)"
        }

        # Kill Word
        Get-Process WINWORD -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        schtasks /Delete /TN "WarmupWord" /F 2>$null
        Remove-Item $warmupScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
        Write-Host "Word warm-up complete."
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
    Write-Host "Available data files in ${TasksDir}:"
    Get-ChildItem $TasksDir -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  - $($_.Name)" }

    Write-Host "=== Word 2010 environment setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
