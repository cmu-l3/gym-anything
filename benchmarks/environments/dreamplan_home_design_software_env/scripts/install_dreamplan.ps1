Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Pre-start script for NCH DreamPlan Home Design Software.
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
    Write-Host "=== DreamPlan Pre-Start: Download and Stage ==="

    # Check if DreamPlan is already installed (NCH standard path)
    $dreamplanExe = $null
    $searchPaths = @(
        "C:\Program Files (x86)\NCH Software\DreamPlan\dreamplan.exe",
        "C:\Program Files\NCH Software\DreamPlan\dreamplan.exe",
        "C:\Program Files (x86)\NCH Software\DreamPlan\DreamPlan.exe",
        "C:\Program Files\NCH Software\DreamPlan\DreamPlan.exe"
    )

    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $dreamplanExe = $path
            break
        }
    }

    if ($dreamplanExe) {
        Write-Host "DreamPlan already installed at: $dreamplanExe"
        $dreamplanExe | Out-File -FilePath "C:\Users\Docker\dreamplan_exe_path.txt" -Encoding ASCII -Force
    } else {
        Write-Host "DreamPlan not found. Downloading installer..."

        $installerPath = "C:\Windows\Temp\designsetup.exe"

        # Check if installer is pre-staged in data directory
        $preStagedNames = @("designsetup.exe", "designpsetup.exe")
        $preStaged = $null
        foreach ($name in $preStagedNames) {
            $candidate = "C:\workspace\data\$name"
            if (Test-Path $candidate) {
                $preStaged = $candidate
                break
            }
        }

        if ($preStaged) {
            Write-Host "Using pre-staged installer from data directory: $preStaged"
            Copy-Item $preStaged -Destination $installerPath -Force
        } else {
            # Download from NCH Software (free version for non-commercial use)
            $urls = @(
                "https://www.nchsoftware.com/design/designsetup.exe",
                "https://www.nch.com.au/design/designsetup.exe"
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
                throw "Failed to download DreamPlan installer from all sources."
            }
        }

        $fileSize = (Get-Item $installerPath).Length / 1MB
        Write-Host "Installer staged at: $installerPath ($([math]::Round($fileSize, 2)) MB)"
    }

    # Stage any optional data files (floor plans, etc.) if present in data/
    $dataDir = "C:\Users\Docker\Documents\DreamPlanData"
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
    if (Test-Path "C:\workspace\data") {
        $files = Get-ChildItem "C:\workspace\data" -Exclude "*.exe" -ErrorAction SilentlyContinue
        if ($files) {
            $files | ForEach-Object {
                Copy-Item $_.FullName -Destination $dataDir -Force
                Write-Host "Copied data file: $($_.Name)"
            }
        }
    }

    Write-Host "=== Pre-start complete ==="

} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
