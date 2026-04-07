Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Setup script for Tier2 Submit environment.
# This script runs after Windows boots (post_start hook).
# Configures the environment, copies data files, and performs warm-up launch.

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up Tier2 Submit environment ==="

    # Create working directory on Desktop
    $TasksDir = "C:\Users\Docker\Desktop\Tier2Tasks"
    New-Item -ItemType Directory -Force -Path $TasksDir | Out-Null

    # Create output directory for submission files
    $OutputDir = "C:\Users\Docker\Desktop\Tier2Output"
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

    # Copy data files from workspace to Desktop for easy access (exclude large installer)
    if (Test-Path "C:\workspace\data") {
        Get-ChildItem "C:\workspace\data" -File | Where-Object { $_.Name -notmatch "(?i)installer|setup" } |
            ForEach-Object { Copy-Item $_.FullName -Destination $TasksDir -Force -ErrorAction SilentlyContinue }
        Write-Host "Data files copied to: $TasksDir"
    }

    # Aggressively disable OneDrive
    Write-Host "Disabling OneDrive..."
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process OneDriveSetup -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $onedrivePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $onedrivePath -Name "OneDrive" -ErrorAction SilentlyContinue
    $onedrivePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $onedrivePolicyPath)) {
        New-Item -Path $onedrivePolicyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $onedrivePolicyPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force
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

    # Disable Windows Backup notifications
    $backupPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $backupPath)) {
        New-Item -Path $backupPath -Force | Out-Null
    }
    Set-ItemProperty -Path $backupPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force

    # Find Tier2 Submit executable
    Write-Host "Locating Tier2 Submit executable..."
    . C:\workspace\scripts\task_utils.ps1
    try {
        $t2sExe = Find-Tier2SubmitExe
        Write-Host "Found Tier2 Submit at: $t2sExe"
    } catch {
        Write-Host "WARNING: Tier2 Submit executable not found: $($_.Exception.Message)"
        Write-Host "Searching more broadly..."
        $t2sExe = $null
        $searchDirs = @("C:\", "C:\Program Files", "C:\Program Files (x86)", "C:\Users")
        foreach ($dir in $searchDirs) {
            $found = Get-ChildItem $dir -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue -Depth 5 |
                Where-Object { $_.Name -match "(?i)tier2|t2s" -and $_.Name -notmatch "unins|setup|install" } |
                Select-Object -First 1
            if ($found) {
                $t2sExe = $found.FullName
                Write-Host "Found Tier2 Submit at: $t2sExe"
                break
            }
        }
    }

    if ($t2sExe) {
        # Warm up Tier2 Submit: launch and close to complete first-run cycle
        Write-Host "Warming up Tier2 Submit (first-run cycle)..."
        $warmupScript = "C:\Windows\Temp\warmup_tier2submit.cmd"
        $warmupContent = "@echo off`r`nstart `"`" `"$t2sExe`""
        [System.IO.File]::WriteAllText($warmupScript, $warmupContent)

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN "WarmupTier2Submit" /TR "cmd /c $warmupScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN "WarmupTier2Submit" 2>$null
        Start-Sleep -Seconds 25

        # Dismiss any first-run dialogs
        $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
        if (Test-Path $dismissScript) {
            schtasks /Create /TN "DismissT2S" /TR "powershell -ExecutionPolicy Bypass -File $dismissScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN "DismissT2S" 2>$null
            Start-Sleep -Seconds 10
            schtasks /Delete /TN "DismissT2S" /F 2>$null
        }

        # Kill Tier2 Submit and its sub-processes
        Get-Process | Where-Object { $_.ProcessName -match "(?i)tier2|t2s|filemaker|fmapp" } | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        schtasks /Delete /TN "WarmupTier2Submit" /F 2>$null
        Remove-Item $warmupScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
        Write-Host "Tier2 Submit warm-up complete."
    } else {
        Write-Host "WARNING: Tier2 Submit executable not found for warm-up."
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
    Get-ChildItem $TasksDir | ForEach-Object { Write-Host "  - $($_.Name) ($([math]::Round($_.Length/1KB, 1)) KB)" }

    Write-Host "=== Tier2 Submit environment setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
