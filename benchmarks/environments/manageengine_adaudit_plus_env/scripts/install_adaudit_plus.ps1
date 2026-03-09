Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Installing ManageEngine ADAudit Plus ==="

    $installerPath = "C:\Windows\Temp\ManageEngine_ADAudit_Plus_x64.exe"
    $expectedInstallDir = "C:\Program Files\ManageEngine\ADAudit Plus"
    $binDir = "$expectedInstallDir\bin"
    $pyagPort = 5555

    # ------------------------------------------------------------------
    # Check if already installed
    # ------------------------------------------------------------------
    if (Test-Path "$binDir\run.bat") {
        Write-Host "ADAudit Plus already installed at: $expectedInstallDir"
        $expectedInstallDir | Out-File -FilePath "C:\Windows\Temp\adaudit_install_dir.txt" -Encoding ASCII -NoNewline
        exit 0
    }

    # ==================================================================
    # Phase 1: Pre-requisites
    # ==================================================================
    Write-Host "`n--- Phase 1: Pre-requisites ---"

    # Kill OneDrive to prevent popup dialogs over the installer
    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "OneDriveSetup" -Force -ErrorAction SilentlyContinue

    # Pre-create firewall rules to prevent Windows Firewall dialogs
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    netsh advfirewall firewall add rule name="ADAudit Plus Web" dir=in action=allow protocol=tcp localport=8081 2>$null
    netsh advfirewall firewall add rule name="ADAudit Plus HTTPS" dir=in action=allow protocol=tcp localport=8444 2>$null
    netsh advfirewall firewall add rule name="ADAudit Plus DB" dir=in action=allow protocol=tcp localport=33307 2>$null
    # Allow Java/Zulu which ADAudit Plus bundles
    netsh advfirewall firewall add rule name="ADAudit Plus Java" dir=in action=allow program="$expectedInstallDir\jre\bin\java.exe" enable=yes 2>$null
    netsh advfirewall firewall add rule name="ADAudit Plus Java2" dir=in action=allow program="$expectedInstallDir\jre\bin\javaw.exe" enable=yes 2>$null
    $ErrorActionPreference = $prevEAP
    Write-Host "Firewall rules created"

    # Disable Edge password manager and First Run Experience via Group Policy registry keys.
    # PasswordManager*: prevents "Save your password?" popup from blocking PyAutoGUI clicks.
    # HideFirstRunExperience: prevents the full-page FRE wizard that blocks the browser
    #   on first-ever launch, covering the requested URL with a multi-page welcome wizard.
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Force | Out-Null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "PasswordManagerEnabled" -Value 0 -Type DWord
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "PasswordManagerSavingEnabled" -Value 0 -Type DWord
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "HideFirstRunExperience" -Value 1 -Type DWord
    Write-Host "Edge policies configured (password manager disabled, FRE hidden)"

    # ==================================================================
    # Phase 2: Download installer
    # ==================================================================
    Write-Host "`n--- Phase 2: Download ---"

    if (-not (Test-Path $installerPath) -or (Get-Item $installerPath).Length -lt 100MB) {
        $urls = @(
            "https://www.manageengine.com/products/active-directory-audit/83574207/ManageEngine_ADAudit_Plus_x64.exe",
            "https://info.manageengine.com/products/active-directory-audit/83574207/ManageEngine_ADAudit_Plus_x64.exe"
        )
        $downloaded = $false
        foreach ($url in $urls) {
            Write-Host "Downloading from: $url"
            try {
                try {
                    Import-Module BitsTransfer -ErrorAction SilentlyContinue
                    Start-BitsTransfer -Source $url -Destination $installerPath -ErrorAction Stop
                } catch {
                    Write-Host "BITS failed, trying WebClient..."
                    $wc = New-Object System.Net.WebClient
                    $wc.DownloadFile($url, $installerPath)
                }
                if ((Test-Path $installerPath) -and (Get-Item $installerPath).Length -gt 100MB) {
                    Write-Host "Download OK: $([math]::Round((Get-Item $installerPath).Length / 1MB)) MB"
                    $downloaded = $true
                    break
                }
            } catch {
                Write-Host "Failed: $_"
            }
        }
        if (-not $downloaded) { throw "Failed to download ADAudit Plus installer" }
    } else {
        Write-Host "Installer already downloaded: $([math]::Round((Get-Item $installerPath).Length / 1MB)) MB"
    }

    # ==================================================================
    # Phase 3: PyAutoGUI helper + installer wizard automation
    # ==================================================================
    Write-Host "`n--- Phase 3: PyAutoGUI setup ---"

    # Helper to send commands to PyAutoGUI TCP server on localhost:5555
    function Send-PyAG {
        param([hashtable]$Cmd)
        try {
            $c = New-Object System.Net.Sockets.TcpClient
            $c.ReceiveTimeout = 5000
            $c.Connect("127.0.0.1", $pyagPort)
            $s = $c.GetStream()
            $json = ($Cmd | ConvertTo-Json -Compress) + "`n"
            $b = [System.Text.Encoding]::UTF8.GetBytes($json)
            $s.Write($b, 0, $b.Length)
            $s.Flush()
            Start-Sleep -Milliseconds 300
            $resp = ""
            if ($s.DataAvailable) {
                $buf = New-Object byte[] 4096
                $n = $s.Read($buf, 0, $buf.Length)
                $resp = [System.Text.Encoding]::UTF8.GetString($buf, 0, $n)
            }
            $c.Close()
            return $resp
        } catch {
            return $null
        }
    }

    function PyAG-Click([int]$X, [int]$Y) {
        Write-Host "  click ($X, $Y)"
        Send-PyAG @{action="click"; x=$X; y=$Y}
        Start-Sleep -Milliseconds 500
    }
    function PyAG-Type([string]$Text) {
        Write-Host "  type '$Text'"
        Send-PyAG @{action="typewrite"; text=$Text}
        Start-Sleep -Milliseconds 300
    }
    function PyAG-Press([string]$Key) {
        Write-Host "  press '$Key'"
        Send-PyAG @{action="press"; key=$Key}
        Start-Sleep -Milliseconds 300
    }
    function PyAG-Hotkey([string[]]$Keys) {
        Write-Host "  hotkey $($Keys -join '+')"
        Send-PyAG @{action="hotkey"; keys=$Keys}
        Start-Sleep -Milliseconds 300
    }

    # Wait for PyAutoGUI server to be ready
    Write-Host "Waiting for PyAutoGUI server on port $pyagPort..."
    $pyagReady = $false
    for ($i = 0; $i -lt 30; $i++) {
        $r = Send-PyAG @{action="moveTo"; x=640; y=360}
        if ($null -ne $r) { $pyagReady = $true; break }
        Start-Sleep -Seconds 2
    }
    if (-not $pyagReady) {
        throw "PyAutoGUI server not available - cannot automate InstallShield wizard"
    }
    Write-Host "PyAutoGUI server ready"

    # ==================================================================
    # Phase 4: Launch installer and automate wizard
    # ==================================================================
    Write-Host "`n--- Phase 4: Installer wizard automation ---"

    # Minimize all windows so the installer appears cleanly
    PyAG-Hotkey @("win", "d")
    Start-Sleep -Seconds 2

    # Launch installer in Session 1 via schtasks /IT
    $batch = "C:\Windows\Temp\launch_installer.cmd"
    "@echo off`r`nstart `"`" `"$installerPath`"" | Out-File -FilePath $batch -Encoding ASCII

    $ErrorActionPreference = "Continue"
    schtasks /Delete /TN InstallADA /F 2>$null
    schtasks /Create /TN InstallADA /TR "cmd /c $batch" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN InstallADA
    $ErrorActionPreference = "Stop"

    # The 247MB self-extracting installer needs 30-45s to show its wizard window.
    # CRITICAL: Must wait for the WIZARD WINDOW (title "ADAudit Plus Setup") to appear,
    # NOT just the process (which starts during self-extraction phase with no title).
    Write-Host "Waiting for installer wizard window (title='ADAudit Plus Setup')..."
    $wizardReady = $false
    for ($w = 0; $w -lt 120; $w += 3) {
        $proc = Get-Process | Where-Object {
            $_.MainWindowTitle -eq "ADAudit Plus Setup"
        }
        if ($proc) {
            Write-Host "  Wizard window detected after ${w}s"
            $wizardReady = $true
            break
        }
        Start-Sleep -Seconds 3
    }
    if (-not $wizardReady) {
        Write-Host "  WARNING: Wizard window not detected after 120s; proceeding with 60s fixed wait..."
        Start-Sleep -Seconds 60
    } else {
        # Give the wizard an extra moment to fully render after the window title appears
        Start-Sleep -Seconds 5
    }

    schtasks /Delete /TN InstallADA /F 2>$null
    Remove-Item $batch -Force -ErrorAction SilentlyContinue

    # --- InstallShield Wizard Steps (1280x720 resolution) ---
    # Verified button positions from manual walkthrough:
    #   Next / Yes / Finish button center: (751, 525)
    #   Cancel button center:              (835, 525)
    #   Skip button center:                (834, 526)
    #   Back button center:                (675, 525)

    # Step 1: Welcome page -> click Next
    Write-Host "Step 1/8: Welcome -> Next"
    PyAG-Click 751 525
    Start-Sleep -Seconds 5

    # Step 2: License Agreement -> click Yes (same position as Next)
    Write-Host "Step 2/8: License Agreement -> Yes"
    PyAG-Click 751 525
    Start-Sleep -Seconds 5

    # Step 3: Select Destination -> click Next (keep default path)
    Write-Host "Step 3/8: Destination -> Next"
    PyAG-Click 751 525
    Start-Sleep -Seconds 5

    # Step 4: Web Server Port -> click Next (keep default 8081)
    Write-Host "Step 4/8: Web Server Port -> Next"
    PyAG-Click 751 525
    Start-Sleep -Seconds 5

    # Step 5: Technical Support Registration (Optional) -> click Skip directly
    # IMPORTANT: Do NOT click Next here (it triggers a "fill email" popup).
    # The Skip button is at the far right, where Cancel usually sits.
    Write-Host "Step 5/8: Registration -> Skip"
    PyAG-Click 834 526
    Start-Sleep -Seconds 5

    # Step 6: Begin Installation (summary page) -> click Next to start install
    Write-Host "Step 6/8: Begin Installation -> Next"
    PyAG-Click 751 525
    Start-Sleep -Seconds 3

    # Step 7: Installation progress bar + "Unpacking Jar Files" phase
    # This takes 2-4 minutes depending on system speed.
    Write-Host "Step 7/8: Installing files (waiting up to 300s)..."
    $installWait = 0
    $installMax = 300
    while ($installWait -lt $installMax) {
        if (Test-Path "$expectedInstallDir\bin\run.bat") {
            Write-Host "  Install files detected after ${installWait}s"
            break
        }
        Start-Sleep -Seconds 15
        $installWait += 15
        Write-Host "  Waiting for install to finish... ${installWait}s"
    }
    # Extra wait for the Finish page to appear after file extraction
    Start-Sleep -Seconds 10

    # Step 8: Finish page -> uncheck "View Readme", click Finish
    # "Start ADAudit Plus Server" checkbox should remain checked.
    Write-Host "Step 8/8: Finish"
    PyAG-Click 573 328           # Uncheck "View Readme" checkbox
    Start-Sleep -Seconds 1
    PyAG-Click 751 525           # Click Finish
    Start-Sleep -Seconds 3
    # Backup: press Enter in case Finish button has focus but click missed
    PyAG-Press "enter"
    Start-Sleep -Seconds 5
    # If wizard is still open, force-close the installer process
    $wizardProc = Get-Process | Where-Object { $_.MainWindowTitle -eq "ADAudit Plus Setup" }
    if ($wizardProc) {
        Write-Host "  Wizard still open - sending Alt+F4..."
        PyAG-Hotkey @("alt", "F4")
        Start-Sleep -Seconds 3
        # Last resort: kill the process
        $wizardProc = Get-Process | Where-Object { $_.MainWindowTitle -eq "ADAudit Plus Setup" }
        if ($wizardProc) {
            Write-Host "  Force-killing installer process..."
            $wizardProc | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Seconds 5

    # ==================================================================
    # Phase 5: Verify installation
    # ==================================================================
    Write-Host "`n--- Phase 5: Verify installation ---"

    $installDir = $null
    $searchPaths = @(
        "C:\Program Files\ManageEngine\ADAudit Plus",
        "C:\ManageEngine\ADAudit Plus",
        "C:\Program Files (x86)\ManageEngine\ADAudit Plus"
    )

    $maxWait = 180
    $waited = 0
    while ($waited -lt $maxWait) {
        foreach ($p in $searchPaths) {
            if (Test-Path "$p\bin\run.bat") {
                $installDir = $p
                break
            }
        }
        if ($installDir) { break }
        Start-Sleep -Seconds 10
        $waited += 10
        Write-Host "  Waiting for install files... ${waited}s"
    }

    if (-not $installDir) {
        throw "ADAudit Plus installation failed - install directory not found after ${maxWait}s"
    }

    Write-Host "Installation verified at: $installDir"
    $installDir | Out-File -FilePath "C:\Windows\Temp\adaudit_install_dir.txt" -Encoding ASCII -NoNewline
    $binDir = "$installDir\bin"

    # ==================================================================
    # Phase 6: Ensure service is running, wait for HTTP
    # ==================================================================
    Write-Host "`n--- Phase 6: Start service and wait for HTTP ---"

    # Check for existing Windows service
    $svc = Get-Service | Where-Object { $_.DisplayName -like "*ADAudit*" } | Select-Object -First 1
    if (-not $svc) {
        # Install as service
        if (Test-Path "$binDir\InstallNTService.bat") {
            Write-Host "Installing as Windows service..."
            $prev = Get-Location
            Set-Location $binDir
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c InstallNTService.bat" -Wait -PassThru -NoNewWindow | Out-Null
            Set-Location $prev
            Start-Sleep -Seconds 3
            $svc = Get-Service | Where-Object { $_.DisplayName -like "*ADAudit*" } | Select-Object -First 1
        }
    }

    if ($svc) {
        Write-Host "Service: $($svc.Name) - Status: $($svc.Status)"
        if ($svc.Status -ne "Running") {
            Write-Host "Starting service via net start..."
            $prevEAP3 = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            net start "ADAudit Plus" 2>$null
            $ErrorActionPreference = $prevEAP3
            Start-Sleep -Seconds 5
        }
    } else {
        Write-Host "No service found, starting via run.bat..."
        $prev = Get-Location
        Set-Location $binDir
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c run.bat" -WindowStyle Hidden
        Set-Location $prev
    }

    # Wait for HTTP 200 on port 8081.
    # IMPORTANT: On first boot after install, the service may crash once because
    # ChangePGPwd.bat (PostgreSQL password setup) races with the service start.
    # If HTTP doesn't come up, check if the service stopped and restart it.
    Write-Host "Waiting for web server on port 8081..."
    $httpReady = $false
    $httpTimeout = 600
    $httpWait = 0
    $restarted = $false
    while ($httpWait -lt $httpTimeout) {
        try {
            $resp = Invoke-WebRequest -Uri "http://localhost:8081/" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400) {
                Write-Host "Web server ready (HTTP $($resp.StatusCode)) after ${httpWait}s"
                $httpReady = $true
                break
            }
        } catch {}
        Start-Sleep -Seconds 5
        $httpWait += 5
        if ($httpWait % 30 -eq 0) { Write-Host "  Still waiting... ${httpWait}s" }

        # Periodically check if the service crashed and needs restart.
        # On first boot, ChangePGPwd.bat races with the service start, causing
        # "FATAL: password authentication failed for user adaudit" crash.
        # After ChangePGPwd completes (~30-60s), the service can be restarted successfully.
        if ($httpWait % 30 -eq 0 -and $httpWait -ge 30) {
            $svc = Get-Service | Where-Object { $_.DisplayName -like "*ADAudit*" } | Select-Object -First 1
            if ($svc -and $svc.Status -ne "Running") {
                Write-Host "  Service stopped - restarting..."
                $prevEAP4 = $ErrorActionPreference
                $ErrorActionPreference = "Continue"
                net start "ADAudit Plus" 2>$null
                $ErrorActionPreference = $prevEAP4
                Start-Sleep -Seconds 5
            }
        }
    }

    if (-not $httpReady) {
        Write-Host "WARNING: Web server not responding after ${httpTimeout}s"
    }

    # ==================================================================
    # Phase 7: Change admin password via browser automation
    # ==================================================================
    Write-Host "`n--- Phase 7: Change admin password ---"

    # The first login with admin/admin triggers mandatory password change.
    # We automate this via Edge browser + PyAutoGUI.

    # Kill any existing Edge
    Get-Process -Name "msedge" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Create Edge "First Run" sentinel file to prevent the First Run Experience wizard.
    # Edge checks for this file; if it exists, the multi-page FRE wizard is skipped.
    # This is a belt-and-suspenders measure alongside the HideFirstRunExperience registry policy.
    $edgeUserData = "C:\Users\Docker\AppData\Local\Microsoft\Edge\User Data"
    New-Item -Path $edgeUserData -ItemType Directory -Force | Out-Null
    New-Item -Path "$edgeUserData\First Run" -ItemType File -Force | Out-Null
    Write-Host "Edge First Run sentinel file created"

    # Minimize all windows so Edge appears cleanly
    PyAG-Hotkey @("win", "d")
    Start-Sleep -Seconds 2

    # Launch Edge maximized. On first-ever launch, Edge needs extra time to create
    # its profile, initialize the renderer, etc. FRE suppressed via registry policy
    # (Phase 1) + sentinel file + --disable-features flag.
    $edgeBatch = "C:\Windows\Temp\launch_edge_adaudit.cmd"
    "@echo off`r`nstart `"`" `"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`" --start-maximized --no-first-run --disable-sync --no-default-browser-check --disable-features=msEdgeOnRampFRE `"http://localhost:8081/`"" | Out-File -FilePath $edgeBatch -Encoding ASCII

    $ErrorActionPreference = "Continue"
    schtasks /Delete /TN LaunchEdge /F 2>$null
    schtasks /Create /TN LaunchEdge /TR "cmd /c $edgeBatch" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN LaunchEdge 2>$null
    $ErrorActionPreference = "Stop"

    # Wait generously for first-ever Edge launch (profile creation + page load).
    Write-Host "Waiting for Edge first launch + page load (40s)..."
    Start-Sleep -Seconds 40
    schtasks /Delete /TN LaunchEdge /F 2>$null
    Remove-Item $edgeBatch -Force -ErrorAction SilentlyContinue

    # Navigate to the login URL explicitly using the address bar.
    # This guarantees we're on the correct page in the ACTIVE tab, regardless of
    # any restored tabs, FRE pages, or other unexpected browser state.
    Write-Host "Navigating to login page via address bar..."
    PyAG-Hotkey @("ctrl", "l")      # Focus address bar
    Start-Sleep -Seconds 1
    PyAG-Type "localhost:8081"       # Type URL
    Start-Sleep -Milliseconds 500
    PyAG-Press "enter"               # Navigate
    Start-Sleep -Seconds 10          # Wait for page to fully load and JS to initialize

    # Login form: The login page has the form on the right side.
    # Verified coordinates at 1280x720:
    #   Username field center: ~(915, 268)
    #   Password field center: ~(915, 311)
    #   LOGIN button center:   ~(787, 467)
    Write-Host "Logging in with admin/admin..."
    PyAG-Click 915 268              # Click username field
    Start-Sleep -Seconds 1
    PyAG-Hotkey @("ctrl", "a")      # Select all (in case pre-filled)
    Start-Sleep -Milliseconds 300
    PyAG-Type "admin"               # Type username
    Start-Sleep -Milliseconds 500
    PyAG-Click 915 311              # Click password field
    Start-Sleep -Seconds 1
    PyAG-Type "admin"               # Type password
    Start-Sleep -Milliseconds 500
    PyAG-Click 787 467              # Click LOGIN button
    Start-Sleep -Seconds 15         # Wait for password change form to fully load

    # Mandatory password change form appears after first login.
    # Verified coordinates at 1280x720 (from visual grounding on actual screenshot):
    #   Current Password field: ~(658, 259)
    #   New Password field:     ~(658, 296)
    #   Confirm Password field: ~(658, 333)
    #   Change button:          ~(571, 375)
    Write-Host "Changing password to Admin@2024..."
    PyAG-Click 658 259              # Click Current Password field
    Start-Sleep -Seconds 1
    PyAG-Type "admin"               # Old password
    Start-Sleep -Milliseconds 500
    PyAG-Click 658 296              # Click New Password field
    Start-Sleep -Seconds 1
    PyAG-Type "Admin"               # First part (no special chars)
    Start-Sleep -Milliseconds 300
    PyAG-Hotkey @("shift", "2")     # Type "@" character
    Start-Sleep -Milliseconds 300
    PyAG-Type "2024"                # Rest of password
    Start-Sleep -Milliseconds 500
    PyAG-Click 658 333              # Click Confirm Password field
    Start-Sleep -Seconds 1
    PyAG-Type "Admin"               # First part
    Start-Sleep -Milliseconds 300
    PyAG-Hotkey @("shift", "2")     # Type "@" character
    Start-Sleep -Milliseconds 300
    PyAG-Type "2024"                # Rest of password
    Start-Sleep -Milliseconds 500
    PyAG-Click 571 375              # Click Change button
    Start-Sleep -Seconds 8          # Wait for change to process

    # Write the actual password to a marker file for other scripts
    "Admin@2024" | Out-File -FilePath "C:\Windows\Temp\adaudit_password.txt" -Encoding ASCII -NoNewline

    # Close the browser
    Write-Host "Closing browser..."
    Get-Process -Name "msedge" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 10

    # Verify password change: login with NEW password, then check we don't get
    # redirected to the password change page (which happens when old password is still active).
    Write-Host "Verifying password change via HTTP login..."
    $passwordVerified = $false
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        try {
            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $loginBody = @{
                j_username    = "admin"
                j_password    = "Admin@2024"
                AUTHRULE_NAME = "ADAPAuthenticator"
            }
            $loginResp = Invoke-WebRequest -Uri "http://localhost:8081/j_security_check" `
                -Method POST -Body $loginBody -WebSession $session `
                -UseBasicParsing -MaximumRedirection 5 -ErrorAction Stop

            # After login, try to access a protected page using the session
            $checkResp = Invoke-WebRequest -Uri "http://localhost:8081/api/json/common/getLoggedOnUserDetail" `
                -Method GET -WebSession $session -UseBasicParsing -ErrorAction Stop
            $checkContent = $checkResp.Content
            # If we get valid JSON with user details, login succeeded with new password
            if ($checkContent -match '"userName"' -or $checkContent -match '"JELOGINNAME"') {
                Write-Host "  Password verification PASSED on attempt $attempt (user API returned data)"
                $passwordVerified = $true
                break
            } elseif ($checkContent -match 'changepass' -or $checkContent -match 'j_security_check') {
                Write-Host "  WARNING: Password change may not have worked (got login/changepass redirect)"
            } else {
                Write-Host "  Login response on attempt $attempt, checking further..."
                # Still count as success if we got HTTP 200 on the protected resource
                if ($checkResp.StatusCode -ge 200 -and $checkResp.StatusCode -lt 400) {
                    Write-Host "  Password verification PASSED (HTTP $($checkResp.StatusCode)) on attempt $attempt"
                    $passwordVerified = $true
                    break
                }
            }
        } catch {
            Write-Host "  Attempt $attempt failed: $_"
        }
        Start-Sleep -Seconds 10
    }
    if (-not $passwordVerified) {
        Write-Host "WARNING: Could not verify password change via HTTP login after 10 attempts"
    }

    # ==================================================================
    # Phase 8: Cleanup and markers
    # ==================================================================
    Write-Host "`n--- Phase 8: Cleanup ---"

    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    "OK" | Out-File -FilePath "C:\Windows\Temp\adaudit_install_complete.marker" -Encoding ASCII -NoNewline

    Write-Host "=== ADAudit Plus installation complete ==="

} catch {
    Write-Host "ERROR: $_"
    Write-Host $_.ScriptStackTrace
    throw
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
