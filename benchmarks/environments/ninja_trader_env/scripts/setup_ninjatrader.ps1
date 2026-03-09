Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Setup script for NinjaTrader 8 environment.
# This script runs after Windows boots (post_start hook).
# NinjaTrader 8.1.x Enterprise Evaluation does NOT require login on launch.

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up NinjaTrader 8 environment ==="

    # Create working directory on Desktop
    $TasksDir = "C:\Users\Docker\Desktop\NinjaTraderTasks"
    New-Item -ItemType Directory -Force -Path $TasksDir | Out-Null

    # Copy data files from workspace to Desktop for easy access
    if (Test-Path "C:\workspace\data") {
        Get-ChildItem "C:\workspace\data" -Filter "*.txt" | ForEach-Object {
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
    # Disable Windows Backup/Consumer notifications
    $backupPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $backupPath)) {
        New-Item -Path $backupPath -Force | Out-Null
    }
    Set-ItemProperty -Path $backupPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force

    # Warm up NinjaTrader: launch, dismiss dialogs, and close to complete first-run cycle.
    Write-Host "Warming up NinjaTrader (first-run cycle)..."
    $ntExe = $null
    $ntPaths = @(
        "C:\Program Files (x86)\NinjaTrader 8\bin64\NinjaTrader.exe",
        "C:\Program Files (x86)\NinjaTrader 8\bin\NinjaTrader.exe",
        "C:\Program Files\NinjaTrader 8\bin64\NinjaTrader.exe",
        "C:\Program Files\NinjaTrader 8\bin\NinjaTrader.exe"
    )
    foreach ($p in $ntPaths) {
        if (Test-Path $p) {
            $ntExe = $p
            break
        }
    }

    if ($ntExe) {
        $warmupScript = "C:\Windows\Temp\warmup_ninjatrader.cmd"
        $warmupContent = "@echo off`r`nstart `"`" `"$ntExe`""
        [System.IO.File]::WriteAllText($warmupScript, $warmupContent)

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN "WarmupNT" /TR "cmd /c $warmupScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN "WarmupNT" 2>$null
        Start-Sleep -Seconds 20

        # Dismiss startup dialogs via PyAutoGUI TCP server
        $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
        if (Test-Path $dismissScript) {
            Write-Host "Dismissing warm-up dialogs via PyAutoGUI..."
            & $dismissScript
        }
        Start-Sleep -Seconds 3

        # Import historical data (SPY, AAPL, MSFT) from Desktop
        $importScript = "C:\workspace\scripts\import_data.ps1"
        if (Test-Path $importScript) {
            Write-Host "Importing historical data via PyAutoGUI..."
            & $importScript
        }
        Start-Sleep -Seconds 3

        # Kill NinjaTrader
        Get-Process NinjaTrader -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        schtasks /Delete /TN "WarmupNT" /F 2>$null
        Remove-Item $warmupScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
        Write-Host "NinjaTrader warm-up complete."
    } else {
        Write-Host "WARNING: NinjaTrader executable not found for warm-up."
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

    Write-Host "=== NinjaTrader 8 environment setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
