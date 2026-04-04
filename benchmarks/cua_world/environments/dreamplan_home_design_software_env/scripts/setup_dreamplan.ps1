Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Post-start setup for DreamPlan Home Design environment.
# This runs via SSH (Session 0) but PyAutoGUI server is available on port 5555.
# Steps:
# 1. Disable OneDrive and Edge auto-restore
# 2. If DreamPlan not installed, run GUI installer via schtasks + PyAutoGUI
# 3. Warm-up launch: handle start screen and first-run dialogs
# 4. Kill DreamPlan after warm-up (subsequent launches will be clean)

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

# Load shared task utilities (PyAutoGUI helpers)
. "C:\workspace\scripts\task_utils.ps1"

try {
    Write-Host "=== Setting up DreamPlan Home Design environment ==="

    # -- Step 1: Disable OneDrive and Edge auto-restore --
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

    # Disable Edge session restore and startup boost
    $edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (-not (Test-Path $edgePolicyPath)) {
        New-Item -Path $edgePolicyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $edgePolicyPath -Name "StartupBoostEnabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $edgePolicyPath -Name "BackgroundModeEnabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $edgePolicyPath -Name "RestoreOnStartup" -Value 5 -Type DWord -Force

    # Kill Edge processes
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # -- Step 2: Install DreamPlan if needed --
    $dreamplanExe = $null
    $searchPaths = @(
        "C:\Program Files (x86)\NCH Software\DreamPlan\dreamplan.exe",
        "C:\Program Files\NCH Software\DreamPlan\dreamplan.exe",
        "C:\Program Files (x86)\NCH Software\DreamPlan\DreamPlan.exe",
        "C:\Program Files\NCH Software\DreamPlan\DreamPlan.exe"
    )

    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $dreamplanExe = $path
            break
        }
    }

    if (-not $dreamplanExe) {
        Write-Host "DreamPlan not installed. Running GUI installer via PyAutoGUI..."

        $installerPath = "C:\Windows\Temp\designsetup.exe"
        if (-not (Test-Path $installerPath)) {
            throw "Installer not found at $installerPath. Pre-start hook may have failed."
        }

        # Launch installer in GUI session via schtasks
        $installScript = "C:\Windows\Temp\run_dreamplan_installer.cmd"
        [System.IO.File]::WriteAllText($installScript, "@echo off`r`nstart `"`" `"$installerPath`"")

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
        schtasks /Create /TN "InstallDreamPlan" /TR "cmd /c $installScript" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN "InstallDreamPlan" 2>$null
        $ErrorActionPreference = $prevEAP

        # Wait for installer GUI to appear
        Write-Host "Waiting for installer to load (20s)..."
        Start-Sleep -Seconds 20

        # Dismiss any OneDrive/notification popups
        Write-Host "Pressing Escape to dismiss any popups..."
        PyAutoGUI-Press -Key "escape"
        Start-Sleep -Seconds 1
        PyAutoGUI-Press -Key "escape"
        Start-Sleep -Seconds 2

        # Click on the installer dialog title bar to ensure it has focus
        Write-Host "Focusing installer dialog..."
        PyAutoGUI-Click -X 640 -Y 150
        Start-Sleep -Seconds 1

        # NCH Installer EULA page: "I accept the license terms" is pre-selected
        # Click "Next >" to accept EULA and proceed
        # VERIFIED: Next button at (855, 568) on 1280x720 screen
        Write-Host "Clicking Next on EULA..."
        PyAutoGUI-Click -X 855 -Y 568
        Start-Sleep -Seconds 5

        # Retry Next click in case first didn't register (e.g. popup grabbed focus)
        Write-Host "Retry Next click..."
        PyAutoGUI-Click -X 855 -Y 568
        Start-Sleep -Seconds 5

        # "Optional Programs and Extras" page appears - click "Skip All" to skip NCH bundled software
        # VERIFIED: Skip All button at (865, 568) on 1280x720 screen
        Write-Host "Clicking 'Skip All' on Optional Programs page..."
        PyAutoGUI-Click -X 865 -Y 568
        Start-Sleep -Seconds 5

        # Retry Skip All in case the page wasn't ready
        PyAutoGUI-Click -X 865 -Y 568
        Start-Sleep -Seconds 3

        # NCH installer auto-installs and may launch DreamPlan
        # Wait for installation to complete (up to 120s)
        Write-Host "Waiting for DreamPlan to install (up to 120s)..."
        $installed = $false
        for ($i = 0; $i -lt 120; $i++) {
            foreach ($sp in $searchPaths) {
                if (Test-Path $sp) {
                    $dreamplanExe = $sp
                    $installed = $true
                    break
                }
            }
            if ($installed) {
                Write-Host "DreamPlan installed at: $dreamplanExe (after ${i}s)"
                break
            }
            Start-Sleep -Seconds 1
        }

        if (-not $installed) {
            Write-Host "WARNING: DreamPlan exe not found after 120s. Searching broadly..."
            $searchDirs = @("C:\Program Files (x86)", "C:\Program Files")
            foreach ($dir in $searchDirs) {
                $found = Get-ChildItem $dir -Recurse -Filter "dreamplan.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    $dreamplanExe = $found.FullName
                    Write-Host "Found DreamPlan at: $dreamplanExe"
                    $installed = $true
                    break
                }
            }

            if (-not $installed) {
                throw "DreamPlan installation failed - executable not found."
            }
        }

        # Clean up installer artifacts
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        schtasks /Delete /TN "InstallDreamPlan" /F 2>$null
        $ErrorActionPreference = $prevEAP
        Remove-Item $installScript -Force -ErrorAction SilentlyContinue

        # Wait for any post-install dialogs or app launch
        Start-Sleep -Seconds 5

        # Dismiss any NCH bundled software offers or first-run dialogs
        Write-Host "Dismissing post-install dialogs..."
        for ($i = 0; $i -lt 5; $i++) {
            PyAutoGUI-Press -Key "escape"
            Start-Sleep -Seconds 1
        }

        Write-Host "DreamPlan installed and initial setup complete."
    } else {
        Write-Host "DreamPlan already installed at: $dreamplanExe"
    }

    # Save exe path for task scripts
    $dreamplanExe | Out-File -FilePath "C:\Users\Docker\dreamplan_exe_path.txt" -Encoding ASCII -Force
    Write-Host "Saved exe path to dreamplan_exe_path.txt"

    # Disable tutorial tips/instructions overlay (they interfere with agent automation).
    # DreamPlan shows context-sensitive tips on every tool selection; this disables them.
    $dpSettingsPath = "HKCU:\Software\NCH Software\DreamPlan\Settings"
    if (-not (Test-Path $dpSettingsPath)) {
        New-Item -Path $dpSettingsPath -Force | Out-Null
    }
    Set-ItemProperty -Path $dpSettingsPath -Name "IsInstructionsDisplayed" -Value "0" -Force
    Write-Host "Disabled tutorial tips (IsInstructionsDisplayed=0)."

    # -- Step 3: Close DreamPlan after install (warm-up phase 1 complete) --
    # Try graceful close first (prevents crash dialog on next launch).
    Write-Host "Closing DreamPlan after initial setup..."
    Close-DreamPlanGracefully
    Get-Process designsetup -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # Clean up installer file
    Remove-Item "C:\Windows\Temp\designsetup.exe" -Force -ErrorAction SilentlyContinue

    # -- Step 4: Full warm-up launch (download samples, open Contemporary House, dismiss tutorial) --
    # Leave DreamPlan OPEN at end so the QEMU savevm checkpoint captures it running with project loaded.
    # The checkpoint will show: DreamPlan with Contemporary House in 3D view, no tutorial overlay.
    Write-Host "Starting full warm-up launch (opens Contemporary House and dismisses tutorial)..."
    # WaitSeconds=45: DreamPlan on this VM can take 40+ seconds to show its window
    # SampleWaitSec=60: first-time download of sample projects takes 30-60 seconds
    $launchSuccess = Launch-DreamPlanWithSample -WaitSeconds 45 -SampleWaitSec 60
    if ($launchSuccess) {
        Write-Host "Warm-up complete. Contemporary House is loaded."
    } else {
        Write-Host "WARNING: Warm-up launch reported failure. DreamPlan may not be in correct state."
    }

    # Verify Contemporary House is open (uses VBScript in Session 1 via AppActivate)
    $verified = Test-ContemporaryHouseOpen
    if ($verified) {
        Write-Host "VERIFIED: Contemporary House is open and ready."
    } else {
        Write-Host "WARNING: Could not verify Contemporary House is open. Checkpoint may be in wrong state."
    }
    Write-Host "NOTE: DreamPlan is left OPEN for checkpoint savevm."

    # -- Step 5: Kill remaining Edge processes and minimize terminals --
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Clear Edge session restore data
    $edgeUserData = "C:\Users\Docker\AppData\Local\Microsoft\Edge\User Data"
    if (Test-Path $edgeUserData) {
        Get-ChildItem $edgeUserData -Directory | ForEach-Object {
            $sessionFiles = @("Current Session", "Current Tabs", "Last Session", "Last Tabs")
            foreach ($sf in $sessionFiles) {
                $fp = Join-Path $_.FullName $sf
                Remove-Item $fp -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Host "Cleared Edge session restore data."
    }

    Write-Host "=== DreamPlan Home Design environment setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
