Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing ActivInspire ==="

    # ---- Check if already installed ----
    # The installer places files under "Activ Software" (not "Promethean")
    $inspireExe = $null
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
            $inspireExe = $p
            Write-Host "ActivInspire already installed at: $inspireExe"
            [System.IO.File]::WriteAllText("C:\Users\Docker\activinspire_path.txt", $inspireExe)
            Write-Host "=== Installation skipped (already present) ==="
            return
        }
    }

    # ---- Download ActivInspire Windows installer ----
    Write-Host "Downloading ActivInspire Windows installer..."

    $installerDir = "C:\Windows\Temp"
    $installerPath = Join-Path $installerDir "ActivInspireSetup.exe"

    # archive.org is the most reliable source (official CDN URLs change frequently)
    $downloadUrls = @(
        "https://archive.org/download/activ-inspire-suitev-2.7.66643en-ussetup/ActivInspireSuite%2Bv2.7.66643%2Ben_US%2Bsetup.exe",
        "https://archive.org/download/activ-inspire-suitev-2.7.66643en-ussetup/ActivInspireSuite+v2.7.66643+en_US+setup.exe"
    )

    $downloaded = $false
    foreach ($url in $downloadUrls) {
        Write-Host "Trying: $url"
        $prevEAP = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            & curl.exe -L --silent --show-error --connect-timeout 30 --max-time 900 -o $installerPath $url 2>&1
        } finally {
            $ErrorActionPreference = $prevEAP
        }

        if ((Test-Path $installerPath) -and ((Get-Item $installerPath).Length -gt 50000000)) {
            $downloaded = $true
            Write-Host "Download successful from: $url"
            break
        } else {
            $actualSize = 0
            if (Test-Path $installerPath) { $actualSize = (Get-Item $installerPath).Length }
            Write-Host "Download failed or file too small ($actualSize bytes) from: $url"
            Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $downloaded) {
        throw "Failed to download ActivInspire installer from all sources"
    }

    $installerSize = (Get-Item $installerPath).Length
    Write-Host "Downloaded installer size: $installerSize bytes"

    # ---- Run installer via interactive session ----
    # The ActivInspire Suite installer (InstallShield) does NOT support true silent
    # install (/s /v"/qn" returns exit code -3). It MUST run in an interactive
    # desktop session (Session 1) with GUI automation to click through the wizard.
    #
    # Strategy: Launch the installer AND a Python pyautogui clicker script together
    # via a schtask in Session 1. The clicker uses pyautogui directly (not via TCP)
    # which ensures reliable click delivery in the desktop session.

    Write-Host "Launching installer with pyautogui clicker in interactive session..."

    # Create the Python clicker script
    $clickerPy = @'
import pyautogui, time, subprocess, os, ctypes

LOG = r"C:\Windows\Temp\install_clicker.log"

def log(msg):
    ts = time.strftime("%H:%M:%S")
    with open(LOG, "a") as f:
        f.write(f"{ts} {msg}\n")

def click(x, y, desc=""):
    log(f"Clicking ({x},{y}) - {desc}")
    pyautogui.click(x, y)

def focus_installer():
    """Find and bring the installer window to the foreground."""
    try:
        user32 = ctypes.windll.user32

        # EnumWindows callback to find installer window
        EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int))
        buf = ctypes.create_unicode_buffer(256)
        found_hwnd = [None]

        def callback(hwnd, lParam):
            user32.GetWindowTextW(hwnd, buf, 256)
            title = buf.value
            if "ActivInspire" in title or "InstallShield" in title or "Setup" in title:
                if user32.IsWindowVisible(hwnd):
                    found_hwnd[0] = hwnd
                    log(f"Found installer window: '{title}' hwnd={hwnd}")
                    return False  # stop enumeration
            return True

        user32.EnumWindows(EnumWindowsProc(callback), 0)

        if found_hwnd[0]:
            hwnd = found_hwnd[0]
            # Restore if minimized (SW_RESTORE = 9)
            user32.ShowWindow(hwnd, 9)
            time.sleep(0.3)
            # Bring to foreground
            user32.SetForegroundWindow(hwnd)
            time.sleep(0.3)
            log("Installer window focused")
            return True
        else:
            log("Installer window not found by title")
            return False
    except Exception as e:
        log(f"focus_installer error: {e}")
        return False

log("Starting install clicker (pyautogui direct)")

# Minimize our own console window so it doesn't cover the installer
try:
    console_hwnd = ctypes.windll.kernel32.GetConsoleWindow()
    if console_hwnd:
        ctypes.windll.user32.ShowWindow(console_hwnd, 6)  # SW_MINIMIZE
        log("Minimized console window")
except Exception as e:
    log(f"Failed to minimize console: {e}")

# Dismiss OneDrive notification if visible (click "No thanks" or X)
time.sleep(2)
# OneDrive X button at approx (1238, 392) in 1280x720
click(1238, 392, "Dismiss OneDrive X button")
time.sleep(1)

# Wait for installer window
log("Waiting for installer window...")
for i in range(120):
    result = subprocess.run(["tasklist"], capture_output=True, text=True)
    if "ActivInspireSetup" in result.stdout:
        log("Installer process found")
        break
    time.sleep(1)

# Wait for wizard to fully render
log("Waiting 15s for wizard to render...")
time.sleep(15)

# Focus the installer window before clicking
focus_installer()
time.sleep(1)

# Click through wizard - Next button is at (751, 525)
# Use 10s delays between steps for slow VMs
click(751, 525, "Step 1: Welcome -> Next")
time.sleep(10)

click(751, 525, "Step 2: Setup Type -> Next")
time.sleep(10)

click(751, 525, "Step 3: Destination -> Next")
time.sleep(10)

click(751, 525, "Step 4: Shared Data -> Next")
time.sleep(10)

# Step 5: License - click I accept radio then Next
# Do NOT press Escape here (it triggers Exit Setup dialog)
click(640, 180, "Step 5: Focus installer title bar")
time.sleep(2)
click(424, 449, "Step 5: I accept radio button")
time.sleep(3)
click(751, 525, "Step 5: License -> Next")
time.sleep(10)

click(751, 525, "Step 6: Start Copying -> Next")
time.sleep(10)

click(751, 525, "Step 7: Ready to Install -> Install")
time.sleep(10)

# Wait for installation to complete (up to 15 min)
# Periodically click the Finish button location (751,525) every 30s.
# During file-copying this clicks harmlessly on the progress bar.
# Once the Wizard Complete screen appears, it clicks Finish immediately.
log("Waiting for installation to complete...")
for i in range(900):
    result = subprocess.run(["tasklist"], capture_output=True, text=True)
    if "ActivInspireSetup" not in result.stdout:
        log("Installer process exited")
        break
    # Every 30 seconds, focus installer and handle whatever screen is showing
    if i > 0 and i % 30 == 0:
        focus_installer()
        time.sleep(0.5)
        # Click "I accept" radio button location first (in case a license page is showing)
        # This is harmless if no license page is visible
        click(424, 449, f"Periodic I-accept click ({i}s)")
        time.sleep(1)
        click(751, 525, f"Periodic Next/Finish click ({i}s)")
    time.sleep(1)
    if i % 60 == 0 and i > 0:
        log(f"  Still installing... ({i}s)")
else:
    log("WARNING: Installer still running after 900s timeout")
    # Final attempt to click Finish
    click(751, 525, "Final timeout Finish click")
    time.sleep(10)

log("Install clicker complete")
with open(r"C:\Windows\Temp\install_clicker_done.txt", "w") as f:
    f.write("done")
'@

    [System.IO.File]::WriteAllText("C:\Windows\Temp\install_clicker.py", $clickerPy)

    # Create batch file that launches installer AND runs the clicker
    $batchContent = "@echo off`r`nstart `"`" `"C:\Windows\Temp\ActivInspireSetup.exe`"`r`n`"C:\Program Files\Python311\python.exe`" `"C:\Windows\Temp\install_clicker.py`""
    [System.IO.File]::WriteAllText("C:\Windows\Temp\install_and_click.bat", $batchContent)

    # Run via schtask in Session 1
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN "InstallActivInspireGUI" /TR "C:\Windows\Temp\install_and_click.bat" /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>&1
    schtasks /Run /TN "InstallActivInspireGUI" 2>&1
    $ErrorActionPreference = $prevEAP

    # Wait for the clicker to complete (up to 20 minutes)
    Write-Host "Waiting for interactive installation to complete..."
    $timeout = 1200
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        if (Test-Path "C:\Windows\Temp\install_clicker_done.txt") {
            Write-Host "Install clicker completed"
            break
        }
        Start-Sleep -Seconds 10
        $elapsed += 10
        if ($elapsed % 60 -eq 0) {
            Write-Host "  Still waiting... ($elapsed seconds elapsed)"
        }
    }

    if ($elapsed -ge $timeout) {
        Write-Host "WARNING: Installation timed out after $timeout seconds"
        Get-Process -Name "ActivInspireSetup" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    # Print clicker log for debugging
    if (Test-Path "C:\Windows\Temp\install_clicker.log") {
        Write-Host "--- Clicker log ---"
        Get-Content "C:\Windows\Temp\install_clicker.log" | ForEach-Object { Write-Host "  $_" }
        Write-Host "---"
    }

    # Wait for installer to fully finish writing files
    Write-Host "Waiting for installer to finalize..."
    Start-Sleep -Seconds 15

    # ---- Verify installation ----
    Write-Host "Verifying ActivInspire installation..."
    $inspireExe = $null
    foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            $inspireExe = $p
            break
        }
    }

    if (-not $inspireExe) {
        # Search more broadly
        Write-Host "Searching for ActivInspire executable..."
        $found = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse -Filter "Inspire.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $inspireExe = $found.FullName
        }
    }

    if ($inspireExe) {
        Write-Host "SUCCESS: ActivInspire installed at: $inspireExe"
        [System.IO.File]::WriteAllText("C:\Users\Docker\activinspire_path.txt", $inspireExe)
    } else {
        Write-Host "ERROR: ActivInspire executable not found after install"
        Write-Host "Listing Program Files for debugging..."
        Get-ChildItem "C:\Program Files" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name)" }
        Get-ChildItem "C:\Program Files (x86)" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name)" }
        throw "ActivInspire installation failed"
    }

    # ---- Suppress startup apps (OneDrive, Teams) ----
    Write-Host "Suppressing startup apps..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -Name "OneDrive" -ErrorAction SilentlyContinue

    $onedrivePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    New-Item -Path $onedrivePolicyPath -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $onedrivePolicyPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force

    $oneDriveSetup = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    if (Test-Path $oneDriveSetup) {
        $proc = Start-Process $oneDriveSetup -ArgumentList "/uninstall" -PassThru -ErrorAction SilentlyContinue
        if ($proc) {
            $finished = $proc.WaitForExit(30000)
            if ($finished) { Write-Host "OneDrive uninstalled." }
            else { Write-Host "OneDrive uninstall still running (continuing)." }
        }
    }

    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -Name "com.squirrel.Teams.Teams" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -Name "Teams" -ErrorAction SilentlyContinue

    $ErrorActionPreference = $prevEAP

    # ---- Create required directories ----
    Write-Host "Creating required directories..."
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents\Flipcharts" | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Pictures\ActivInspire" | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop" | Out-Null

    # ---- Cleanup temp files ----
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\install_clicker.py" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\install_and_click.bat" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\install_clicker.log" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\install_clicker_done.txt" -Force -ErrorAction SilentlyContinue

    Write-Host "=== ActivInspire installation complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
