Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing Jolly Lobby Track ==="

    # ---- Check if already installed ----
    $lobbyExe = $null
    $searchPaths = @(
        "C:\Program Files (x86)\Jolly Technologies\Lobby Track\LobbyTrack.exe",
        "C:\Program Files\Jolly Technologies\Lobby Track\LobbyTrack.exe",
        "C:\Program Files (x86)\Jolly\Lobby Track\LobbyTrack.exe",
        "C:\Program Files\Jolly\Lobby Track\LobbyTrack.exe",
        "C:\Program Files (x86)\LobbyTrack\LobbyTrack.exe",
        "C:\Program Files\LobbyTrack\LobbyTrack.exe"
    )
    foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            $lobbyExe = $p
            Write-Host "Lobby Track already installed at: $lobbyExe"
            [System.IO.File]::WriteAllText("C:\Users\Docker\lobbytrack_path.txt", $lobbyExe)
            Write-Host "=== Installation skipped (already present) ==="
            return
        }
    }

    # ---- Download Lobby Track Free installer ----
    Write-Host "Downloading Jolly Lobby Track Free installer..."

    $installerDir = "C:\Windows\Temp"
    $installerPath = Join-Path $installerDir "LobbyTrackFreeSetup.exe"

    # Lobby Track Free from Jolly Technologies (original jollytech.com URL now 404)
    # Using Wayback Machine archive of the official distribution
    $downloadUrls = @(
        "https://web.archive.org/web/20170809181430/http://jollytech.com/download/LobbyTrackFreeSetup.exe",
        "https://web.archive.org/web/20180101000000*/jollytech.com/download/LobbyTrackFreeSetup.exe"
    )

    $downloaded = $false
    foreach ($url in $downloadUrls) {
        Write-Host "Trying: $url"
        $prevEAP = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            & curl.exe -L --silent --show-error --connect-timeout 60 --max-time 900 -o $installerPath $url 2>&1
        } finally {
            $ErrorActionPreference = $prevEAP
        }

        if ((Test-Path $installerPath) -and ((Get-Item $installerPath).Length -gt 5000000)) {
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
        throw "Failed to download Lobby Track installer from all sources"
    }

    $installerSize = (Get-Item $installerPath).Length
    Write-Host "Downloaded installer size: $installerSize bytes"

    $skipGUI = $false

    # ---- Try silent install first ----
    Write-Host "Attempting silent install..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    # Try InstallShield silent flags
    $silentProc = Start-Process $installerPath -ArgumentList '/s /v"/qn ALLUSERS=1 /norestart"' `
        -PassThru -Wait -ErrorAction SilentlyContinue
    if ($silentProc) {
        Write-Host "Silent install exit code: $($silentProc.ExitCode)"
    }

    $ErrorActionPreference = $prevEAP

    # Check if silent install succeeded
    $lobbyExe = $null
    foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            $lobbyExe = $p
            Write-Host "Silent install SUCCEEDED! Lobby Track at: $lobbyExe"
            [System.IO.File]::WriteAllText("C:\Users\Docker\lobbytrack_path.txt", $lobbyExe)
            # Skip GUI clicker entirely
            $skipGUI = $true
            break
        }
    }

    if (-not $lobbyExe) {
        # Search more broadly
        $found = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse `
            -Filter "LobbyTrack*.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch "Setup|Uninstall" } |
            Select-Object -First 1
        if ($found) {
            $lobbyExe = $found.FullName
            Write-Host "Silent install SUCCEEDED! Found at: $lobbyExe"
            [System.IO.File]::WriteAllText("C:\Users\Docker\lobbytrack_path.txt", $lobbyExe)
            $skipGUI = $true
        }
    }

    if (-not $skipGUI) {
        Write-Host "Silent install did not work, falling back to GUI automation..."
    }

    # ---- Fallback: Run installer via interactive session with GUI automation ----
    # Lobby Track uses an InstallShield-based installer. We launch it in
    # Session 1 alongside a PyAutoGUI clicker script that navigates the wizard.
    if (-not $skipGUI) {
    Write-Host "Launching installer with pyautogui clicker in interactive session..."

    # Create the Python clicker script — uses window-relative coordinates
    # so it works at any screen resolution (1024x768, 1280x720, 1920x1080)
    $clickerPy = @'
import pyautogui, time, subprocess, os, ctypes
from ctypes import wintypes

pyautogui.FAILSAFE = False
LOG = r"C:\Windows\Temp\install_clicker.log"
SHOT_DIR = r"C:\Windows\Temp\install_screenshots"
os.makedirs(SHOT_DIR, exist_ok=True)

def log(msg):
    ts = time.strftime("%H:%M:%S")
    line = f"{ts} {msg}"
    print(line)
    with open(LOG, "a") as f:
        f.write(line + "\n")

def screenshot(name):
    try:
        p = os.path.join(SHOT_DIR, f"{name}.png")
        pyautogui.screenshot(p)
        log(f"Screenshot: {p}")
    except Exception as e:
        log(f"Screenshot failed: {e}")

def find_window(*keywords):
    """Find a visible window matching any keyword. Returns (hwnd, title)."""
    user32 = ctypes.windll.user32
    WNDENUMPROC = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_int, ctypes.c_int)
    buf = ctypes.create_unicode_buffer(512)
    result = [None, None]
    def cb(hwnd, _):
        if not user32.IsWindowVisible(hwnd):
            return True
        user32.GetWindowTextW(hwnd, buf, 512)
        title = buf.value
        if any(kw.lower() in title.lower() for kw in keywords):
            result[0] = hwnd
            result[1] = title
            return False
        return True
    user32.EnumWindows(WNDENUMPROC(cb), 0)
    return result[0], result[1]

def focus(hwnd):
    """Restore and focus a window."""
    u = ctypes.windll.user32
    u.ShowWindow(hwnd, 9)  # SW_RESTORE
    time.sleep(0.3)
    u.SetForegroundWindow(hwnd)
    time.sleep(0.5)

def get_rect(hwnd):
    """Get window rect as (left, top, width, height)."""
    r = wintypes.RECT()
    ctypes.windll.user32.GetWindowRect(hwnd, ctypes.byref(r))
    return r.left, r.top, r.right - r.left, r.bottom - r.top

def click_rel(hwnd, x_pct, y_pct, desc=""):
    """Click at relative position within window (% of width/height)."""
    focus(hwnd)
    left, top, w, h = get_rect(hwnd)
    x = left + int(w * x_pct)
    y = top + int(h * y_pct)
    log(f"Click ({x},{y}) [win {w}x{h} at ({left},{top}), rel {x_pct:.2f},{y_pct:.2f}] - {desc}")
    pyautogui.click(x, y)

screen_w, screen_h = pyautogui.size()
log(f"Screen: {screen_w}x{screen_h}")
log("Starting Lobby Track install clicker (window-relative)")

# Minimize console
try:
    ch = ctypes.windll.kernel32.GetConsoleWindow()
    if ch:
        ctypes.windll.user32.ShowWindow(ch, 6)
except: pass

# Dismiss OneDrive / other popups
time.sleep(2)
pyautogui.press('escape')
time.sleep(1)

# Wait for installer process
log("Waiting for installer process...")
for i in range(120):
    r = subprocess.run(["tasklist"], capture_output=True, text=True)
    if "LobbyTrack" in r.stdout or "setup" in r.stdout.lower() or "msiexec" in r.stdout.lower():
        log("Installer process found")
        break
    time.sleep(1)

# Wait for wizard to render
log("Waiting 20s for wizard to render...")
time.sleep(20)
screenshot("01_initial")

# Helper: advance through wizard
INSTALLER_KEYWORDS = ["Lobby Track", "LobbyTrack", "InstallShield", "Jolly", "Setup"]

def advance_wizard(step_name, accept_license=False):
    """Focus installer window and advance through the current wizard page."""
    hwnd, title = find_window(*INSTALLER_KEYWORDS)
    if not hwnd:
        log(f"{step_name}: No window found, pressing Enter")
        pyautogui.press('enter')
        return

    focus(hwnd)
    rect = get_rect(hwnd)
    log(f"{step_name}: '{title}' rect={rect}")
    time.sleep(0.5)

    if accept_license:
        # Accept license: try Alt+A, then click radio button area, then Tab+Space
        pyautogui.hotkey('alt', 'a')
        time.sleep(0.5)
        # Radio button in license page: ~30% from left, ~72% from top of window
        click_rel(hwnd, 0.30, 0.72, "I accept radio")
        time.sleep(0.5)
        # Also try tabbing to radio and pressing Space
        for _ in range(5):
            pyautogui.press('tab')
            time.sleep(0.2)
        pyautogui.press('space')
        time.sleep(0.5)

    # Click Next/Install/Finish button area: ~85% from left, ~91% from top
    click_rel(hwnd, 0.85, 0.91, "Next/Install/Finish")
    time.sleep(0.5)
    # Backup: press Enter for default button
    pyautogui.press('enter')

# Step 1: Language selection — Enter to accept English default
log("Step 1: Language selection")
hwnd, title = find_window(*INSTALLER_KEYWORDS, "Choose", "Language", "Select")
if hwnd:
    focus(hwnd)
    log(f"Language window: '{title}' rect={get_rect(hwnd)}")
pyautogui.press('enter')
time.sleep(8)
screenshot("02_after_language")

# Step 2: .NET prerequisite / Welcome
advance_wizard("Step 2: Prereq/Welcome")
time.sleep(8)
screenshot("03_after_step2")

# Step 3: Welcome -> Next
advance_wizard("Step 3: Welcome Next")
time.sleep(8)
screenshot("04_after_step3")

# Step 4: License Agreement -> Accept + Next
advance_wizard("Step 4: License", accept_license=True)
time.sleep(8)
screenshot("05_after_license")

# Step 5: Destination folder -> Next
advance_wizard("Step 5: Destination")
time.sleep(8)
screenshot("06_after_dest")

# Step 6: Ready to install -> Install
advance_wizard("Step 6: Install")
time.sleep(10)
screenshot("07_installing")

# Wait for installation to complete (up to 15 min)
log("Waiting for installation to complete...")
for i in range(900):
    r = subprocess.run(["tasklist"], capture_output=True, text=True)
    has = any(kw in r.stdout for kw in ["LobbyTrack", "setup", "msiexec"])
    if not has:
        log("Installer process exited")
        break
    if i > 0 and i % 30 == 0:
        screenshot(f"08_wait_{i}")
        hwnd, title = find_window(*INSTALLER_KEYWORDS)
        if hwnd:
            focus(hwnd)
            time.sleep(0.5)
            # Try accept + next on whatever dialog is showing
            pyautogui.hotkey('alt', 'a')
            time.sleep(0.3)
            click_rel(hwnd, 0.30, 0.72, f"Periodic accept ({i}s)")
            time.sleep(0.3)
            click_rel(hwnd, 0.85, 0.91, f"Periodic Next ({i}s)")
            time.sleep(0.3)
            pyautogui.press('enter')
    time.sleep(1)
    if i % 60 == 0 and i > 0:
        log(f"  Still installing... ({i}s)")
else:
    log("WARNING: Installer still running after 900s")
    screenshot("09_timeout")
    advance_wizard("Timeout: Finish")
    time.sleep(10)

screenshot("10_final")
log("Install clicker complete")
with open(r"C:\Windows\Temp\install_clicker_done.txt", "w") as f:
    f.write("done")
'@

    [System.IO.File]::WriteAllText("C:\Windows\Temp\install_clicker.py", $clickerPy)

    # Create batch file that launches installer AND runs the clicker
    $batchContent = "@echo off`r`nstart `"`" `"$installerPath`"`r`n`"C:\Program Files\Python311\python.exe`" `"C:\Windows\Temp\install_clicker.py`""
    [System.IO.File]::WriteAllText("C:\Windows\Temp\install_and_click.bat", $batchContent)

    # Run via schtask in Session 1
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN "InstallLobbyTrackGUI" /TR "C:\Windows\Temp\install_and_click.bat" /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>&1
    schtasks /Run /TN "InstallLobbyTrackGUI" 2>&1
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
        Get-Process | Where-Object { $_.Name -match "LobbyTrack|setup|msiexec" } |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }

    # Print clicker log for debugging
    if (Test-Path "C:\Windows\Temp\install_clicker.log") {
        Write-Host "--- Clicker log ---"
        Get-Content "C:\Windows\Temp\install_clicker.log" | ForEach-Object { Write-Host "  $_" }
        Write-Host "---"
    }

    # Wait for installer to finalize
    Write-Host "Waiting for installer to finalize..."
    Start-Sleep -Seconds 15

    } # end if (-not $skipGUI)

    # ---- Verify installation ----
    Write-Host "Verifying Lobby Track installation..."
    $lobbyExe = $null
    foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            $lobbyExe = $p
            break
        }
    }

    if (-not $lobbyExe) {
        Write-Host "Searching for LobbyTrack executable..."
        $found = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse `
            -Filter "LobbyTrack*.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch "Setup|Uninstall" } |
            Select-Object -First 1
        if ($found) {
            $lobbyExe = $found.FullName
        }
    }

    if ($lobbyExe) {
        Write-Host "SUCCESS: Lobby Track installed at: $lobbyExe"
        [System.IO.File]::WriteAllText("C:\Users\Docker\lobbytrack_path.txt", $lobbyExe)
    } else {
        Write-Host "WARNING: Lobby Track executable not found after install"
        Write-Host "Listing Program Files for debugging..."
        Get-ChildItem "C:\Program Files" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name)" }
        Get-ChildItem "C:\Program Files (x86)" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name)" }

        # Try broader search
        $found = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse `
            -Filter "*.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "Lobby" -and $_.Name -notmatch "Setup|Uninstall" } |
            Select-Object -First 1
        if ($found) {
            $lobbyExe = $found.FullName
            Write-Host "Found via broader search: $lobbyExe"
            [System.IO.File]::WriteAllText("C:\Users\Docker\lobbytrack_path.txt", $lobbyExe)
        } else {
            Write-Host "ERROR: Lobby Track installation failed"
        }
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
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents" | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop" | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\LobbyTrack\data" | Out-Null

    # ---- Copy data files from workspace ----
    Write-Host "Copying visitor data files..."
    if (Test-Path "C:\workspace\data") {
        Copy-Item "C:\workspace\data\*" -Destination "C:\Users\Docker\LobbyTrack\data\" `
            -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ---- Cleanup temp files ----
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\install_clicker.py" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\install_and_click.bat" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\install_clicker.log" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\install_clicker_done.txt" -Force -ErrorAction SilentlyContinue

    Write-Host "=== Jolly Lobby Track installation complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
