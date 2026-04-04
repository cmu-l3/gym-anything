Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up bcWebCam Environment ==="

    # -------------------------------------------------------------------
    # 1. Create bcWebCam config directory
    # -------------------------------------------------------------------
    Write-Host "--- Preparing bcWebCam config ---"

    $iniDir = "C:\Users\Docker\AppData\Local\bcWebCam"
    New-Item -ItemType Directory -Force -Path $iniDir | Out-Null
    Write-Host "Config directory ready at $iniDir"

    # -------------------------------------------------------------------
    # 2. Find bcWebCam executable
    # -------------------------------------------------------------------
    Write-Host "--- Locating bcWebCam ---"

    $bcExe = $null
    $savedPath = "C:\Users\Docker\bcwebcam_path.txt"
    if (Test-Path $savedPath) {
        $bcExe = (Get-Content $savedPath -Raw).Trim()
        if (-not (Test-Path $bcExe)) { $bcExe = $null }
    }
    if (-not $bcExe) {
        $found = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse -Filter "bcWebCam.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $bcExe = $found.FullName }
    }

    if (-not $bcExe) {
        Write-Host "WARNING: bcWebCam.exe not found. Skipping warm-up."
    } else {
        Write-Host "Found bcWebCam at: $bcExe"

        # Create desktop shortcut
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut("C:\Users\Docker\Desktop\bcWebCam.lnk")
        $shortcut.TargetPath = $bcExe
        $shortcut.WorkingDirectory = Split-Path $bcExe -Parent
        $shortcut.Save()

        # -------------------------------------------------------------------
        # 3. Warm-up launch bcWebCam to dismiss first-run dialogs
        #    bcWebCam shows two dialogs on first launch:
        #    a) "bcWebCam - First Start" welcome dialog (click OK at ~639, 536)
        #    b) "No compatible WebCam device driver" error (click OK at ~782, 418)
        # -------------------------------------------------------------------
        Write-Host "--- Warm-up launch of bcWebCam ---"

        $launchScript = "C:\Windows\Temp\launch_bcwebcam.cmd"
        $launchCmd = "@echo off`r`nstart `"`" `"$bcExe`""
        [System.IO.File]::WriteAllText($launchScript, $launchCmd)

        $taskName = "LaunchBcWebCam_Warmup"
        $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")

        $prevEAP = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN $taskName 2>$null

            # Wait for bcWebCam to launch and show first-start dialog
            Start-Sleep -Seconds 8

            # Dismiss dialogs via PyAutoGUI TCP server (port 5555)
            Write-Host "Dismissing First Start dialog via PyAutoGUI..."
            try {
                $sock = New-Object System.Net.Sockets.TcpClient
                $iar = $sock.BeginConnect("127.0.0.1", 5555, $null, $null)
                if ($iar.AsyncWaitHandle.WaitOne(5000, $false)) {
                    $sock.EndConnect($iar)
                    $stream = $sock.GetStream()
                    $writer = New-Object System.IO.StreamWriter($stream)
                    $writer.AutoFlush = $true
                    $reader = New-Object System.IO.StreamReader($stream)

                    # Click OK on First Start dialog (~639, 536)
                    $writer.WriteLine('{"action":"click","x":639,"y":536}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Seconds 3

                    # Click OK on "No WebCam" error dialog (~782, 418)
                    Write-Host "Dismissing No WebCam error dialog..."
                    $writer.WriteLine('{"action":"click","x":782,"y":418}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Seconds 2

                    # Press Escape for any remaining dialogs
                    $writer.WriteLine('{"action":"press","keys":"esc"}')
                    $reader.ReadLine() | Out-Null
                    Start-Sleep -Milliseconds 500
                    $writer.WriteLine('{"action":"press","keys":"esc"}')
                    $reader.ReadLine() | Out-Null

                    $sock.Close()
                    Write-Host "Dialogs dismissed via PyAutoGUI"
                } else {
                    Write-Host "PyAutoGUI server not reachable for dialog dismissal"
                    $sock.Close()
                }
            } catch {
                Write-Host "PyAutoGUI dismissal failed: $($_.Exception.Message)"
            }

            Start-Sleep -Seconds 2

            # Gracefully close bcWebCam so it saves first-run state (Alt+F4)
            Write-Host "Closing bcWebCam gracefully (Alt+F4)..."
            try {
                $sock2 = New-Object System.Net.Sockets.TcpClient
                $iar2 = $sock2.BeginConnect("127.0.0.1", 5555, $null, $null)
                if ($iar2.AsyncWaitHandle.WaitOne(3000, $false)) {
                    $sock2.EndConnect($iar2)
                    $s2 = $sock2.GetStream()
                    $w2 = New-Object System.IO.StreamWriter($s2)
                    $w2.AutoFlush = $true
                    $r2 = New-Object System.IO.StreamReader($s2)
                    $w2.WriteLine('{"action":"hotkey","keys":["alt","F4"]}')
                    $r2.ReadLine() | Out-Null
                    $sock2.Close()
                }
            } catch { }
            Start-Sleep -Seconds 3
        } finally {
            # Force-kill bcWebCam if still running
            Get-Process bcWebCam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            schtasks /Delete /TN $taskName /F 2>$null
            Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
            $ErrorActionPreference = $prevEAP
        }

        Write-Host "Warm-up launch complete"

        # Save bcWebCam path
        Set-Content -Path "C:\Users\Docker\bcwebcam_path.txt" -Value $bcExe -Encoding UTF8
    }

    # -------------------------------------------------------------------
    # 4. Copy barcode data to desktop
    # -------------------------------------------------------------------
    Write-Host "--- Copying barcode data ---"
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop\Barcodes" | Out-Null
    Copy-Item "C:\workspace\data\barcodes\product_barcodes.csv" "C:\Users\Docker\Desktop\Barcodes\" -Force -ErrorAction SilentlyContinue
    Copy-Item "C:\workspace\data\barcodes\qr_codes.csv" "C:\Users\Docker\Desktop\Barcodes\" -Force -ErrorAction SilentlyContinue

    # -------------------------------------------------------------------
    # 5. Close browsers and disable Edge auto-start
    # -------------------------------------------------------------------
    Write-Host "--- Closing browser windows and disabling Edge ---"
    $prevEAP2 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    # Disable Edge startup boost, background mode, and session restore
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force 2>$null | Out-Null }
    New-ItemProperty -Path $regPath -Name "StartupBoostEnabled" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
    New-ItemProperty -Path $regPath -Name "BackgroundModeEnabled" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
    # RestoreOnStartup=5 = open new tab page (do NOT restore previous session)
    New-ItemProperty -Path $regPath -Name "RestoreOnStartup" -Value 5 -PropertyType DWord -Force 2>$null | Out-Null

    # Disable Windows 11 "Restart Apps" feature
    $winlogon = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    if (-not (Test-Path $winlogon)) { New-Item -Path $winlogon -Force 2>$null | Out-Null }
    New-ItemProperty -Path $winlogon -Name "DisableAutomaticRestartSignOn" -Value 1 -PropertyType DWord -Force 2>$null | Out-Null
    $userWinlogon = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    if (-not (Test-Path $userWinlogon)) { New-Item -Path $userWinlogon -Force 2>$null | Out-Null }
    New-ItemProperty -Path $userWinlogon -Name "RestartApps" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null

    # Clear ALL Edge session data (all profiles, not just Default)
    $edgeUserData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    if (Test-Path $edgeUserData) {
        Get-ChildItem $edgeUserData -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            foreach ($f in @("Current Session","Current Tabs","Last Session","Last Tabs")) {
                Remove-Item (Join-Path $_.FullName $f) -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Suppress Windows notifications (OneDrive backup, etc.)
    Write-Host "Disabling Windows notification popups..."
    $toastPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications"
    if (-not (Test-Path $toastPath)) { New-Item -Path $toastPath -Force 2>$null | Out-Null }
    New-ItemProperty -Path $toastPath -Name "ToastEnabled" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
    # Disable OneDrive auto-start
    Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    taskkill /F /IM OneDrive.exe 2>$null

    # Aggressively kill Edge — repeat 5 times with 2s gaps before checkpoint save
    Write-Host "Killing Edge repeatedly to ensure clean checkpoint..."
    for ($k = 0; $k -lt 5; $k++) {
        taskkill /F /IM msedge.exe 2>$null
        Start-Sleep -Seconds 2
    }
    $ErrorActionPreference = $prevEAP2

    Write-Host "=== bcWebCam Environment Setup Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
