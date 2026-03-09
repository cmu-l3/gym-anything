Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up Talon Voice environment ==="

    # ---- 1. Disable OneDrive ----
    Write-Host "Disabling OneDrive..."
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -Name "OneDrive" -ErrorAction SilentlyContinue
    $onedrivePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    New-Item -Path $onedrivePolicyPath -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $onedrivePolicyPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force

    $oneDriveSetup = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    if (Test-Path $oneDriveSetup) {
        $proc = Start-Process $oneDriveSetup -ArgumentList "/uninstall" -PassThru -ErrorAction SilentlyContinue
        if ($proc) {
            $finished = $proc.WaitForExit(30000)
            if ($finished) {
                Write-Host "OneDrive uninstalled."
            } else {
                Write-Host "OneDrive uninstall still running (continuing)."
            }
        }
    }

    # ---- 2. Create working directories ----
    Write-Host "Setting up working directories..."
    $talonUserDir = "C:\Users\Docker\AppData\Roaming\Talon\user"
    New-Item -ItemType Directory -Force -Path $talonUserDir | Out-Null

    $desktopDir = "C:\Users\Docker\Desktop"
    $talonTasksDir = Join-Path $desktopDir "TalonTasks"
    New-Item -ItemType Directory -Force -Path $talonTasksDir | Out-Null

    # ---- 3. Copy data files from workspace ----
    if (Test-Path "C:\workspace\data") {
        Write-Host "Copying data files from workspace..."
        Copy-Item "C:\workspace\data\*" -Destination $talonTasksDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Data files copied to: $talonTasksDir"
    }

    # ---- 4. Set .talon file association with Notepad++ or Notepad ----
    Write-Host "Setting .talon file association..."
    $nppExe = "C:\Program Files\Notepad++\notepad++.exe"
    if (Test-Path $nppExe) {
        $editor = $nppExe
        Write-Host "Using Notepad++ for .talon files"
    } else {
        $editor = "notepad.exe"
        Write-Host "Using Notepad for .talon files"
    }

    # Associate .talon extension
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & cmd /c "assoc .talon=TalonFile" 2>$null
        & cmd /c "ftype TalonFile=`"$editor`" `"%1`"" 2>$null
    } finally {
        $ErrorActionPreference = $prevEAP
    }

    # ---- 4b. Warm-up Notepad++ to dismiss first-run update dialog ----
    # Notepad++ shows an "Update Available" dialog on first launch.
    # Clicking "Never" writes noUpdate="yes" to config.xml.
    # We must warm up, click Never, let N++ close gracefully so it saves config.
    Write-Host "Warming up Notepad++ (first-run cycle)..."
    if (Test-Path $nppExe) {
        $nppWarmup = "C:\Windows\Temp\warmup_npp.cmd"
        $nppBatch = "@echo off`r`nstart `"`" `"$nppExe`""
        [System.IO.File]::WriteAllText($nppWarmup, $nppBatch)

        $prevEAP = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            $nppTask = "WarmupNpp_GA"
            $nppTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
            schtasks /Create /TN $nppTask /TR "cmd /c $nppWarmup" `
                /SC ONCE /ST $nppTime /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN $nppTask 2>$null
            Start-Sleep -Seconds 10

            # Click "Never" on the update dialog (coords 784,396 in 1280x720)
            $json = '{"action":"click","x":784,"y":396}'
            try {
                $client = New-Object System.Net.Sockets.TcpClient
                $client.Connect("127.0.0.1", 5555)
                $stream = $client.GetStream()
                $writer = New-Object System.IO.StreamWriter($stream)
                $writer.AutoFlush = $true
                $writer.WriteLine($json)
                $reader = New-Object System.IO.StreamReader($stream)
                $resp = $reader.ReadLine()
                Write-Host "Dismissed Notepad++ update dialog: $resp"
                $client.Close()
            } catch {
                Write-Host "PyAutoGUI click for update dialog: $_"
            }
            Start-Sleep -Seconds 3

            # Close Notepad++ gracefully so it saves config.xml with noUpdate="yes"
            $json2 = '{"action":"hotkey","keys":["alt","F4"]}'
            try {
                $client2 = New-Object System.Net.Sockets.TcpClient
                $client2.Connect("127.0.0.1", 5555)
                $stream2 = $client2.GetStream()
                $writer2 = New-Object System.IO.StreamWriter($stream2)
                $writer2.AutoFlush = $true
                $writer2.WriteLine($json2)
                $reader2 = New-Object System.IO.StreamReader($stream2)
                $resp2 = $reader2.ReadLine()
                Write-Host "Sent Alt+F4 to close Notepad++: $resp2"
                $client2.Close()
            } catch {
                Write-Host "PyAutoGUI Alt+F4: $_"
            }
            Start-Sleep -Seconds 3

            # Force-kill if still running
            Get-Process notepad++ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2

            schtasks /Delete /TN $nppTask /F 2>$null
            Remove-Item $nppWarmup -Force -ErrorAction SilentlyContinue
        } finally {
            $ErrorActionPreference = $prevEAP
        }
        Write-Host "Notepad++ warm-up complete."
    }

    # ---- 4c. Ensure Notepad++ auto-update is disabled in config.xml ----
    # After warm-up, config.xml should exist. Patch it directly as safety net.
    $nppConfigDir = "C:\Users\Docker\AppData\Roaming\Notepad++"
    $nppConfig = Join-Path $nppConfigDir "config.xml"
    if (Test-Path $nppConfig) {
        $content = Get-Content $nppConfig -Raw -ErrorAction SilentlyContinue
        if ($content -and ($content -match 'noUpdate="no"')) {
            $content = $content -replace 'noUpdate="no"', 'noUpdate="yes"'
            Set-Content $nppConfig -Value $content -ErrorAction SilentlyContinue
            Write-Host "Notepad++ auto-update patched in config.xml"
        } elseif ($content -and ($content -match 'noUpdate="yes"')) {
            Write-Host "Notepad++ auto-update already disabled"
        } else {
            Write-Host "WARNING: Could not find noUpdate setting in config.xml"
        }
    } else {
        Write-Host "WARNING: Notepad++ config.xml not found at $nppConfig"
    }

    # ---- 5. Verify Talon installation ----
    $talonExe = "C:\Program Files\Talon\talon.exe"
    if (-not (Test-Path $talonExe)) {
        # Try to find it
        $found = Get-ChildItem "C:\Program Files\Talon" -Recurse -Filter "talon.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $talonExe = $found.FullName
            Write-Host "Found Talon at: $talonExe"
        } else {
            Write-Host "WARNING: talon.exe not found. Listing C:\Program Files\Talon:"
            Get-ChildItem "C:\Program Files\Talon" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name)" }
        }
    }

    # ---- 6. Verify community command set ----
    $communityDir = Join-Path $talonUserDir "community"
    if (Test-Path $communityDir) {
        $talonFiles = (Get-ChildItem $communityDir -Recurse -Filter "*.talon" -ErrorAction SilentlyContinue).Count
        $pyFiles = (Get-ChildItem $communityDir -Recurse -Filter "*.py" -ErrorAction SilentlyContinue).Count
        Write-Host "Community command set present: $talonFiles .talon files, $pyFiles .py files"

        # List key directories
        Write-Host "Community directories:"
        Get-ChildItem $communityDir -Directory | ForEach-Object { Write-Host "  $($_.Name)/" }
    } else {
        Write-Host "WARNING: Community command set not found at $communityDir"
    }

    # ---- 6b. Dismiss community welcome overlay permanently ----
    # The new_user_message plugin checks for a file called "new_user_message_dismissed"
    # in the plugin directory. Creating this file prevents the welcome overlay on startup.
    $dismissFile = Join-Path $communityDir "plugin\new_user_message\new_user_message_dismissed"
    if (-not (Test-Path $dismissFile)) {
        New-Item -ItemType File -Force -Path $dismissFile | Out-Null
        Write-Host "Created new_user_message_dismissed file"
    } else {
        Write-Host "new_user_message_dismissed file already exists"
    }

    # ---- 7. Warm-up launch of Talon ----
    # Talon first-run shows: EULA dialog -> audio error notification
    # The community welcome overlay is prevented by the dismissal file above.
    Write-Host "Warming up Talon (first-run cycle)..."
    if (Test-Path $talonExe) {
        $warmupScript = "C:\Windows\Temp\warmup_talon.cmd"
        $warmupContent = "@echo off`r`nstart `"`" `"$talonExe`""
        [System.IO.File]::WriteAllText($warmupScript, $warmupContent)

        $prevEAP = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            $taskName = "WarmupTalon_GA"
            $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
            schtasks /Create /TN $taskName /TR "cmd /c $warmupScript" `
                /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN $taskName 2>$null
            Start-Sleep -Seconds 15

            # Helper to click via PyAutoGUI
            function Click-PyAutoGUI([int]$x, [int]$y) {
                $json = "{`"action`":`"click`",`"x`":$x,`"y`":$y}"
                try {
                    $cl = New-Object System.Net.Sockets.TcpClient
                    $cl.Connect("127.0.0.1", 5555)
                    $s = $cl.GetStream()
                    $w = New-Object System.IO.StreamWriter($s)
                    $w.AutoFlush = $true
                    $w.WriteLine($json)
                    $r = New-Object System.IO.StreamReader($s)
                    $resp = $r.ReadLine()
                    $cl.Close()
                    return $resp
                } catch {
                    return "error: $_"
                }
            }

            # Phase 1: Accept EULA dialog - click at multiple possible positions
            Write-Host "Dismissing EULA dialog..."
            $eulaPositions = @(@(627, 433), @(648, 458), @(700, 511), @(717, 552))
            foreach ($pos in $eulaPositions) {
                $result = Click-PyAutoGUI $pos[0] $pos[1]
                Write-Host "EULA click ($($pos[0]),$($pos[1])): $result"
                Start-Sleep -Seconds 2
            }

            # Phase 2: Community welcome overlay is suppressed by new_user_message_dismissed file

            # Phase 3: Dismiss audio error notification - X button at (1242, 572)
            Write-Host "Dismissing audio error notification..."
            $result = Click-PyAutoGUI 1242 572
            Write-Host "Audio notification click: $result"
            Start-Sleep -Seconds 3

            # Kill Talon to complete first-run cycle
            Get-Process talon -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3

            # Cleanup
            schtasks /Delete /TN $taskName /F 2>$null
            Remove-Item $warmupScript -Force -ErrorAction SilentlyContinue
        } finally {
            $ErrorActionPreference = $prevEAP
        }
        Write-Host "Talon warm-up complete."
    } else {
        Write-Host "WARNING: Skipping warm-up - talon.exe not found"
    }

    # ---- 8. Create desktop shortcut for file explorer to Talon user dir ----
    Write-Host "Creating desktop shortcuts..."
    $shortcutContent = @"
@echo off
start explorer "$communityDir"
"@
    $shortcutPath = Join-Path $desktopDir "Open_Talon_Commands.cmd"
    [System.IO.File]::WriteAllText($shortcutPath, $shortcutContent)

    # ---- 9. Minimize terminal windows ----
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
    Get-Process cmd -ErrorAction SilentlyContinue | ForEach-Object {
        [Win32]::ShowWindow($_.MainWindowHandle, 6) | Out-Null
    }

    Write-Host "=== Talon Voice environment setup complete ==="
    Write-Host "Talon exe: $talonExe"
    Write-Host "Community dir: $communityDir"
    Write-Host "Tasks dir: $talonTasksDir"
    Write-Host "Editor: $editor"
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
