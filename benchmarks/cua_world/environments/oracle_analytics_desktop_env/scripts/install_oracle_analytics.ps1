Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Installation script for Oracle Analytics Desktop (January 2026 Update).
# This script runs during VM initialization (pre_start hook).
# The installer EXE must be pre-staged in data/ since Oracle requires SSO login to download.

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing Oracle Analytics Desktop ==="

    # Check if Oracle Analytics Desktop is already installed
    $oadPaths = @(
        "C:\Program Files\Oracle Analytics Desktop\bi\bifoundation\web\bin\OAD.exe",
        "C:\Program Files\Oracle Analytics Desktop\OAD.exe",
        "C:\Program Files (x86)\Oracle Analytics Desktop\OAD.exe"
    )

    $existingPath = $null
    foreach ($p in $oadPaths) {
        if (Test-Path $p) {
            $existingPath = $p
            break
        }
    }

    # Also search common install locations
    if (-not $existingPath) {
        $searchDirs = @(
            "C:\Program Files\Oracle Analytics Desktop",
            "C:\Program Files (x86)\Oracle Analytics Desktop",
            "C:\Users\Docker\AppData\Local\OracleAnalyticsDesktop"
        )
        foreach ($dir in $searchDirs) {
            if (Test-Path $dir) {
                $found = Get-ChildItem $dir -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match "OAD|dvdesktop|analyticsdesktop" -or $_.Name -match "Oracle.*Analytics" } |
                    Select-Object -First 1
                if ($found) {
                    $existingPath = $found.FullName
                    break
                }
            }
        }
    }

    if ($existingPath) {
        Write-Host "Oracle Analytics Desktop already installed at: $existingPath"
        Write-Host "=== Installation skipped (already present) ==="
    } else {
        Write-Host "Oracle Analytics Desktop not found. Installing from pre-staged installer..."

        # Look for installer EXE in workspace data directory (pre-staged)
        $installerSource = $null
        $candidates = @(
            "C:\workspace\data\Oracle_Analytics_Desktop_January2026_Win.exe",
            "C:\workspace\data\Oracle_Analytics_Desktop_Win.exe",
            "C:\workspace\data\Oracle_Analytics_Desktop_2026_Win.exe"
        )
        # Also search for any OAD installer in data dir
        $wildcardSearch = Get-ChildItem "C:\workspace\data\" -Filter "Oracle_Analytics_Desktop*Win*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($wildcardSearch) {
            $candidates = @($wildcardSearch.FullName) + $candidates
        }

        foreach ($candidate in $candidates) {
            if (Test-Path $candidate) {
                $installerSource = $candidate
                break
            }
        }

        if (-not $installerSource) {
            Write-Host "WARNING: Oracle Analytics Desktop installer not found in C:\workspace\data\"
            Write-Host "Please download the installer from https://www.oracle.com/solutions/analytics/analytics-desktop/oracle-analytics-desktop.html"
            Write-Host "(requires Oracle SSO login) and place the .exe file in the data/ directory as:"
            Write-Host "  examples/oracle_analytics_desktop_env/data/Oracle_Analytics_Desktop_Win.exe"
            Write-Host "Continuing with system setup (OneDrive, Windows Update cleanup)..."
        } else {
            $installerPath = "C:\Windows\Temp\Oracle_Analytics_Desktop_Win.exe"
            Write-Host "Copying installer from $installerSource ..."
            Copy-Item $installerSource -Destination $installerPath -Force

            if (-not (Test-Path $installerPath)) {
                throw "Failed to stage Oracle Analytics Desktop installer"
            }
            $fileSize = (Get-Item $installerPath).Length / 1MB
            Write-Host "Installer ready: $([math]::Round($fileSize, 1)) MB"

            # Install Oracle Analytics Desktop
            # OAD uses Oracle Universal Installer (OUI). Try multiple silent install approaches.
            Write-Host "Installing Oracle Analytics Desktop (this may take 10-15 minutes)..."

            # Create OUI response file for silent install
            $rspFile = "C:\Windows\Temp\oad_install.rsp"
            $oracleHome = "C:\Program Files\Oracle Analytics Desktop"
            @"
[ENGINE]
Response File Version=1.0.0.0.0

[GENERIC]
ORACLE_HOME=$oracleHome
INSTALL_TYPE=Complete
DECLINE_SECURITY_UPDATES=true
SECURITY_UPDATES_VIA_MYORACLESUPPORT=false
"@ | Out-File -FilePath $rspFile -Encoding ascii -Force

            # Attempt 1: OUI silent mode with response file
            Write-Host "Attempt 1: OUI silent install with response file..."
            $proc = Start-Process $installerPath -ArgumentList "-silent -responseFile $rspFile -nowait" -PassThru
            $proc.WaitForExit(900000)  # 15 minute timeout
            if (-not $proc.HasExited) {
                Write-Host "Installer timed out, killing..."
                $proc.Kill()
            }
            Write-Host "Installer exit code: $($proc.ExitCode)"

            # If attempt 1 failed, try without response file
            if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
                Write-Host "Attempt 2: OUI silent install without response file..."
                $proc2 = Start-Process $installerPath -ArgumentList "-silent -nowait" -PassThru
                $proc2.WaitForExit(900000)
                if (-not $proc2.HasExited) {
                    $proc2.Kill()
                }
                Write-Host "Installer (attempt 2) exit code: $($proc2.ExitCode)"
            }

            # If OUI failed, try InstallShield flags
            $oadInstalled = Test-Path $oracleHome
            if (-not $oadInstalled) {
                Write-Host "Attempt 3: InstallShield silent install..."
                $proc3 = Start-Process $installerPath -ArgumentList "/S /v`"/qn ACCEPT_EULA=YES INSTALLDIR=\`"$oracleHome\`"`"" -PassThru
                $proc3.WaitForExit(900000)
                if (-not $proc3.HasExited) {
                    $proc3.Kill()
                }
                Write-Host "Installer (attempt 3) exit code: $($proc3.ExitCode)"
            }

            # Verify installation by searching for the executable
            $installed = $false

            # Re-check known paths
            foreach ($p in $oadPaths) {
                if (Test-Path $p) {
                    Write-Host "Oracle Analytics Desktop installed at: $p"
                    $installed = $true
                    break
                }
            }

            if (-not $installed) {
                # Search more broadly
                $searchResult = Get-ChildItem "C:\Program Files" -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match "OAD|dvdesktop|analyticsdesktop" } |
                    Select-Object -First 1
                if (-not $searchResult) {
                    $searchResult = Get-ChildItem "C:\Program Files (x86)" -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -match "OAD|dvdesktop|analyticsdesktop" } |
                        Select-Object -First 1
                }
                if (-not $searchResult) {
                    # Check AppData\Local (some versions install here)
                    $searchResult = Get-ChildItem "C:\Users\Docker\AppData\Local" -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -match "OAD|dvdesktop|analyticsdesktop|Oracle.*Analytics" } |
                        Select-Object -First 1
                }
                if ($searchResult) {
                    Write-Host "Oracle Analytics Desktop found at: $($searchResult.FullName)"
                    $installed = $true
                }
            }

            if (-not $installed) {
                Write-Host "WARNING: Could not verify Oracle Analytics Desktop installation."
                Write-Host "Checking for any Oracle Analytics-related directories..."
                Get-ChildItem "C:\Program Files" -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match "Oracle" } | ForEach-Object {
                        Write-Host "  Found: $($_.FullName)"
                    }
                Get-ChildItem "C:\Program Files (x86)" -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match "Oracle" } | ForEach-Object {
                        Write-Host "  Found: $($_.FullName)"
                    }
            }

            # Clean up installer
            Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
            Write-Host "Installer cleaned up."

            Write-Host "=== Oracle Analytics Desktop installation complete ==="
        }
    }

    # Disable Windows Update to prevent interference
    Write-Host "Disabling Windows Update service..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Stop-Service wuauserv -Force 2>$null
    Set-Service wuauserv -StartupType Disabled 2>$null
    $ErrorActionPreference = $prevEAP

    # Disable OneDrive auto-start and uninstall
    Write-Host "Disabling OneDrive..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    # Kill OneDrive process
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # Disable OneDrive via registry
    $regPaths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive",
        "HKLM:\SOFTWARE\Microsoft\OneDrive"
    )
    foreach ($rp in $regPaths) {
        if (-not (Test-Path $rp)) {
            New-Item -Path $rp -Force 2>$null | Out-Null
        }
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -Value 1 -Type DWord 2>$null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableLibrariesDefaultSaveToOneDrive" -Value 1 -Type DWord 2>$null

    # Remove OneDrive autorun entries
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue 2>$null
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -ErrorAction SilentlyContinue 2>$null

    # Remove OneDrive scheduled tasks
    Get-ScheduledTask -TaskName "*OneDrive*" -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue 2>$null

    # Uninstall OneDrive
    $onedrivePaths = @(
        "C:\Windows\SysWOW64\OneDriveSetup.exe",
        "C:\Windows\System32\OneDriveSetup.exe"
    )
    foreach ($odPath in $onedrivePaths) {
        if (Test-Path $odPath) {
            $odProc = Start-Process $odPath -ArgumentList "/uninstall" -PassThru
            if (-not $odProc.WaitForExit(30000)) {
                $odProc.Kill()
            }
            break
        }
    }
    $ErrorActionPreference = $prevEAP

    Write-Host "=== Pre-start setup complete ==="

} catch {
    Write-Host "ERROR in install script: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    throw
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
