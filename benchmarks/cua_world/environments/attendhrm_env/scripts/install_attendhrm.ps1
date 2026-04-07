Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing AttendHRM (Lenvica HRMS) ==="

    # -------------------------------------------------------------------
    # Phase 1: Create working directories
    # -------------------------------------------------------------------
    $tempDir = "C:\temp\attendhrm_install"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop" | Out-Null
    Write-Host "Working directories created"

    # -------------------------------------------------------------------
    # Phase 2: Suppress startup apps that cause distracting popups
    # -------------------------------------------------------------------
    Write-Host "--- Suppressing startup apps ---"
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    # Uninstall OneDrive (30s timeout - NOT -Wait which can hang)
    $odrSetup = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    if (Test-Path $odrSetup) {
        $odrProc = Start-Process $odrSetup -ArgumentList "/uninstall" -PassThru -ErrorAction SilentlyContinue
        if ($odrProc) { $odrProc.WaitForExit(30000) }
    }

    # Disable OneDrive auto-start and prevent OneDrive setup dialogs
    Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    taskkill /F /IM OneDrive.exe 2>$null
    taskkill /F /IM OneDriveSetup.exe 2>$null

    # Remove OneDrive scheduled tasks to prevent re-launch
    schtasks /Delete /TN "OneDrive Reporting Task-S-1-5-21*" /F 2>$null
    schtasks /Delete /TN "OneDrive Standalone Update Task-S-1-5-21*" /F 2>$null
    Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "*OneDrive*" } | ForEach-Object {
        Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }

    # Prevent OneDrive setup from running on login
    $oneDriveSetupKey = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
    if (-not (Test-Path $oneDriveSetupKey)) { New-Item -Path $oneDriveSetupKey -Force 2>$null | Out-Null }
    New-ItemProperty -Path $oneDriveSetupKey -Name "KFMSilentOptIn" -Value "" -PropertyType String -Force 2>$null | Out-Null
    New-ItemProperty -Path $oneDriveSetupKey -Name "PreventNetworkTrafficPreUserSignIn" -Value 1 -PropertyType DWord -Force 2>$null | Out-Null

    # Remove OneDrive from startup in HKLM as well
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -Force -ErrorAction SilentlyContinue

    # Delete OneDriveSetup.exe to prevent it from ever running again
    Remove-Item "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:SystemRoot\System32\OneDriveSetup.exe" -Force -ErrorAction SilentlyContinue

    # Disable Windows startup notifications
    $toastPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications"
    if (-not (Test-Path $toastPath)) { New-Item -Path $toastPath -Force 2>$null | Out-Null }
    New-ItemProperty -Path $toastPath -Name "ToastEnabled" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null

    # Disable Windows 11 "Restart Apps" feature (stops apps re-opening after reboot)
    $winlogon = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    if (-not (Test-Path $winlogon)) { New-Item -Path $winlogon -Force 2>$null | Out-Null }
    New-ItemProperty -Path $winlogon -Name "DisableAutomaticRestartSignOn" -Value 1 -PropertyType DWord -Force 2>$null | Out-Null
    $userWinlogon = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    if (-not (Test-Path $userWinlogon)) { New-Item -Path $userWinlogon -Force 2>$null | Out-Null }
    New-ItemProperty -Path $userWinlogon -Name "RestartApps" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null

    $ErrorActionPreference = $prevEAP
    Write-Host "Startup apps suppressed"

    # -------------------------------------------------------------------
    # Phase 3: Download AttendHRM Lite installer (~287 MB)
    #   Primary URL confirmed live (HTTP 200) on 2026-02-24:
    #     https://www.lenvica.com/download/AttendHRM-Attendance-Lite-Setup.exe
    # -------------------------------------------------------------------
    Write-Host "--- Downloading AttendHRM Attendance Lite installer ---"
    $installerPath = "$tempDir\AttendHRM-Attendance-Lite-Setup.exe"

    $downloadUrls = @(
        "https://www.lenvica.com/download/AttendHRM-Attendance-Lite-Setup.exe",
        "https://lenvica.com/download/AttendHRM-Attendance-Lite-Setup.exe"
    )

    $downloaded = $false
    foreach ($url in $downloadUrls) {
        try {
            Write-Host "Trying: $url"
            # Use curl.exe (ships with Windows 10/11) for reliable large-file downloads.
            # Invoke-WebRequest buffers the entire file in memory and hangs on large files.
            $curlArgs = @("--retry", "3", "--retry-delay", "5", "-L", "--max-time", "600",
                          "-o", $installerPath, $url)
            $proc = Start-Process "curl.exe" -ArgumentList $curlArgs -Wait -PassThru -ErrorAction SilentlyContinue
            if ((Test-Path $installerPath) -and (Get-Item $installerPath).Length -gt 100MB) {
                $sizeMB = [Math]::Round((Get-Item $installerPath).Length / 1MB, 1)
                Write-Host "Downloaded successfully from $url ($sizeMB MB)"
                $downloaded = $true
                break
            } else {
                Write-Host "Download incomplete from $url (file too small), trying next..."
                Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Host "Failed from ${url}: $($_.Exception.Message)"
        }
    }

    # Fallback: use installer from mounted data directory (if manually placed)
    if (-not $downloaded) {
        $mountedInstaller = "C:\workspace\data\AttendHRM-Attendance-Lite-Setup.exe"
        if (Test-Path $mountedInstaller) {
            Write-Host "Using installer from mounted data directory: $mountedInstaller"
            Copy-Item $mountedInstaller $installerPath -Force
            $downloaded = $true
        }
    }

    if (-not $downloaded) {
        throw "ERROR: AttendHRM installer could not be downloaded. Download manually from https://lenvica.com/download-attendhrm/ and place at examples/attendhrm_env/data/AttendHRM-Attendance-Lite-Setup.exe"
    }

    # -------------------------------------------------------------------
    # Phase 4: Install AttendHRM silently (Inno Setup installer)
    #   /VERYSILENT    - hides all windows and progress
    #   /SUPPRESSMSGBOXES - suppresses all message boxes
    #   /NORESTART     - prevents automatic reboot
    #   /SP-           - suppresses "This will install..." pre-prompt
    #
    # IMPORTANT: The AttendHRM Inno Setup installer has a [Run] section that
    # launches Attend.exe after installation and waits for it to exit. In a
    # headless (Session 0) environment, Attend.exe never exits on its own,
    # causing -Wait to block indefinitely. We use a background job to kill
    # any Attend.exe launched by the installer every 10 seconds.
    # -------------------------------------------------------------------
    Write-Host "--- Installing AttendHRM silently (this may take 2-5 minutes) ---"
    $killJob = Start-Job -ScriptBlock {
        for ($i = 0; $i -lt 120; $i++) {
            Start-Sleep -Seconds 5
            Stop-Process -Name "Attend" -Force -ErrorAction SilentlyContinue
        }
    }
    try {
        $installResult = Start-Process $installerPath `
            -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-" `
            -Wait -PassThru
        $exitCode = $installResult.ExitCode
    } finally {
        Stop-Job $killJob -ErrorAction SilentlyContinue
        Remove-Job $killJob -Force -ErrorAction SilentlyContinue
    }

    # Exit code 0 = success, 3010 = "reboot recommended" (app works without reboot)
    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Host "AttendHRM installation succeeded (exit code: $exitCode)"
    } else {
        throw "AttendHRM installation failed with exit code: $exitCode"
    }

    # -------------------------------------------------------------------
    # Phase 5: Verify installation and locate Attend.exe
    # -------------------------------------------------------------------
    Write-Host "--- Verifying AttendHRM installation ---"

    $attendExe = $null
    $candidatePaths = @(
        "C:\Program Files (x86)\Attend HRM\Bin\Attend.exe",  # actual install path (verified)
        "C:\Program Files (x86)\Attend HRM\Attend.exe",
        "C:\Program Files\Attend HRM\Bin\Attend.exe",
        "C:\Program Files\Attend HRM\Attend.exe",
        "C:\Program Files (x86)\AttendHRM\Attend.exe",
        "C:\Program Files\AttendHRM\Attend.exe",
        "C:\Program Files (x86)\Lenvica\Attend HRM\Attend.exe"
    )
    foreach ($p in $candidatePaths) {
        if (Test-Path $p) {
            $attendExe = $p
            break
        }
    }

    if (-not $attendExe) {
        # Recursive search as last resort
        $found = Get-ChildItem "C:\Program Files (x86)", "C:\Program Files" -Recurse -Filter "Attend.exe" `
            -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -notmatch "unins" } | Select-Object -First 1
        if ($found) { $attendExe = $found.FullName }
    }

    if ($attendExe) {
        Write-Host "AttendHRM found at: $attendExe"
        # Save path for use by setup script and tasks
        Set-Content -Path "C:\Users\Docker\attendhrm_path.txt" -Value $attendExe -Encoding UTF8
        Write-Host "Executable path saved to C:\Users\Docker\attendhrm_path.txt"
    } else {
        throw "ERROR: Attend.exe not found after installation. Check install log."
    }

    # -------------------------------------------------------------------
    # Phase 6: Verify Firebird database service
    #   Firebird is bundled with AttendHRM and starts as a Windows service.
    # -------------------------------------------------------------------
    Write-Host "--- Checking Firebird database service ---"
    $prevEAP3 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $fbSvc = Get-Service | Where-Object { $_.Name -like "*Firebird*" } | Select-Object -First 1
    if ($fbSvc) {
        Write-Host "Firebird service found: $($fbSvc.Name) (status: $($fbSvc.Status))"
        if ($fbSvc.Status -ne "Running") {
            try {
                Start-Service $fbSvc.Name
                Write-Host "Firebird service started"
            } catch {
                Write-Host "WARNING: Could not start Firebird service: $($_.Exception.Message)"
            }
        }
    } else {
        Write-Host "NOTE: Firebird service not yet visible (may start after reboot or delay)"
    }

    $ErrorActionPreference = $prevEAP3

    # -------------------------------------------------------------------
    # Phase 7: Add Firebird client DLLs to system PATH
    # AttendHRM needs fbclient.dll / gds32.dll on PATH to connect to Firebird.
    # -------------------------------------------------------------------
    Write-Host "--- Adding Firebird to system PATH ---"
    $fbBinDirs = @(
        "C:\Program Files (x86)\Firebird\Firebird_5_0",
        "C:\Program Files (x86)\Firebird\Firebird_5_0\bin",
        "C:\Program Files (x86)\Attend HRM\Firebird"
    )
    $currentPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    foreach ($dir in $fbBinDirs) {
        if ((Test-Path $dir) -and ($currentPath -notlike "*$dir*")) {
            $currentPath = "$currentPath;$dir"
            Write-Host "Added to PATH: $dir"
        }
    }
    [System.Environment]::SetEnvironmentVariable("Path", $currentPath, "Machine")

    # -------------------------------------------------------------------
    # Phase 8: Cleanup installer to free disk space
    # -------------------------------------------------------------------
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    Write-Host "Installer cleaned up"

    Write-Host "=== AttendHRM Installation Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
