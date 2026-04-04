Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Installation script for NinjaTrader 8 (v8.0.28.0).
# This script runs during VM initialization (pre_start hook).
# Uses version 8.0.28.0 which does NOT require mandatory login (unlike 8.1.x).

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing NinjaTrader 8 (v8.0.28.0) ==="

    # Check if NinjaTrader is already installed
    $ntPaths = @(
        "C:\Program Files (x86)\NinjaTrader 8\bin64\NinjaTrader.exe",
        "C:\Program Files (x86)\NinjaTrader 8\bin\NinjaTrader.exe",
        "C:\Program Files\NinjaTrader 8\bin64\NinjaTrader.exe",
        "C:\Program Files\NinjaTrader 8\bin\NinjaTrader.exe"
    )

    $existingPath = $null
    foreach ($p in $ntPaths) {
        if (Test-Path $p) {
            $existingPath = $p
            break
        }
    }

    if ($existingPath) {
        Write-Host "NinjaTrader already installed at: $existingPath"
        Write-Host "=== Installation skipped (already present) ==="
    } else {
        Write-Host "NinjaTrader not found. Installing from MSI..."

        # Look for MSI in workspace data directory (pre-staged)
        $msiSource = $null
        $msiCandidates = @(
            "C:\workspace\data\NinjaTrader.Install.V8.msi",
            "C:\workspace\data\NinjaTrader.Install.msi"
        )
        foreach ($candidate in $msiCandidates) {
            if (Test-Path $candidate) {
                $msiSource = $candidate
                break
            }
        }
        $msiPath = "C:\Windows\Temp\NinjaTrader.Install.V8.msi"

        if ($msiSource) {
            Write-Host "Copying MSI from $msiSource ..."
            Copy-Item $msiSource -Destination $msiPath -Force
        } else {
            throw "NinjaTrader MSI not found in C:\workspace\data\. Please place NinjaTrader.Install.V8.msi in the data directory."
        }

        if (-not (Test-Path $msiPath)) {
            throw "Failed to stage NinjaTrader MSI installer"
        }
        $fileSize = (Get-Item $msiPath).Length / 1MB
        Write-Host "MSI ready: $([math]::Round($fileSize, 1)) MB"

        # Install silently via msiexec
        Write-Host "Installing NinjaTrader silently..."
        $proc = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart" -PassThru -Wait
        Write-Host "Installer exit code: $($proc.ExitCode)"

        # Verify installation
        $installed = $false
        foreach ($p in $ntPaths) {
            if (Test-Path $p) {
                Write-Host "NinjaTrader installed at: $p"
                $installed = $true
                break
            }
        }

        if (-not $installed) {
            # Search more broadly
            $searchResult = Get-ChildItem "C:\Program Files (x86)" -Recurse -Filter "NinjaTrader.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $searchResult) {
                $searchResult = Get-ChildItem "C:\Program Files" -Recurse -Filter "NinjaTrader.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            if ($searchResult) {
                Write-Host "NinjaTrader found at: $($searchResult.FullName)"
                $installed = $true
            } else {
                throw "NinjaTrader installation failed - executable not found"
            }
        }

        # Clean up installer
        Remove-Item $msiPath -Force -ErrorAction SilentlyContinue
        Write-Host "Installer cleaned up."

        Write-Host "=== NinjaTrader 8 installation complete ==="
    }
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
