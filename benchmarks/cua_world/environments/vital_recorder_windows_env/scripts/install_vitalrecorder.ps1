# install_vitalrecorder.ps1 - Pre-start hook: install Vital Recorder on Windows 11
# VitalRecorder is a free medical vital signs recording/analysis tool from VitalDB (Seoul National University Hospital)
# Download: MSI installer from https://vitaldb.net/getvr.php?type=msi&ver=1.16.6
# IMPORTANT: The MSI does an "advertised" install by default (files not extracted).
# Must use REINSTALL=ALL REINSTALLMODE=omus to force full file extraction.
# Install path: C:\Users\Docker\AppData\Roaming\VitalRecorder\Vital.exe
# Process name: Vital (NOT VitalRecorder)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing Vital Recorder ==="

    # Check if already installed (actual install path is AppData\Roaming)
    $vrExe = "C:\Users\Docker\AppData\Roaming\VitalRecorder\Vital.exe"

    if (Test-Path $vrExe) {
        Write-Host "Vital Recorder already installed at: $vrExe"
    } else {
        Write-Host "Downloading Vital Recorder MSI installer..."

        $msiPath = "C:\Windows\Temp\VitalRecorder.msi"

        # Download MSI from vitaldb.net
        $downloadUrl = "https://vitaldb.net/getvr.php?type=msi&ver=1.16.6"
        $fallbackUrl = "https://vitaldb.net/getvr.php?type=msi&ver=1.16.4"

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & curl.exe -L --silent --show-error --max-time 300 -o $msiPath $downloadUrl 2>&1
        $curlExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP

        if ($curlExit -ne 0 -or -not (Test-Path $msiPath) -or (Get-Item $msiPath).Length -lt 100000) {
            Write-Host "Primary download failed (exit=$curlExit). Trying fallback URL..."
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            & curl.exe -L --silent --show-error --max-time 300 -o $msiPath $fallbackUrl 2>&1
            $ErrorActionPreference = $prevEAP
        }

        if (-not (Test-Path $msiPath) -or (Get-Item $msiPath).Length -lt 100000) {
            throw "Failed to download Vital Recorder MSI installer"
        }

        $fileSize = (Get-Item $msiPath).Length
        Write-Host "Downloaded MSI: $([math]::Round($fileSize / 1MB, 1)) MB"

        # Step 1: Initial MSI install (creates advertised shortcuts)
        Write-Host "Step 1: Initial MSI install..."
        $proc = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart" -PassThru -Wait
        Write-Host "MSI initial install exit code: $($proc.ExitCode)"

        if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
            throw "MSI installation failed with exit code: $($proc.ExitCode)"
        }

        # Step 2: Force full file extraction (MSI advertised install fix)
        Write-Host "Step 2: Forcing full file extraction (REINSTALL=ALL)..."
        $proc2 = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart REINSTALL=ALL REINSTALLMODE=omus" -PassThru -Wait
        Write-Host "MSI reinstall exit code: $($proc2.ExitCode)"

        # Wait for files to appear
        Start-Sleep -Seconds 5

        # Verify installation
        if (Test-Path $vrExe) {
            Write-Host "Vital Recorder installed successfully at: $vrExe"
        } else {
            Write-Host "WARNING: Vital.exe not found at expected path. Searching..."
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            $searchResult = cmd /c "where /r C:\Users\Docker\AppData Vital.exe 2>nul"
            $ErrorActionPreference = $prevEAP
            if ($searchResult) {
                Write-Host "Found at: $searchResult"
            } else {
                Write-Host "ERROR: Vital.exe not found anywhere after installation"
            }
        }

        # Keep MSI for potential repair (don't delete)
    }

    # Copy real vital data files from workspace to a known location
    $dataDir = "C:\Users\Docker\Desktop\VitalRecorderData"
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null

    $sourceData = "C:\workspace\data"
    if (Test-Path $sourceData) {
        Write-Host "Copying vital data files to Desktop..."
        Copy-Item "$sourceData\*.vital" -Destination $dataDir -Force -ErrorAction SilentlyContinue
        $fileCount = (Get-ChildItem $dataDir -Filter "*.vital" -ErrorAction SilentlyContinue).Count
        Write-Host "Copied $fileCount .vital files to $dataDir"
    }

    Write-Host "=== Vital Recorder installation complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
