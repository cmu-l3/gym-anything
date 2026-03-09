Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Install Blue Sky Plan 5.0 dental implant planning software.
# This script runs as the pre_start hook (SSH Session 0).
# Key: installer MUST run via schtasks /IT since Session 0 has no GUI.
# Key: curl.exe progress goes to stderr which kills $ErrorActionPreference="Stop".
#      Always use --silent --show-error and wrap in ErrorActionPreference="Continue".

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing Blue Sky Plan ==="

    # --- Step 1: Check if Blue Sky Plan is already installed ---
    $launcherExe = "C:\Program Files\BlueSkyPlan\Launcher\BlueSkyLauncher.exe"
    if (Test-Path $launcherExe) {
        Write-Host "Blue Sky Plan is already installed at: $launcherExe"
        # Still need to set up Mesa OpenGL and DICOM data, skip to Step 4
    } else {
        # --- Step 2: Download Blue Sky Plan installer ---
        $workDir = "C:\BSPSetup"
        New-Item -ItemType Directory -Force -Path $workDir | Out-Null

        $curlExe = "C:\Windows\System32\curl.exe"
        $installerUrl = "https://manual.blueskyplan.com/catalogs/BSP/BlueSkyPlan_5.0.29-setup64.exe"
        $installerPath = "$workDir\BlueSkyPlan_5.0.29-setup64.exe"

        Write-Host "Downloading Blue Sky Plan 5.0.29 installer..."
        # CRITICAL: curl.exe writes progress to stderr. With $ErrorActionPreference="Stop",
        # PowerShell treats stderr output as a terminating error. Must use --silent --show-error
        # AND temporarily set ErrorActionPreference to Continue.
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & $curlExe -L --silent --show-error --max-time 900 --connect-timeout 30 -o $installerPath $installerUrl 2>&1
        $curlExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP

        if ($curlExit -ne 0 -or -not (Test-Path $installerPath) -or (Get-Item $installerPath).Length -lt 1000000) {
            Write-Host "Primary download failed (exit $curlExit). Trying fallback version..."
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            $fallbackUrl = "https://manual.blueskyplan.com/catalogs/BSP/BlueSkyPlan_5.0.28-setup64.exe"
            & $curlExe -L --silent --show-error --max-time 900 --connect-timeout 30 -o $installerPath $fallbackUrl 2>&1
            $ErrorActionPreference = $prevEAP
        }

        if (-not (Test-Path $installerPath)) {
            throw "Installer download failed - file not found"
        }
        $fileSize = (Get-Item $installerPath).Length
        Write-Host "Installer downloaded: $([math]::Round($fileSize / 1MB, 1)) MB"

        # --- Step 3: Install via schtasks /IT (interactive session) ---
        Write-Host "Starting installation via interactive session..."

        $installBat = "C:\Windows\Temp\install_bsp.cmd"
        $installArgs = "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /SP-"
        $batContent = "@echo off`r`n`"$installerPath`" $installArgs`r`necho INSTALL_EXIT_CODE=%ERRORLEVEL% > C:\Windows\Temp\bsp_install_result.txt"
        [System.IO.File]::WriteAllText($installBat, $batContent)

        $taskName = "InstallBSP_GA"
        $prevEAP = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            schtasks /Delete /TN $taskName /F 2>&1 | Out-Null
            schtasks /Create /TN $taskName /TR "cmd /c $installBat" /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>&1 | Out-Null
            schtasks /Run /TN $taskName 2>&1 | Out-Null
        } finally {
            $ErrorActionPreference = $prevEAP
        }

        Write-Host "Installer launched. Waiting for completion..."

        # Poll for completion
        $maxWaitSec = 600
        $elapsed = 0
        $installed = $false
        while ($elapsed -lt $maxWaitSec) {
            Start-Sleep -Seconds 10
            $elapsed += 10

            if (Test-Path "C:\Windows\Temp\bsp_install_result.txt") {
                $resultContent = Get-Content "C:\Windows\Temp\bsp_install_result.txt" -Raw
                Write-Host "Install result: $resultContent"
                $installed = $true
                break
            }

            if (Test-Path $launcherExe) {
                Write-Host "BSP Launcher detected at: $launcherExe after ${elapsed}s"
                # Wait extra time: the installer creates Launcher/ first, then BlueSkyPlan4/.
                # Breaking too early means BlueSkyPlan4 may not be fully populated yet.
                Write-Host "Waiting 30s more for installer to finish all directories..."
                Start-Sleep -Seconds 30
                $installed = $true
                break
            }

            if ($elapsed % 60 -eq 0) {
                Write-Host "  Still waiting... (${elapsed}s elapsed)"
            }
        }

        # Cleanup
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        schtasks /Delete /TN $taskName /F 2>&1 | Out-Null
        Remove-Item $installBat -Force -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\Temp\bsp_install_result.txt" -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP

        if (-not $installed) {
            Write-Host "WARNING: Installation may not have completed within ${maxWaitSec}s."
        }

        # Verify
        if (Test-Path $launcherExe) {
            Write-Host "Blue Sky Plan installed successfully."
        } else {
            Write-Host "WARNING: BlueSkyLauncher.exe not found after installation."
        }
    }

    # --- Step 4: Set up Mesa OpenGL for QEMU ---
    # QEMU's virtio-vga only supports OpenGL ~3.x, but BSP requires 4.3+.
    # BSP ships with opengl32sw.dll (Mesa LLVMPipe, supports OpenGL 4.5).
    # Copy it as opengl32.dll so Windows loads it via DLL search order.
    Write-Host ""
    Write-Host "=== Setting up Mesa software OpenGL ==="
    # Source DLL: installer only ships opengl32sw.dll in Launcher, not in BlueSkyPlan4
    $sourceDll = "C:\Program Files\BlueSkyPlan\Launcher\opengl32sw.dll"
    $bspDirs = @(
        "C:\Program Files\BlueSkyPlan\Launcher",
        "C:\Program Files\BlueSkyPlan\BlueSkyPlan4"
    )
    foreach ($dir in $bspDirs) {
        if (-not (Test-Path $dir)) { continue }
        $targetDll = "$dir\opengl32.dll"
        if (-not (Test-Path $targetDll)) {
            $localSw = "$dir\opengl32sw.dll"
            if (Test-Path $localSw) {
                Copy-Item $localSw $targetDll -Force
            } elseif (Test-Path $sourceDll) {
                Copy-Item $sourceDll $targetDll -Force
            }
            if (Test-Path $targetDll) {
                Write-Host "Copied opengl32sw.dll -> opengl32.dll in $dir"
            }
        } else {
            Write-Host "opengl32.dll already exists in $dir"
        }
    }
    # Set global environment variables
    [System.Environment]::SetEnvironmentVariable("QT_OPENGL", "software", "Machine")
    [System.Environment]::SetEnvironmentVariable("MESA_GL_VERSION_OVERRIDE", "4.5", "Machine")
    Write-Host "Mesa OpenGL configured."

    # --- Step 5: Set up DICOM data ---
    Write-Host ""
    Write-Host "=== Setting up DICOM data ==="
    $dicomDir = "C:\Users\Docker\Documents\DentalDICOM"
    New-Item -ItemType Directory -Force -Path $dicomDir | Out-Null

    # First try to copy from mounted workspace data (most reliable)
    if (Test-Path "C:\workspace\data\dicom") {
        Write-Host "Copying DICOM data from workspace..."
        Copy-Item "C:\workspace\data\dicom\*" -Destination $dicomDir -Recurse -Force -ErrorAction SilentlyContinue
        $fileCount = (Get-ChildItem $dicomDir -Recurse -File -Filter "*.dcm" -ErrorAction SilentlyContinue).Count
        if ($fileCount -gt 0) {
            Write-Host "Copied $fileCount DICOM files from workspace."
        }
    }

    # Check if we have DICOM files already
    $existingDcm = (Get-ChildItem $dicomDir -Recurse -File -ErrorAction SilentlyContinue).Count
    if ($existingDcm -lt 5) {
        Write-Host "Downloading DICOM data from rubomedical..."
        $curlExe = "C:\Windows\System32\curl.exe"
        $workDir = "C:\BSPSetup"
        New-Item -ItemType Directory -Force -Path $workDir -ErrorAction SilentlyContinue | Out-Null

        # Download multiple DICOM samples to build a series
        $dicomUrls = @(
            "https://www.rubomedical.com/dicom_files/dicom_viewer_0002.zip",
            "https://www.rubomedical.com/dicom_files/dicom_viewer_0003.zip"
        )
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $idx = 0
        foreach ($url in $dicomUrls) {
            $zipFile = "$workDir\dicom_$idx.zip"
            & $curlExe -L --silent --show-error --max-time 120 --connect-timeout 15 -o $zipFile $url 2>&1
            if ($LASTEXITCODE -eq 0 -and (Test-Path $zipFile) -and (Get-Item $zipFile).Length -gt 1000) {
                try {
                    Expand-Archive -Path $zipFile -DestinationPath $dicomDir -Force
                    Write-Host "Extracted DICOM data from $url"
                } catch {
                    Write-Host "Extract failed for $url : $($_.Exception.Message)"
                }
            }
            $idx++
        }
        $ErrorActionPreference = $prevEAP
    }

    $totalFiles = (Get-ChildItem $dicomDir -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-Host "DICOM directory: $dicomDir ($totalFiles files)"

    # Cleanup installer files
    Remove-Item -Path "C:\BSPSetup" -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "=== Blue Sky Plan installation complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
