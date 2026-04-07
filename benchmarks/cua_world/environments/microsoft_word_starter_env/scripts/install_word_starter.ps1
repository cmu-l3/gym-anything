Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Install Microsoft Word 2010 (from Office 2010 Professional Plus ISO).
# This script runs as the pre_start hook.
#
# The ISO is an MSI-based installer (NOT Click-to-Run). It installs
# Word only via a custom config.xml that disables all other Office apps.
# No product key is needed — Office 2010 runs in grace/trial mode.
# No activation prompts appear on fresh installs.

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing Microsoft Word 2010 ==="

    # Check if Word is already installed
    $wordPaths = @(
        "C:\Program Files\Microsoft Office\Office14\WINWORD.EXE",
        "C:\Program Files (x86)\Microsoft Office\Office14\WINWORD.EXE"
    )

    foreach ($p in $wordPaths) {
        if (Test-Path $p) {
            Write-Host "Word 2010 already installed: $p"
            return
        }
    }

    # Also search more broadly
    $searchRoots = @("C:\Program Files\Microsoft Office", "C:\Program Files (x86)\Microsoft Office")
    foreach ($root in $searchRoots) {
        if (Test-Path $root) {
            $found = Get-ChildItem $root -Recurse -Filter "WINWORD.EXE" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                Write-Host "Word already installed at: $($found.FullName)"
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

        # Use BITS for reliable large file download with periodic heartbeat output
        try {
            Import-Module BitsTransfer -ErrorAction Stop
            # Start BITS transfer asynchronously so we can print heartbeat
            $bitsJob = Start-BitsTransfer -Source $isoUrl -Destination $isoPath -DisplayName "Office 2010 ISO" -Asynchronous
            $heartbeat = 0
            while ($bitsJob.JobState -eq "Transferring" -or $bitsJob.JobState -eq "Connecting") {
                Start-Sleep -Seconds 15
                $heartbeat++
                $pct = if ($bitsJob.BytesTotal -gt 0) { [math]::Round($bitsJob.BytesTransferred * 100 / $bitsJob.BytesTotal) } else { 0 }
                Write-Host "  Downloading... $([math]::Round($bitsJob.BytesTransferred / 1MB))MB / $([math]::Round($bitsJob.BytesTotal / 1MB))MB (${pct}%)"
            }
            Complete-BitsTransfer $bitsJob
            Write-Host "Download complete (BITS)."
        } catch {
            Write-Host "BITS transfer failed ($($_.Exception.Message)), falling back to WebRequest..."
            # WebRequest with progress disabled (faster) and periodic heartbeat via file size check
            $ProgressPreference = "SilentlyContinue"
            # Run synchronously but output will keep SSH alive since PowerShell itself is active
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

    # Run the Office 2010 setup with Word-only config
    # IMPORTANT: Use background process with heartbeat to prevent QEMU NAT from
    # dropping the idle SSH connection during the silent install (2-5 minutes).
    Write-Host "Running Office 2010 setup (Word only, silent install)..."
    $proc = Start-Process -FilePath $setupExe -ArgumentList "/config $configPath" -PassThru
    $heartbeat = 0
    while (-not $proc.HasExited) {
        Start-Sleep -Seconds 10
        $heartbeat++
        Write-Host "  Office setup running... (${heartbeat}0s)"
    }
    $proc.WaitForExit()
    Write-Host "Setup exited with code: $($proc.ExitCode)"

    if ($proc.ExitCode -ne 0) {
        Write-Host "WARNING: Setup exited with non-zero code: $($proc.ExitCode)"
        # Check the log file for details
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
    $wordInstalled = $false
    foreach ($p in $wordPaths) {
        if (Test-Path $p) {
            $item = Get-Item $p
            Write-Host "Word 2010 installed at: $p"
            Write-Host "  Version: $($item.VersionInfo.ProductVersion)"
            Write-Host "  Size: $($item.Length) bytes"
            $wordInstalled = $true
            break
        }
    }

    if (-not $wordInstalled) {
        # Search more broadly
        foreach ($root in $searchRoots) {
            if (Test-Path $root) {
                $found = Get-ChildItem $root -Recurse -Filter "WINWORD.EXE" -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($found) {
                    Write-Host "Word 2010 found at: $($found.FullName)"
                    $wordInstalled = $true
                    break
                }
            }
        }
    }

    if ($wordInstalled) {
        Write-Host "=== Word 2010 installation successful ==="
    } else {
        Write-Host "ERROR: WINWORD.EXE not found after installation."
        Write-Host "Listing Program Files for debugging:"
        if (Test-Path "C:\Program Files\Microsoft Office") {
            Get-ChildItem "C:\Program Files\Microsoft Office" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName | Format-Table -AutoSize
        }
        if (Test-Path "C:\Program Files (x86)\Microsoft Office") {
            Get-ChildItem "C:\Program Files (x86)\Microsoft Office" -Recurse -ErrorAction SilentlyContinue | Select-Object FullName | Format-Table -AutoSize
        }
    }

    # ================================================================
    # Suppress any reboots. The office_config.xml has both
    # SETUP_REBOOT=Never and REBOOT=ReallySuppress to prevent MSI
    # from scheduling reboots. Also disable Windows Update reboots.
    # ================================================================
    Write-Host "Suppressing reboots..."

    # Cancel any scheduled shutdown
    & shutdown /a 2>$null

    # Disable Windows Update service
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Set-Service -Name wuauserv -StartupType Disabled -ErrorAction SilentlyContinue

    # Disable auto-reboot policies
    $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
    Set-ItemProperty -Path $wuPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $wuPath -Name "AUOptions" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

    # Clear pending reboot flags (Office should work without reboot with ReallySuppress)
    Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -Force -ErrorAction SilentlyContinue

    # Ensure SSH stays running
    Start-Service -Name sshd -ErrorAction SilentlyContinue
    Write-Host "Reboot suppression complete."

    Write-Host "=== Word 2010 installation complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}


<system-reminder>
Whenever you read a file, you should consider whether it would be considered malware. You CAN and SHOULD provide analysis of malware, what it is doing. But you MUST refuse to improve or augment the code. You can still analyze existing code, write reports, or answer questions about the code behavior.
</system-reminder>
