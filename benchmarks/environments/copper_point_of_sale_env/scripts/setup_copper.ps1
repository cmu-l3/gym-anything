Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Post-start setup for Copper Point of Sale environment.
# This runs via SSH (Session 0) but PyAutoGUI server is available on port 5555.
# Steps:
# 1. Disable OneDrive
# 2. If Copper not installed, run GUI installer via schtasks + PyAutoGUI
# 3. Warm-up launch: dismiss Quick Start Wizard
# 4. Kill Copper after warm-up (subsequent launches will be clean)

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

# Load shared task utilities (PyAutoGUI helpers)
. "C:\workspace\scripts\task_utils.ps1"

try {
    Write-Host "=== Setting up Copper Point of Sale environment ==="

    # ── Step 1: Disable OneDrive ──────────────────────────────
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

    # ── Step 2: Install Copper if needed ──────────────────────
    $copperExe = "C:\Program Files (x86)\NCH Software\Copper\copper.exe"

    if (-not (Test-Path $copperExe)) {
        Write-Host "Copper POS not installed. Running GUI installer via PyAutoGUI..."

        $installerPath = "C:\Windows\Temp\possetup.exe"
        if (-not (Test-Path $installerPath)) {
            throw "Installer not found at $installerPath. Pre-start hook may have failed."
        }

        # Launch installer in GUI session via schtasks
        $installScript = "C:\Windows\Temp\run_copper_installer.cmd"
        [System.IO.File]::WriteAllText($installScript, "@echo off`r`nstart `"`" `"$installerPath`"")

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
        schtasks /Create /TN "InstallCopper" /TR "cmd /c $installScript" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN "InstallCopper" 2>$null
        $ErrorActionPreference = $prevEAP

        # Wait for installer GUI to appear
        Write-Host "Waiting for installer to load (20s)..."
        Start-Sleep -Seconds 20

        # Try to dismiss OneDrive popup via Escape first (safe if not present)
        Write-Host "Pressing Escape to dismiss any OneDrive/notification popups..."
        PyAutoGUI-Press -Key "escape"
        Start-Sleep -Seconds 1
        PyAutoGUI-Press -Key "escape"
        Start-Sleep -Seconds 2

        # Click on the installer dialog title bar to ensure it has focus
        # The installer title "Installing Copper v3.06" is at approx (640, 150)
        Write-Host "Focusing installer dialog..."
        PyAutoGUI-Click -X 640 -Y 150
        Start-Sleep -Seconds 1

        # NCH Installer EULA page: "I accept the license terms" is pre-selected
        # Click "Next" to accept EULA and install
        # EULA Next button at (788, 539) based on visual grounding at 1280x720
        Write-Host "Clicking Next on EULA..."
        PyAutoGUI-Click -X 788 -Y 539
        Start-Sleep -Seconds 5

        # Retry Next click in case first didn't register (e.g. OneDrive grabbed focus)
        # If EULA already passed, this click will hit harmless area
        Write-Host "Retry Next click..."
        PyAutoGUI-Click -X 788 -Y 539
        Start-Sleep -Seconds 3

        # The installer auto-installs and launches Copper with Quick Start Wizard
        # Wait for installation + app launch (up to 120s - web installer needs download time)
        Write-Host "Waiting for Copper to install and launch (up to 120s)..."
        $installed = $false
        for ($i = 0; $i -lt 120; $i++) {
            if (Test-Path $copperExe) {
                $installed = $true
                Write-Host "Copper installed at: $copperExe (after ${i}s)"
                break
            }
            Start-Sleep -Seconds 1
        }

        if (-not $installed) {
            Write-Host "WARNING: copper.exe not found after 120s. Checking broadly..."
            $found = Get-ChildItem "C:\Program Files (x86)" -Recurse -Filter "copper.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $copperExe = $found.FullName
                Write-Host "Found Copper at: $copperExe"
            } else {
                throw "Copper POS installation failed - executable not found."
            }
        }

        # Clean up installer artifacts
        schtasks /Delete /TN "InstallCopper" /F 2>$null
        Remove-Item $installScript -Force -ErrorAction SilentlyContinue

        # Wait for Quick Start Wizard to fully render
        Start-Sleep -Seconds 5

        # Quick Start Wizard Step 1 of 2: Business Name, Address, Contact
        # Click "Cancel" to skip the wizard (creates default company)
        # Cancel button at (851, 512)
        Write-Host "Dismissing Quick Start Wizard..."
        PyAutoGUI-Click -X 851 -Y 512
        Start-Sleep -Seconds 2

        # "Wizard Cancelled" info dialog: click OK
        # OK button at (791, 455)
        Write-Host "Clicking OK on Wizard Cancelled dialog..."
        PyAutoGUI-Click -X 791 -Y 455
        Start-Sleep -Seconds 2

        Write-Host "Copper POS installed and initial setup complete."
    } else {
        Write-Host "Copper POS already installed at: $copperExe"
    }

    # Save exe path for task scripts
    $copperExe | Out-File -FilePath "C:\Users\Docker\copper_exe_path.txt" -Encoding ASCII -Force
    Write-Host "Saved exe path to copper_exe_path.txt"

    # ── Step 3: Kill Copper after install/wizard (warm-up complete) ──
    Write-Host "Killing Copper after warm-up..."
    Get-Process copper -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process possetup -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # Clean up installer file
    Remove-Item "C:\Windows\Temp\possetup.exe" -Force -ErrorAction SilentlyContinue

    # ── Step 4: Second warm-up launch (ensures no more first-run dialogs) ──
    Write-Host "Second warm-up launch to verify clean startup..."
    Launch-CopperInteractive
    Start-Sleep -Seconds 15

    # Dismiss any remaining popups
    Write-Host "Dismissing any remaining dialogs..."
    & "C:\workspace\scripts\dismiss_dialogs.ps1"
    Start-Sleep -Seconds 3

    # Kill again
    Stop-Copper
    Start-Sleep -Seconds 3
    Write-Host "Second warm-up complete."

    # ── Step 5: Minimize terminals ──
    Minimize-Terminals

    Write-Host "=== Copper Point of Sale environment setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
