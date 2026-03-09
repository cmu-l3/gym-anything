Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Pre-start script for NCH Copper Point of Sale Software.
# This runs in SSH Session 0 (no GUI access).
# Downloads the installer and stages data files.
# Actual GUI installation happens in post_start via PyAutoGUI.
# NCH installers do NOT support silent install flags.

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Copper POS Pre-Start: Download and Stage ==="

    # Check if Copper is already installed
    $copperExe = "C:\Program Files (x86)\NCH Software\Copper\copper.exe"
    if (Test-Path $copperExe) {
        Write-Host "Copper POS already installed at: $copperExe"
        Write-Host "Saving exe path for later use..."
        $copperExe | Out-File -FilePath "C:\Users\Docker\copper_exe_path.txt" -Encoding ASCII -Force
    } else {
        Write-Host "Copper POS not found. Downloading installer..."

        $installerPath = "C:\Windows\Temp\possetup.exe"

        # Check if installer is pre-staged in data directory
        $preStaged = "C:\workspace\data\possetup.exe"
        if (Test-Path $preStaged) {
            Write-Host "Using pre-staged installer from data directory..."
            Copy-Item $preStaged -Destination $installerPath -Force
        } else {
            # Download from NCH Software
            $urls = @(
                "https://www.nchsoftware.com/point-of-sale/possetupfree.exe",
                "https://www.nchsoftware.com/point-of-sale/possetup.exe"
            )

            $downloaded = $false
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            foreach ($url in $urls) {
                Write-Host "Attempting download from: $url"
                try {
                    & curl.exe --silent --show-error --location --output $installerPath $url 2>&1
                    if ((Test-Path $installerPath) -and (Get-Item $installerPath).Length -gt 100000) {
                        $downloaded = $true
                        Write-Host "Download successful from: $url"
                        break
                    } else {
                        Write-Host "Download too small or failed from: $url"
                        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
                    }
                } catch {
                    Write-Host "Download failed from ${url}: $($_.Exception.Message)"
                }
            }
            $ErrorActionPreference = $prevEAP

            if (-not $downloaded) {
                throw "Failed to download Copper POS installer from all sources."
            }
        }

        $fileSize = (Get-Item $installerPath).Length / 1MB
        Write-Host "Installer staged at: $installerPath ($([math]::Round($fileSize, 2)) MB)"
    }

    # Copy data files to a known location for task setup
    $dataDir = "C:\Users\Docker\Documents\CopperData"
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    if (Test-Path "C:\workspace\data") {
        Get-ChildItem "C:\workspace\data" -Filter "*.csv" | ForEach-Object {
            Copy-Item $_.FullName -Destination $dataDir -Force
            Write-Host "Copied data file: $($_.Name)"
        }
    }
    Write-Host "Data files staged at: $dataDir"

    Write-Host "=== Pre-start complete ==="

} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
