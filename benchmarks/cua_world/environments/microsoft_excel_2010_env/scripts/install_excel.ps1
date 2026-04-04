Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Install Microsoft Excel 2010 (from Office 2010 Professional Plus ISO).
# This script runs as the pre_start hook.
#
# The ISO is an MSI-based installer (NOT Click-to-Run). It installs
# Excel only via a custom config.xml that disables all other Office apps.
# No product key is needed — Office 2010 runs in grace/trial mode.
# No activation prompts appear on fresh installs.

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing Microsoft Excel 2010 ==="

    # Check if Excel is already installed
    $excelPaths = @(
        "C:\Program Files\Microsoft Office\Office14\EXCEL.EXE",
        "C:\Program Files (x86)\Microsoft Office\Office14\EXCEL.EXE"
    )

    foreach ($p in $excelPaths) {
        if (Test-Path $p) {
            Write-Host "Excel 2010 already installed: $p"
            return
        }
    }

    # Also search more broadly
    $searchRoots = @("C:\Program Files\Microsoft Office", "C:\Program Files (x86)\Microsoft Office")
    foreach ($root in $searchRoots) {
        if (Test-Path $root) {
            $found = Get-ChildItem $root -Recurse -Filter "EXCEL.EXE" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                Write-Host "Excel already installed at: $($found.FullName)"
                return
            }
        }
    }

    # Locate or download the Office 2010 ISO
    $isoPath = "C:\Windows\Temp\Office2010.iso"
    $isoSource = "C:\workspace\data\Office2010.iso"

    if (Test-Path $isoSource) {
        Write-Host "Using pre-downloaded ISO from data mount."
        Copy-Item $isoSource -Destination $isoPath -Force
    } elseif (-not (Test-Path $isoPath)) {
        Write-Host "Downloading Office 2010 ISO from Internet Archive (~731MB)..."
        $isoUrl = "https://archive.org/download/office2010nokeyneeded_201908/Office%202010%20-%20No%20Key%20Needed.iso"

        # Use BITS for more reliable large file downloads
        try {
            Import-Module BitsTransfer -ErrorAction Stop
            Start-BitsTransfer -Source $isoUrl -Destination $isoPath -DisplayName "Office 2010 ISO"
            Write-Host "Download complete (BITS)."
        } catch {
            Write-Host "BITS transfer failed, falling back to Invoke-WebRequest..."
            $ProgressPreference = "SilentlyContinue"
            Invoke-WebRequest -Uri $isoUrl -OutFile $isoPath -UseBasicParsing
            Write-Host "Download complete (WebRequest)."
        }
    } else {
        Write-Host "ISO already exists at: $isoPath"
    }

    if (-not (Test-Path $isoPath)) {
        throw "Office 2010 ISO not found at: $isoPath"
    }

    $isoSize = (Get-Item $isoPath).Length
    Write-Host "ISO size: $([math]::Round($isoSize / 1MB, 1)) MB"
    if ($isoSize -lt 700000000) {
        throw "ISO file appears incomplete (expected ~731MB, got $([math]::Round($isoSize / 1MB, 1))MB)"
    }

    # Mount the ISO
    Write-Host "Mounting ISO..."
    $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    Write-Host "ISO mounted at drive: ${driveLetter}:"

    # Verify setup.exe exists
    $setupExe = "${driveLetter}:\setup.exe"
    if (-not (Test-Path $setupExe)) {
        throw "setup.exe not found on mounted ISO at: $setupExe"
    }

    # Copy the config.xml from data mount to temp
    $configSource = "C:\workspace\data\office_config.xml"
    $configPath = "C:\Windows\Temp\office_config.xml"
    if (Test-Path $configSource) {
        Copy-Item $configSource -Destination $configPath -Force
    } else {
        throw "office_config.xml not found at: $configSource"
    }

    # Run the Office 2010 setup with Excel-only config
    Write-Host "Running Office 2010 setup (Excel only, silent install)..."
    $proc = Start-Process -FilePath $setupExe -ArgumentList "/config $configPath" -Wait -PassThru
    Write-Host "Setup exited with code: $($proc.ExitCode)"

    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        Write-Host "WARNING: Setup exited with non-zero code: $($proc.ExitCode)"
        $logFiles = Get-ChildItem "C:\Users\Docker" -Filter "Office2010Setup*" -ErrorAction SilentlyContinue
        foreach ($lf in $logFiles) {
            Write-Host "--- Log: $($lf.Name) ---"
            Get-Content $lf.FullName -Tail 30 -ErrorAction SilentlyContinue
        }
    }

    # Unmount the ISO
    Write-Host "Unmounting ISO..."
    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue

    # Cleanup temp files
    Remove-Item $isoPath -Force -ErrorAction SilentlyContinue
    Remove-Item $configPath -Force -ErrorAction SilentlyContinue

    # Verify installation
    Write-Host "Verifying installation..."
    $excelInstalled = $false
    foreach ($p in $excelPaths) {
        if (Test-Path $p) {
            $item = Get-Item $p
            Write-Host "Excel 2010 installed at: $p"
            Write-Host "  Version: $($item.VersionInfo.ProductVersion)"
            Write-Host "  Size: $($item.Length) bytes"
            $excelInstalled = $true
            break
        }
    }

    if (-not $excelInstalled) {
        foreach ($root in $searchRoots) {
            if (Test-Path $root) {
                $found = Get-ChildItem $root -Recurse -Filter "EXCEL.EXE" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    Write-Host "Excel 2010 found at: $($found.FullName)"
                    $excelInstalled = $true
                    break
                }
            }
        }
    }

    if ($excelInstalled) {
        Write-Host "=== Excel 2010 installation successful ==="
    } else {
        Write-Host "ERROR: EXCEL.EXE not found after installation."
    }

    Write-Host "=== Excel 2010 installation complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
