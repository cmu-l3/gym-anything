Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up AttendHRM Environment ==="

    # -------------------------------------------------------------------
    # Phase 1: Wait for Firebird database service to be running
    # Firebird is bundled with AttendHRM and auto-starts as a Windows service.
    # -------------------------------------------------------------------
    Write-Host "--- Waiting for Firebird service ---"
    $maxWait = 120
    $elapsed = 0
    $fbReady = $false

    while ($elapsed -lt $maxWait) {
        $prevEAP0 = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $fbSvc = Get-Service | Where-Object { $_.Name -like "*Firebird*" -and $_.Status -eq "Running" } | Select-Object -First 1
        $ErrorActionPreference = $prevEAP0

        if ($fbSvc) {
            Write-Host "Firebird service is running: $($fbSvc.Name)"
            $fbReady = $true
            break
        }

        # Try to start any stopped Firebird service
        $prevEAP1 = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $stoppedFb = Get-Service | Where-Object { $_.Name -like "*Firebird*" } | Select-Object -First 1
        if ($stoppedFb -and $stoppedFb.Status -ne "Running") {
            Write-Host "Starting Firebird service: $($stoppedFb.Name)"
            Start-Service $stoppedFb.Name -ErrorAction SilentlyContinue
        }
        $ErrorActionPreference = $prevEAP1

        Start-Sleep -Seconds 5
        $elapsed += 5
        Write-Host "Waiting for Firebird... ($elapsed/$maxWait s)"
    }

    if (-not $fbReady) {
        Write-Host "WARNING: Firebird service not confirmed ready after ${maxWait}s, proceeding anyway"
    }

    # Extra stabilization wait
    Start-Sleep -Seconds 3

    # -------------------------------------------------------------------
    # Phase 2: Locate AttendHRM executable
    # -------------------------------------------------------------------
    Write-Host "--- Locating AttendHRM ---"
    $attendExe = $null
    $savedPath = "C:\Users\Docker\attendhrm_path.txt"
    if (Test-Path $savedPath) {
        $attendExe = (Get-Content $savedPath -Raw).Trim()
        if (-not (Test-Path $attendExe)) { $attendExe = $null }
    }

    if (-not $attendExe) {
        $candidates = @(
            "C:\Program Files (x86)\Attend HRM\Bin\Attend.exe",  # actual install path (verified)
            "C:\Program Files (x86)\Attend HRM\Attend.exe",
            "C:\Program Files\Attend HRM\Bin\Attend.exe",
            "C:\Program Files\Attend HRM\Attend.exe",
            "C:\Program Files (x86)\AttendHRM\Attend.exe",
            "C:\Program Files\AttendHRM\Attend.exe"
        )
        foreach ($p in $candidates) {
            if (Test-Path $p) { $attendExe = $p; break }
        }
    }

    if (-not $attendExe) {
        $prevEAP2 = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $found = Get-ChildItem "C:\Program Files (x86)", "C:\Program Files" -Recurse -Filter "Attend.exe" `
            -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -notmatch "unins" } | Select-Object -First 1
        $ErrorActionPreference = $prevEAP2
        if ($found) { $attendExe = $found.FullName }
    }

    if (-not $attendExe) {
        Write-Host "WARNING: AttendHRM not found, skipping warm-up"
    } else {
        Write-Host "AttendHRM found at: $attendExe"
        Set-Content -Path "C:\Users\Docker\attendhrm_path.txt" -Value $attendExe -Encoding UTF8

        # Create Desktop shortcut
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut("C:\Users\Docker\Desktop\AttendHRM.lnk")
        $shortcut.TargetPath = $attendExe
        $shortcut.WorkingDirectory = Split-Path $attendExe -Parent
        $shortcut.Save()
        Write-Host "Desktop shortcut created: C:\Users\Docker\Desktop\AttendHRM.lnk"

        # -------------------------------------------------------------------
        # Phase 3: Warm-up launch — handle any first-run dialogs and verify
        # the Demo database + admin/admin login works.
        #
        # IMPORTANT: Double-click the desktop shortcut via PyAutoGUI (Session 1)
        # so the AttendHRM window appears in the FOREGROUND, not behind the terminal.
        # -------------------------------------------------------------------
        Write-Host "--- Warm-up launch of AttendHRM ---"

        $prevEAP3 = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"

            # Double-click the desktop shortcut to launch AttendHRM in foreground.
            # The shortcut was created in Phase 2 at C:\Users\Docker\Desktop\AttendHRM.lnk
            # Desktop icon position: (30, 469) — visible to the left of the terminal window.
            Write-Host "Double-clicking AttendHRM desktop icon..."
            try {
                $sock0 = New-Object System.Net.Sockets.TcpClient
                $iar0  = $sock0.BeginConnect("127.0.0.1", 5555, $null, $null)
                if ($iar0.AsyncWaitHandle.WaitOne(5000, $false)) {
                    $sock0.EndConnect($iar0)
                    $stream0 = $sock0.GetStream()
                    $w0 = New-Object System.IO.StreamWriter($stream0)
                    $w0.AutoFlush = $true
                    $r0 = New-Object System.IO.StreamReader($stream0)
                    $w0.WriteLine('{"action":"doubleClick","x":30,"y":469}')
                    $r0.ReadLine() | Out-Null
                    $sock0.Close()
                    Write-Host "Desktop icon double-clicked"
                } else {
                    $sock0.Close()
                    Write-Host "WARNING: PyAutoGUI not reachable for icon click, trying schtasks fallback"
                    $launchScript = "C:\Windows\Temp\launch_attendhrm_warmup.cmd"
                    $launchCmd = "@echo off`r`nstart `"`" `"$attendExe`""
                    [System.IO.File]::WriteAllText($launchScript, $launchCmd)
                    $taskName2 = "LaunchAttendHRM_Warmup"
                    schtasks /Delete /TN $taskName2 /F 2>$null | Out-Null
                    $st2 = (Get-Date).AddMinutes(1).ToString("HH:mm")
                    schtasks /Create /TN $taskName2 /TR "cmd /c $launchScript" /SC ONCE /ST $st2 /RL HIGHEST /IT /F 2>$null | Out-Null
                    schtasks /Run /TN $taskName2 2>$null | Out-Null
                    Start-Sleep -Seconds 2
                    schtasks /Delete /TN $taskName2 /F 2>$null | Out-Null
                    Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
                }
            } catch {
                Write-Host "Icon double-click failed: $($_.Exception.Message)"
            }

            # Wait for splash screen + login window to appear (15s)
            Write-Host "Waiting for AttendHRM login window to appear..."
            Start-Sleep -Seconds 15

            # Attempt login via PyAutoGUI TCP server (runs in interactive session)
            Write-Host "Attempting login via PyAutoGUI..."
            try {
                $sock = New-Object System.Net.Sockets.TcpClient
                $iar  = $sock.BeginConnect("127.0.0.1", 5555, $null, $null)
                if ($iar.AsyncWaitHandle.WaitOne(5000, $false)) {
                    $sock.EndConnect($iar)
                    $stream = $sock.GetStream()
                    $writer = New-Object System.IO.StreamWriter($stream)
                    $writer.AutoFlush = $true
                    $reader = New-Object System.IO.StreamReader($stream)

                    # -------------------------------------------------------
                    # Dismiss CEF binaries error dialog (appears on every launch).
                    # Its title bar close button is at approximately (737, 13).
                    # -------------------------------------------------------
                    Write-Host "Dismissing CEF error dialog (if present)..."
                    $writer.WriteLine('{"action":"click","x":737,"y":13}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Seconds 2

                    # -------------------------------------------------------
                    # Login flow (coordinate-based; verified against real UI):
                    #   Login dialog: username pre-filled "admin"
                    #   Password field: (665, 381)
                    #   Login button:   (618, 491)
                    # -------------------------------------------------------

                    # Click the password field (username is pre-filled as "admin")
                    $writer.WriteLine('{"action":"click","x":665,"y":381}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Milliseconds 500

                    # Type password: admin
                    $writer.WriteLine('{"action":"typewrite","text":"admin","interval":0.05}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Milliseconds 400

                    # Click Login button
                    $writer.WriteLine('{"action":"click","x":618,"y":491}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Seconds 4

                    # -------------------------------------------------------
                    # Windows Firewall dialog (appears on first launch):
                    #   "Do you want to allow AttendHRMAPI on all networks?"
                    #   Allow button: (538, 579) — verified via visual_grounding
                    # Try clicking Allow; harmless if dialog is not present.
                    # -------------------------------------------------------
                    Write-Host "Handling Windows Firewall dialog (if present)..."
                    $writer.WriteLine('{"action":"click","x":538,"y":579}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Seconds 4

                    # -------------------------------------------------------
                    # Employer Details dialog (first-run only):
                    #   Company Name field: (700, 304)
                    #   City field:         (700, 331)
                    #   Country field:      (700, 358)
                    #   Save & Continue:    (791, 387)
                    #   Error OK button:    (639, 371)
                    # -------------------------------------------------------
                    Write-Host "Filling Employer Details dialog (if present)..."

                    # Company Name
                    $writer.WriteLine('{"action":"click","x":700,"y":304}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Milliseconds 300
                    $writer.WriteLine('{"action":"typewrite","text":"Demo Company","interval":0.05}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Milliseconds 300

                    # City
                    $writer.WriteLine('{"action":"click","x":700,"y":331}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Milliseconds 300
                    $writer.WriteLine('{"action":"typewrite","text":"New York","interval":0.05}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Milliseconds 300

                    # Country
                    $writer.WriteLine('{"action":"click","x":700,"y":358}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Milliseconds 300
                    $writer.WriteLine('{"action":"typewrite","text":"USA","interval":0.05}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Milliseconds 300

                    # Save & Continue
                    $writer.WriteLine('{"action":"click","x":791,"y":387}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Seconds 3

                    # If a validation error appeared (error OK button at 639,371), dismiss it
                    $writer.WriteLine('{"action":"click","x":639,"y":371}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Milliseconds 500
                    # Try Save & Continue again
                    $writer.WriteLine('{"action":"click","x":791,"y":387}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Seconds 3

                    Write-Host "First-run dialogs handled, app should be on Dashboard"
                    Start-Sleep -Seconds 2

                    # Close the application via Alt+F4
                    $writer.WriteLine('{"action":"hotkey","keys":["alt","F4"]}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Seconds 2

                    # Dismiss any exit confirmation (press Enter for default button)
                    $writer.WriteLine('{"action":"press","keys":"return"}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Seconds 3

                    $sock.Close()
                    Write-Host "Warm-up login and close succeeded"
                } else {
                    Write-Host "PyAutoGUI server not reachable within 5s"
                    $sock.Close()
                }
            } catch {
                Write-Host "Warm-up login attempt failed: $($_.Exception.Message)"
            }

        } finally {
            # Force kill if still running
            $prevEAP4 = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            Get-Process -Name "Attend" -ErrorAction SilentlyContinue |
                Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            $ErrorActionPreference = $prevEAP4
            $ErrorActionPreference = $prevEAP3
        }

        Write-Host "Warm-up complete"
    }

    # -------------------------------------------------------------------
    # Phase 4: Copy data files to user's Desktop
    # -------------------------------------------------------------------
    Write-Host "--- Preparing data files ---"
    $desktopPath = "C:\Users\Docker\Desktop"
    New-Item -ItemType Directory -Force -Path $desktopPath | Out-Null

    # Copy the employee import CSV to Desktop (for import_employees task)
    $importCsvSrc = "C:\workspace\data\employees_import.csv"
    $importCsvDst = "$desktopPath\employees_import.csv"
    if (Test-Path $importCsvSrc) {
        Copy-Item $importCsvSrc $importCsvDst -Force
        Write-Host "Copied employees_import.csv to Desktop"
    } else {
        Write-Host "WARNING: employees_import.csv not found in data directory"
    }

    # -------------------------------------------------------------------
    # Phase 5: Disable Edge auto-start and clean up browsers
    # -------------------------------------------------------------------
    Write-Host "--- Disabling Edge auto-start ---"
    $prevEAP5 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force 2>$null | Out-Null }
    New-ItemProperty -Path $regPath -Name "StartupBoostEnabled"  -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
    New-ItemProperty -Path $regPath -Name "BackgroundModeEnabled" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
    New-ItemProperty -Path $regPath -Name "RestoreOnStartup"      -Value 5 -PropertyType DWord -Force 2>$null | Out-Null

    # Aggressively kill Edge 5 times with 2s gaps before checkpoint save
    for ($k = 0; $k -lt 5; $k++) {
        taskkill /F /IM msedge.exe 2>$null
        Start-Sleep -Seconds 2
    }
    $ErrorActionPreference = $prevEAP5

    # -------------------------------------------------------------------
    # Phase 6: Extend Firebird database with locations and designations
    # needed for the add_employee and import_employees tasks.
    #   - Locations: COCHIN, Texas, Chennai  (the demo DB only has London/Norwich/Dublin)
    #   - Designations: Senior Developer, Office Assistant, Account Executive, Account Manager
    # Uses isql.exe with UPDATE OR INSERT (Firebird UPSERT) so re-runs are safe.
    # -------------------------------------------------------------------
    Write-Host "--- Extending Firebird database (locations + designations) ---"
    $prevEAP6 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    try {
        # Locate isql.exe (Firebird interactive SQL tool)
        $isqlExe = $null
        $isqlCandidates = @(
            "C:\Program Files (x86)\Firebird\Firebird_5_0\isql.exe",
            "C:\Program Files (x86)\Firebird\Firebird_2_5\isql.exe",
            "C:\Program Files\Firebird\Firebird_5_0\isql.exe",
            "C:\Program Files\Firebird\Firebird_2_5\isql.exe"
        )
        foreach ($c in $isqlCandidates) {
            if (Test-Path $c) { $isqlExe = $c; break }
        }
        if (-not $isqlExe) {
            $fbDirs = @("C:\Program Files (x86)\Firebird", "C:\Program Files\Firebird")
            foreach ($d in $fbDirs) {
                if (Test-Path $d) {
                    $found = Get-ChildItem $d -Recurse -Filter "isql.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($found) { $isqlExe = $found.FullName; break }
                }
            }
        }

        # Locate DEMO.FDB
        $demoFdb = $null
        $fdbCandidates = @(
            "C:\Program Files (x86)\Attend HRM\Data\DEMO.FDB",
            "C:\Program Files\Attend HRM\Data\DEMO.FDB"
        )
        foreach ($c in $fdbCandidates) {
            if (Test-Path $c) { $demoFdb = $c; break }
        }

        if (-not $isqlExe) {
            Write-Host "WARNING: isql.exe not found — skipping database extension"
        } elseif (-not $demoFdb) {
            Write-Host "WARNING: DEMO.FDB not found — skipping database extension"
        } else {
            Write-Host "isql.exe: $isqlExe"
            Write-Host "DEMO.FDB: $demoFdb"

            # Write the SQL to a temp file (ASCII — Firebird isql needs plain text)
            $sqlFile = "C:\Windows\Temp\attendhrm_db_extend.sql"
            $sqlLines = @(
                "/* Add locations needed by add_employee and import_employees tasks */",
                "/* UPDATE OR INSERT is Firebird UPSERT — safe to run multiple times  */",
                "UPDATE OR INSERT INTO WGR_BRA (BRA_ID, BRA_NAME, BRA_CODE, BRA_WGR_ID)",
                "  VALUES (10, 'COCHIN', 'COCHIN', 1) MATCHING (BRA_ID);",
                "UPDATE OR INSERT INTO WGR_BRA (BRA_ID, BRA_NAME, BRA_CODE, BRA_WGR_ID)",
                "  VALUES (11, 'Texas', 'TX', 1) MATCHING (BRA_ID);",
                "UPDATE OR INSERT INTO WGR_BRA (BRA_ID, BRA_NAME, BRA_CODE, BRA_WGR_ID)",
                "  VALUES (12, 'Chennai', 'CHN', 1) MATCHING (BRA_ID);",
                "COMMIT;",
                "/* Add designations/positions needed by tasks */",
                "UPDATE OR INSERT INTO ITA_POS (POS_ID, POS_NAME)",
                "  VALUES (100, 'Senior Developer') MATCHING (POS_ID);",
                "UPDATE OR INSERT INTO ITA_POS (POS_ID, POS_NAME)",
                "  VALUES (101, 'Office Assistant') MATCHING (POS_ID);",
                "UPDATE OR INSERT INTO ITA_POS (POS_ID, POS_NAME)",
                "  VALUES (102, 'Account Executive') MATCHING (POS_ID);",
                "UPDATE OR INSERT INTO ITA_POS (POS_ID, POS_NAME)",
                "  VALUES (103, 'Account Manager') MATCHING (POS_ID);",
                "COMMIT;"
            )
            [System.IO.File]::WriteAllLines($sqlFile, $sqlLines, [System.Text.Encoding]::ASCII)

            # Run isql.exe — connect to DB and execute the SQL file
            $isqlArgs = "-user SYSDBA -password masterkey `"$demoFdb`" -i `"$sqlFile`""
            $proc = Start-Process $isqlExe -ArgumentList $isqlArgs -Wait -PassThru -ErrorAction SilentlyContinue
            if ($proc -and $proc.ExitCode -eq 0) {
                Write-Host "Database extension succeeded (COCHIN/Texas/Chennai + Senior Developer/Office Assistant/Account Executive/Account Manager added)"
            } else {
                Write-Host "WARNING: isql.exe returned exit code $($proc.ExitCode) — check DB extension manually"
            }

            Remove-Item $sqlFile -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Host "WARNING: Database extension error: $($_.Exception.Message) (non-critical)"
    } finally {
        $ErrorActionPreference = $prevEAP6
    }

    # -------------------------------------------------------------------
    # Phase 7: Write ready marker
    # -------------------------------------------------------------------
    Set-Content -Path "C:\Users\Docker\attendhrm_ready.marker" `
        -Value "Ready at $(Get-Date)" -Encoding UTF8

    Write-Host "=== AttendHRM Environment Setup Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    exit 1
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
