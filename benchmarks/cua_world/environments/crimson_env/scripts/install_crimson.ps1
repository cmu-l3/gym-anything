Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Install Red Lion Crimson 3.0 HMI/SCADA configuration software.
# This script runs as the pre_start hook.

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing Red Lion Crimson 3.0 ==="

    # Check if Crimson is already installed
    # The main executable is c3.exe (not Crimson3.exe)
    $crimsonExe = $null
    $knownPath = "C:\Program Files (x86)\Red Lion Controls\Crimson 3.0\c3.exe"
    if (Test-Path $knownPath) {
        $crimsonExe = $knownPath
    }
    if (-not $crimsonExe) {
        $searchPaths = @(
            "C:\Program Files\Red Lion Controls",
            "C:\Program Files (x86)\Red Lion Controls"
        )
        foreach ($sp in $searchPaths) {
            if (Test-Path $sp) {
                $found = Get-ChildItem $sp -Recurse -Filter "c3.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    $crimsonExe = $found.FullName
                    break
                }
            }
        }
    }
    if ($crimsonExe) {
        Write-Host "Crimson is already installed at: $crimsonExe"
        return
    }

    # Create working directory for installer
    $workDir = "C:\CrimsonSetup"
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null

    # Download Crimson 3.0 installer (170 MB)
    Write-Host "Downloading Crimson 3.0 installer..."
    $installerUrl = "https://hmsnetworks.blob.core.windows.net/nlw/docs/default-source/products/redlion/monitored/software/crimson/crimson/c3/update/crimson-c3-gold-714-0.exe?sfvrsn=37ea67a8_9&download=true"
    $installerPath = "$workDir\crimson-c3-gold-714-0.exe"

    # Check if installer is available from workspace mount (pre-downloaded)
    $mountedInstaller = "C:\workspace\data\crimson-c3-gold-714-0.exe"
    $downloaded = $false

    if (Test-Path $mountedInstaller) {
        Write-Host "Installer found in workspace mount. Copying..."
        Copy-Item $mountedInstaller -Destination $installerPath -Force
        if ((Get-Item $installerPath).Length -gt 100000000) {
            $downloaded = $true
            Write-Host "Installer copied from workspace mount."
        }
    }

    if (-not $downloaded) {
        # Download using curl.exe (native Windows curl, much faster than Invoke-WebRequest)
        # Invoke-WebRequest buffers entire file in memory which stalls on large downloads
        $maxRetries = 3
        for ($i = 1; $i -le $maxRetries; $i++) {
            Write-Host "Download attempt $i of $maxRetries using curl.exe..."
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            & curl.exe -L -o $installerPath --retry 3 --connect-timeout 30 --max-time 600 $installerUrl 2>&1 | Write-Host
            $ErrorActionPreference = $prevEAP
            if ((Test-Path $installerPath) -and (Get-Item $installerPath).Length -gt 100000000) {
                $downloaded = $true
                Write-Host "Download completed successfully."
                break
            } else {
                Write-Host "WARNING: Downloaded file is too small or missing, retrying..."
                Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 5
            }
        }
    }

    if (-not $downloaded) {
        throw "Failed to download Crimson installer after all attempts."
    }

    # Install Crimson 3.0 silently
    # The Crimson 3.0 .exe is an NSIS-based installer; /S = silent mode
    Write-Host "Starting Crimson 3.0 installation (silent)... This may take 5-10 minutes."

    # Try NSIS silent flag first
    $process = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -PassThru -NoNewWindow
    Write-Host "Installation process exited with code: $($process.ExitCode)"

    # If NSIS silent mode didn't work (non-zero exit), try InnoSetup flags
    if ($process.ExitCode -ne 0) {
        Write-Host "NSIS /S flag returned non-zero exit. Trying /VERYSILENT..."
        $process = Start-Process -FilePath $installerPath -ArgumentList "/VERYSILENT /NORESTART /SUPPRESSMSGBOXES" -Wait -PassThru -NoNewWindow
        Write-Host "Installation process exited with code: $($process.ExitCode)"
    }

    # Allow exit code 3010 (reboot recommended) as success
    if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
        Write-Host "WARNING: Installer exited with code $($process.ExitCode). Checking if installation succeeded anyway..."
    }

    # Wait for installation to fully complete
    Start-Sleep -Seconds 10

    # Verify installation - the main executable is c3.exe
    $crimsonInstalled = $false
    $knownPath = "C:\Program Files (x86)\Red Lion Controls\Crimson 3.0\c3.exe"
    if (Test-Path $knownPath) {
        $crimsonExe = $knownPath
        $crimsonInstalled = $true
    }
    if (-not $crimsonInstalled) {
        $searchPaths = @(
            "C:\Program Files\Red Lion Controls",
            "C:\Program Files (x86)\Red Lion Controls"
        )
        foreach ($sp in $searchPaths) {
            if (Test-Path $sp) {
                $found = Get-ChildItem $sp -Recurse -Filter "c3.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    $crimsonExe = $found.FullName
                    $crimsonInstalled = $true
                    break
                }
            }
        }
    }

    if ($crimsonInstalled) {
        Write-Host "Crimson 3.0 installed successfully at: $crimsonExe"
    } else {
        Write-Host "ERROR: Could not find c3.exe after installation."
        Write-Host "Listing contents of C:\Program Files (x86) for debugging:"
        Get-ChildItem "C:\Program Files (x86)" -Directory -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  - $($_.Name)" }
    }

    # Cleanup installer
    Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "=== Crimson 3.0 installation complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
