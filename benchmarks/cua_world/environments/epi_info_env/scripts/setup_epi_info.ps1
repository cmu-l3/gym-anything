Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up Epi Info 7 Environment ==="

    # -------------------------------------------------------------------
    # 1. Find Epi Info 7 launcher executable
    # -------------------------------------------------------------------
    Write-Host "--- Locating Epi Info 7 launcher ---"

    $launcherExe = $null
    $savedPath = "C:\Users\Docker\epi_info_launcher_path.txt"
    if (Test-Path $savedPath) {
        $launcherExe = (Get-Content $savedPath -Raw).Trim()
        if (-not (Test-Path $launcherExe)) { $launcherExe = $null }
    }

    if (-not $launcherExe) {
        $searchPaths = @(
            "C:\EpiInfo7\Launch Epi Info 7.exe",
            "C:\EpiInfo7\Analysis.exe",
            "C:\EpiInfo7\EpiInfo7Launcher.exe",
            "C:\EpiInfo7\EpiInfo7.exe",
            "C:\Program Files\CDC\Epi Info 7\EpiInfo7Launcher.exe",
            "C:\Program Files (x86)\CDC\Epi Info 7\EpiInfo7Launcher.exe"
        )
        foreach ($p in $searchPaths) {
            if (Test-Path $p) { $launcherExe = $p; break }
        }
        if (-not $launcherExe) {
            $found = Get-ChildItem "C:\EpiInfo7" -Recurse -Filter "Launch Epi Info 7.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $launcherExe = $found.FullName }
        }
        if (-not $launcherExe) {
            $found = Get-ChildItem "C:\EpiInfo7" -Recurse -Filter "EpiInfo7Launcher.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $launcherExe = $found.FullName }
        }
        if (-not $launcherExe) {
            $found = Get-ChildItem "C:\EpiInfo7" -Recurse -Filter "Analysis.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $launcherExe = $found.FullName }
        }
    }

    if (-not $launcherExe) {
        Write-Host "WARNING: Epi Info 7 launcher not found."
        # List EpiInfo7 contents for debugging
        if (Test-Path "C:\EpiInfo7") {
            Write-Host "C:\EpiInfo7 contents:"
            Get-ChildItem "C:\EpiInfo7" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name)" }
        }
    } else {
        Write-Host "Found Epi Info 7 at: $launcherExe"
        # Update saved path
        Set-Content -Path "C:\Users\Docker\epi_info_launcher_path.txt" -Value $launcherExe -Encoding UTF8
    }

    # -------------------------------------------------------------------
    # 2. Find EColi.PRJ sample data file
    # -------------------------------------------------------------------
    Write-Host "--- Locating EColi sample dataset ---"

    $ecoliPrj = $null
    $savedEcoli = "C:\Users\Docker\ecoli_prj_path.txt"
    if (Test-Path $savedEcoli) {
        $ecoliPrj = (Get-Content $savedEcoli -Raw).Trim()
        if (-not (Test-Path $ecoliPrj)) { $ecoliPrj = $null }
    }

    if (-not $ecoliPrj) {
        $ecoliFile = Get-ChildItem "C:\EpiInfo7" -Recurse -Filter "EColi.prj" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $ecoliFile) {
            $ecoliFile = Get-ChildItem "C:\EpiInfo7" -Recurse -Filter "EColi.PRJ" -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($ecoliFile) {
            $ecoliPrj = $ecoliFile.FullName
            Set-Content -Path "C:\Users\Docker\ecoli_prj_path.txt" -Value $ecoliPrj -Encoding UTF8
        }
    }

    if ($ecoliPrj) {
        Write-Host "EColi.PRJ found at: $ecoliPrj"
    } else {
        Write-Host "WARNING: EColi.PRJ not found."
        # Look for any prj files
        $prjFiles = Get-ChildItem "C:\EpiInfo7" -Recurse -Filter "*.prj" -ErrorAction SilentlyContinue
        Write-Host "Available PRJ files:"
        $prjFiles | ForEach-Object { Write-Host "  $($_.FullName)" }
    }

    # -------------------------------------------------------------------
    # 3. Create Desktop shortcut for Epi Info 7
    # -------------------------------------------------------------------
    if ($launcherExe) {
        Write-Host "--- Creating Desktop shortcut ---"
        try {
            $WshShell = New-Object -ComObject WScript.Shell
            $shortcut = $WshShell.CreateShortcut("C:\Users\Docker\Desktop\Epi Info 7.lnk")
            $shortcut.TargetPath = $launcherExe
            $shortcut.WorkingDirectory = Split-Path $launcherExe -Parent
            $shortcut.Description = "Epi Info 7 - CDC Epidemiology Software"
            $shortcut.Save()
            Write-Host "Desktop shortcut created"
        } catch {
            Write-Host "WARNING: Could not create shortcut: $($_.Exception.Message)"
        }
    }

    # -------------------------------------------------------------------
    # 4. Suppress Epi Info 7 update checks via registry
    #    Epi Info checks for updates on launch; disable to avoid dialogs.
    # -------------------------------------------------------------------
    Write-Host "--- Configuring Epi Info 7 settings ---"
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        # Epi Info 7 stores settings in HKCU\Software\CDC\EpiInfo
        $epiRegPath = "HKCU:\Software\CDC\EpiInfo"
        if (-not (Test-Path $epiRegPath)) {
            New-Item -Path $epiRegPath -Force 2>$null | Out-Null
        }
        # Disable automatic update check
        New-ItemProperty -Path $epiRegPath -Name "CheckForUpdates" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
        New-ItemProperty -Path $epiRegPath -Name "AutoUpdate" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
        Write-Host "Epi Info registry settings configured"
    } catch {
        Write-Host "WARNING: Could not set Epi Info registry settings: $($_.Exception.Message)"
    } finally {
        $ErrorActionPreference = $prevEAP
    }

    # Also try to set config in XML if Epi Info uses app.config
    $configPaths = @(
        "C:\EpiInfo7\EpiInfo7.exe.config",
        "C:\EpiInfo7\EpiInfo7Launcher.exe.config"
    )
    foreach ($cfg in $configPaths) {
        if (Test-Path $cfg) {
            Write-Host "Found config file: $cfg"
            # Could modify update URL here if needed
        }
    }

    # -------------------------------------------------------------------
    # 5. Create EColi_classic project (flat-table with classic field names)
    #    Needs 32-bit PowerShell for Jet OLEDB 4.0 access to .mdb files
    # -------------------------------------------------------------------
    Write-Host "--- Creating EColi_classic project ---"
    try {
        $createScript = "C:\workspace\scripts\create_ecoli_classic.ps1"
        if (Test-Path $createScript) {
            $proc = Start-Process -FilePath "C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" `
                -ArgumentList "-ExecutionPolicy Bypass -File `"$createScript`"" `
                -Wait -PassThru -NoNewWindow
            Write-Host "create_ecoli_classic.ps1 exit code: $($proc.ExitCode)"
        } else {
            Write-Host "WARNING: create_ecoli_classic.ps1 not found at $createScript"
        }
    } catch {
        Write-Host "WARNING: EColi_classic project creation failed: $($_.Exception.Message)"
    }

    # -------------------------------------------------------------------
    # 6. Warm-up launch of Epi Info 7 to dismiss first-run dialogs
    # -------------------------------------------------------------------
    if ($launcherExe) {
        Write-Host "--- Warm-up launch of Epi Info 7 ---"

        $launchScript = "C:\Windows\Temp\launch_epi_info.cmd"
        $launchDir = Split-Path $launcherExe -Parent
        $launchCmd = "@echo off`r`ncd /d `"$launchDir`"`r`nstart `"`" `"$launcherExe`""
        [System.IO.File]::WriteAllText($launchScript, $launchCmd)

        $taskName = "LaunchEpiInfo_Warmup"
        $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")

        $prevEAP2 = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN $taskName 2>$null
            Write-Host "Epi Info 7 launch scheduled. Waiting for it to start..."

            # Wait for Epi Info to start and load
            Start-Sleep -Seconds 20

            # Dismiss any dialogs via PyAutoGUI TCP server
            Write-Host "Attempting to dismiss first-run dialogs..."
            $dismissed = $false
            for ($attempt = 0; $attempt -lt 3; $attempt++) {
                try {
                    $sock = New-Object System.Net.Sockets.TcpClient
                    $iar = $sock.BeginConnect("127.0.0.1", 5555, $null, $null)
                    if ($iar.AsyncWaitHandle.WaitOne(3000, $false)) {
                        $sock.EndConnect($iar)
                        $stream = $sock.GetStream()
                        $writer = New-Object System.IO.StreamWriter($stream)
                        $writer.AutoFlush = $true
                        $reader = New-Object System.IO.StreamReader($stream)

                        # Press Escape to dismiss any dialog
                        $writer.WriteLine('{"action":"press","keys":"esc"}')
                        $reader.ReadLine() | Out-Null
                        Start-Sleep -Milliseconds 500

                        # Press Enter to accept/dismiss dialog if one is open
                        $writer.WriteLine('{"action":"press","keys":"enter"}')
                        $reader.ReadLine() | Out-Null
                        Start-Sleep -Milliseconds 500

                        # Press Escape again for any remaining dialogs
                        $writer.WriteLine('{"action":"press","keys":"esc"}')
                        $reader.ReadLine() | Out-Null
                        Start-Sleep -Milliseconds 300

                        # Press Alt+F4 to close any popup (NOT the main window)
                        $writer.WriteLine('{"action":"hotkey","keys":["alt","F4"]}')
                        $reader.ReadLine() | Out-Null
                        Start-Sleep -Milliseconds 500

                        $sock.Close()
                        $dismissed = $true
                        Write-Host "Dialog dismissal attempt $($attempt + 1) complete"
                    } else {
                        Write-Host "PyAutoGUI server not reachable (attempt $($attempt + 1))"
                        $sock.Close()
                    }
                } catch {
                    Write-Host "PyAutoGUI attempt $($attempt + 1) failed: $($_.Exception.Message)"
                }
                Start-Sleep -Seconds 3
            }

            # Close Epi Info gracefully via Alt+F4 on main window
            Write-Host "Closing Epi Info 7 (warm-up complete)..."
            Start-Sleep -Seconds 5
            try {
                $sock3 = New-Object System.Net.Sockets.TcpClient
                $iar3 = $sock3.BeginConnect("127.0.0.1", 5555, $null, $null)
                if ($iar3.AsyncWaitHandle.WaitOne(3000, $false)) {
                    $sock3.EndConnect($iar3)
                    $s3 = $sock3.GetStream()
                    $w3 = New-Object System.IO.StreamWriter($s3)
                    $w3.AutoFlush = $true
                    $r3 = New-Object System.IO.StreamReader($s3)
                    # Alt+F4 to close main Epi Info window
                    $w3.WriteLine('{"action":"hotkey","keys":["alt","F4"]}')
                    $r3.ReadLine() | Out-Null
                    Start-Sleep -Milliseconds 1000
                    # Confirm any "Are you sure?" dialog
                    $w3.WriteLine('{"action":"press","keys":"enter"}')
                    $r3.ReadLine() | Out-Null
                    $sock3.Close()
                }
            } catch {
                Write-Host "Could not close via PyAutoGUI: $($_.Exception.Message)"
            }

            Start-Sleep -Seconds 3
        } finally {
            # Force-kill Epi Info processes if still running
            $prevEAP3 = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            Get-Process "EpiInfo7*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Get-Process "EpiInfo*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            schtasks /Delete /TN $taskName /F 2>$null
            Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
            $ErrorActionPreference = $prevEAP3
            $ErrorActionPreference = $prevEAP2
        }

        Write-Host "Warm-up launch complete"
    }

    # -------------------------------------------------------------------
    # 6. Disable Edge auto-restore and suppress browser popups
    # -------------------------------------------------------------------
    Write-Host "--- Disabling Edge auto-restore and browser popups ---"
    $prevEAP4 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force 2>$null | Out-Null }
    New-ItemProperty -Path $regPath -Name "StartupBoostEnabled" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
    New-ItemProperty -Path $regPath -Name "BackgroundModeEnabled" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
    New-ItemProperty -Path $regPath -Name "RestoreOnStartup" -Value 5 -PropertyType DWord -Force 2>$null | Out-Null

    $winlogon = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    if (-not (Test-Path $winlogon)) { New-Item -Path $winlogon -Force 2>$null | Out-Null }
    New-ItemProperty -Path $winlogon -Name "DisableAutomaticRestartSignOn" -Value 1 -PropertyType DWord -Force 2>$null | Out-Null
    $userWinlogon = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    if (-not (Test-Path $userWinlogon)) { New-Item -Path $userWinlogon -Force 2>$null | Out-Null }
    New-ItemProperty -Path $userWinlogon -Name "RestartApps" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null

    # Clear Edge session data
    $edgeUserData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    if (Test-Path $edgeUserData) {
        Get-ChildItem $edgeUserData -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            foreach ($f in @("Current Session","Current Tabs","Last Session","Last Tabs")) {
                Remove-Item (Join-Path $_.FullName $f) -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Suppress Windows notifications
    $toastPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications"
    if (-not (Test-Path $toastPath)) { New-Item -Path $toastPath -Force 2>$null | Out-Null }
    New-ItemProperty -Path $toastPath -Name "ToastEnabled" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null

    # Disable OneDrive auto-start
    Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    taskkill /F /IM OneDrive.exe 2>$null

    # Kill Edge repeatedly before checkpoint
    Write-Host "Killing Edge to ensure clean checkpoint..."
    for ($k = 0; $k -lt 3; $k++) {
        taskkill /F /IM msedge.exe 2>$null
        Start-Sleep -Seconds 2
    }
    $ErrorActionPreference = $prevEAP4

    # Clean up desktop in Session 1 (minimize terminals, close Start menu)
    Write-Host "Cleaning up desktop..."
    $cleanupScript = "C:\Windows\Temp\cleanup_desktop.ps1"
    @'
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Milliseconds 500
(New-Object -ComObject Shell.Application).MinimizeAll()
'@ | Set-Content $cleanupScript -Encoding UTF8
    $prevEAP5 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN "CleanupDesktop_GA" /TR "powershell -ExecutionPolicy Bypass -File $cleanupScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN "CleanupDesktop_GA" 2>$null
    Start-Sleep -Seconds 5
    schtasks /Delete /TN "CleanupDesktop_GA" /F 2>$null
    Remove-Item $cleanupScript -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP5

    Write-Host "=== Epi Info 7 Environment Setup Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
