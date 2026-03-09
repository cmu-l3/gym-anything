# install_garmin_basecamp.ps1 - pre_start hook
# Installs Garmin BaseCamp 4.7.5 + Python automation stack

$ErrorActionPreference = "Continue"
$logFile = "C:\Users\Docker\env_setup_pre_start.log"
Start-Transcript -Path $logFile -Append | Out-Null

Write-Host "=== Garmin BaseCamp install started ==="

# Working dirs
$tmpDir  = "C:\temp\garmin_install"
$toolDir = "C:\GarminTools"
New-Item -ItemType Directory -Force -Path $tmpDir  | Out-Null
New-Item -ItemType Directory -Force -Path $toolDir | Out-Null

# --- 1. Install Garmin BaseCamp 4.7.5 ---
$bcExePaths = @(
    "C:\Program Files (x86)\Garmin\BaseCamp\BaseCamp.exe",
    "C:\Program Files\Garmin\BaseCamp\BaseCamp.exe"
)
$bcInstalled = $bcExePaths | Where-Object { Test-Path $_ }

if (-not $bcInstalled) {
    Write-Host "Downloading Garmin BaseCamp 4.7.5..."
    $bcInstaller = "$tmpDir\BaseCamp_475.exe"

    $urls = @(
        "https://download.garmin.com/software/BaseCamp_475.exe"
    )

    $downloaded = $false
    foreach ($url in $urls) {
        try {
            Write-Host "  Trying BITS: $url"
            # BITS is more reliable than Invoke-WebRequest for large files (avoids partial downloads)
            Start-BitsTransfer -Source $url -Destination $bcInstaller -ErrorAction Stop
            $fileSize = (Get-Item $bcInstaller -ErrorAction SilentlyContinue).Length
            # BaseCamp_475.exe is ~61MB; reject if too small (indicates partial/corrupt download)
            if ($fileSize -gt 50000000) {
                $downloaded = $true
                Write-Host "  Downloaded OK ($fileSize bytes)"
                break
            } else {
                Write-Host "  File too small via BITS: $fileSize bytes (expected ~61MB)"
                Remove-Item $bcInstaller -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Host "  BITS failed: $_, trying Invoke-WebRequest..."
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $url -OutFile $bcInstaller -UseBasicParsing -TimeoutSec 300
                $fileSize = (Get-Item $bcInstaller -ErrorAction SilentlyContinue).Length
                if ($fileSize -gt 50000000) {
                    $downloaded = $true
                    Write-Host "  Downloaded OK ($fileSize bytes)"
                    break
                } else {
                    Write-Host "  File too small via IWR: $fileSize bytes (expected ~61MB)"
                    Remove-Item $bcInstaller -ErrorAction SilentlyContinue
                }
            } catch {
                Write-Host "  IWR also failed: $_"
            }
        }
    }

    if (-not $downloaded) {
        Write-Host "ERROR: Could not download BaseCamp installer."
        Stop-Transcript | Out-Null
        exit 1
    }

    Write-Host "Installing BaseCamp silently..."
    $proc = Start-Process -FilePath $bcInstaller `
        -ArgumentList "/install /quiet /norestart" `
        -Wait -PassThru
    # Exit code 3010 = reboot recommended (NOT an error)
    if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
        Write-Host "BaseCamp installed successfully (exit=$($proc.ExitCode))"
    } else {
        Write-Host "WARNING: BaseCamp installer exited with code $($proc.ExitCode)"
    }

    # Verify installation
    $bcInstalled = $bcExePaths | Where-Object { Test-Path $_ }
    if (-not $bcInstalled) {
        $found = Get-ChildItem "C:\Program Files*" -Recurse -Filter "BaseCamp.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            Write-Host "BaseCamp found at: $($found.FullName)"
            $found.FullName | Set-Content "$toolDir\basecamp_path.txt"
        } else {
            Write-Host "WARNING: BaseCamp.exe not found after install"
        }
    } else {
        Write-Host "BaseCamp verified at: $($bcInstalled[0])"
        $bcInstalled[0] | Set-Content "$toolDir\basecamp_path.txt"
    }
} else {
    Write-Host "BaseCamp already installed at: $($bcInstalled[0])"
    $bcInstalled[0] | Set-Content "$toolDir\basecamp_path.txt"
}

# --- 2. Install Python 3.11 (for GUI automation) ---
# Python installs to "C:\Program Files\Python311\" when InstallAllUsers=1
$pythonExe = "C:\Program Files\Python311\python.exe"
if (-not (Test-Path $pythonExe)) {
    Write-Host "Downloading Python 3.11.9..."
    $pyInstaller = "$tmpDir\python-3.11.9-amd64.exe"
    try {
        Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" `
            -OutFile $pyInstaller -UseBasicParsing -TimeoutSec 300
        Write-Host "Installing Python 3.11.9..."
        $proc = Start-Process -FilePath $pyInstaller `
            -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" `
            -Wait -PassThru
        Write-Host "Python install exit code: $($proc.ExitCode)"
    } catch {
        Write-Host "WARNING: Python download/install failed: $_"
    }
} else {
    Write-Host "Python already at $pythonExe"
}

# --- 3. Install Python automation libraries ---
if (Test-Path $pythonExe) {
    Write-Host "Installing Python libraries (pyautogui, pywin32, pygetwindow)..."
    & $pythonExe -m pip install --upgrade pip --quiet 2>&1 | Out-Null
    & $pythonExe -m pip install pyautogui pywin32 pygetwindow Pillow 2>&1
    Write-Host "Python libraries install done."
} else {
    Write-Host "WARNING: Python not found - skipping library install"
}

# --- 4. Copy PyAutoGUI server to persistent location ---
if (Test-Path "C:\workspace\scripts\pyautogui_server.py") {
    Copy-Item "C:\workspace\scripts\pyautogui_server.py" "$toolDir\pyautogui_server.py" -Force
    Write-Host "Copied PyAutoGUI server to $toolDir"
}

# --- 5. Pre-create BaseCamp data directory ---
$bcDataDir = "C:\Users\Docker\AppData\Roaming\Garmin\BaseCamp\Database\4.7"
New-Item -ItemType Directory -Force -Path $bcDataDir | Out-Null
Write-Host "Pre-created BaseCamp data directory: $bcDataDir"

# --- 6. Cleanup temp files ---
Remove-Item "$tmpDir\BaseCamp_475.exe"       -ErrorAction SilentlyContinue
Remove-Item "$tmpDir\python-3.11.9-amd64.exe" -ErrorAction SilentlyContinue

Write-Host "=== Garmin BaseCamp install complete ==="
Stop-Transcript | Out-Null
