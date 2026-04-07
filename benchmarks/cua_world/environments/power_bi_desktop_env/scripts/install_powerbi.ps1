Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Installation script for Microsoft Power BI Desktop.
# This script runs during VM initialization (pre_start hook).

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing Power BI Desktop ==="

    # Check if Power BI Desktop is already installed
    $pbiPaths = @(
        "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe",
        "C:\Program Files (x86)\Microsoft Power BI Desktop\bin\PBIDesktop.exe"
    )

    $existingPath = $null
    foreach ($p in $pbiPaths) {
        if (Test-Path $p) {
            $existingPath = $p
            break
        }
    }

    if ($existingPath) {
        Write-Host "Power BI Desktop already installed at: $existingPath"
        Write-Host "=== Installation skipped (already present) ==="
    } else {
        Write-Host "Power BI Desktop not found. Downloading installer..."

        # Download Power BI Desktop installer
        $installerUrl = "https://download.microsoft.com/download/8/8/0/880BCA75-79DD-466A-927D-1ABF1F5454B0/PBIDesktopSetup_x64.exe"
        $installerPath = "C:\Windows\Temp\PBIDesktopSetup_x64.exe"

        Write-Host "Downloading from: $installerUrl"
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($installerUrl, $installerPath)

        if (-not (Test-Path $installerPath)) {
            throw "Failed to download Power BI Desktop installer"
        }
        $fileSize = (Get-Item $installerPath).Length / 1MB
        Write-Host "Download complete: $([math]::Round($fileSize, 1)) MB"

        if ($fileSize -lt 50) {
            Write-Host "WARNING: Installer file is suspiciously small ($([math]::Round($fileSize, 1)) MB). Retrying with curl..."
            Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
            curl.exe -L -o $installerPath $installerUrl --retry 3 --retry-delay 5 --connect-timeout 30 --max-time 600
            if (Test-Path $installerPath) {
                $fileSize = (Get-Item $installerPath).Length / 1MB
                Write-Host "Retry download: $([math]::Round($fileSize, 1)) MB"
            }
            if (-not (Test-Path $installerPath) -or $fileSize -lt 50) {
                throw "Power BI Desktop installer download failed (file too small or missing)"
            }
        }

        # Install silently
        Write-Host "Installing Power BI Desktop silently..."
        $installArgs = "-quiet -norestart ACCEPT_EULA=1 INSTALLDESKTOPSHORTCUT=0 DISABLE_UPDATE_NOTIFICATION=1 ENABLECXP=0"
        $proc = Start-Process $installerPath -ArgumentList $installArgs -PassThru -Wait
        Write-Host "Installer exit code: $($proc.ExitCode)"

        # Wait for background MSI operations to complete
        Start-Sleep -Seconds 10

        # Verify installation
        $installed = $false
        foreach ($p in $pbiPaths) {
            if (Test-Path $p) {
                Write-Host "Power BI Desktop installed at: $p"
                $installed = $true
                break
            }
        }

        if (-not $installed) {
            # Search more broadly
            $searchResult = Get-ChildItem "C:\Program Files" -Recurse -Filter "PBIDesktop.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($searchResult) {
                Write-Host "Power BI Desktop found at: $($searchResult.FullName)"
                $installed = $true
            } else {
                throw "Power BI Desktop installation failed - executable not found"
            }
        }

        # Clean up installer
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        Write-Host "Installer cleaned up."

        Write-Host "=== Power BI Desktop installation complete ==="
    }
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
