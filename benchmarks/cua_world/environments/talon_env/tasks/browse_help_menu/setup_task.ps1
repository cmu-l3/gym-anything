Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_browse_help_menu.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up browse_help_menu task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Kill Notepad++ and any existing Explorer windows to start clean
    Get-Process notepad++ -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        # Close any open Explorer windows (not the shell itself)
        Get-Process explorer -ErrorAction SilentlyContinue | Where-Object {
            $_.MainWindowTitle -ne ""
        } | ForEach-Object {
            # Only close named windows, not the desktop shell
            try {
                $_.CloseMainWindow() | Out-Null
            } catch { }
        }
    } finally {
        $ErrorActionPreference = $prevEAP
    }
    Start-Sleep -Seconds 2

    # Dismiss community welcome overlay permanently by creating dismissal file
    $dismissFile = Join-Path $Script:CommunityDir "plugin\new_user_message\new_user_message_dismissed"
    if (-not (Test-Path $dismissFile)) {
        New-Item -ItemType File -Force -Path $dismissFile | Out-Null
        Write-Host "Created new_user_message_dismissed file"
    }

    # Ensure Talon is running in the system tray
    $talonRunning = Get-Process talon -ErrorAction SilentlyContinue
    if (-not $talonRunning) {
        Write-Host "Talon not running, launching and dismissing first-run dialogs..."

        # Launch Talon via schtasks (inline, not via function to avoid early exit issues)
        $talonExe = Find-TalonExe
        $launchScript = "C:\Windows\Temp\launch_talon_task.cmd"
        $batchContent = "@echo off`r`nstart `"`" `"$talonExe`""
        [System.IO.File]::WriteAllText($launchScript, $batchContent)

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN "LaunchTalonTask_GA" /TR "cmd /c $launchScript" /SC ONCE /ST ((Get-Date).AddMinutes(1).ToString("HH:mm")) /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN "LaunchTalonTask_GA" 2>$null
        Start-Sleep -Seconds 15
        schtasks /Delete /TN "LaunchTalonTask_GA" /F 2>$null
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue

        # Dismiss first-run dialogs via PyAutoGUI TCP
        function Send-Click([int]$cx, [int]$cy) {
            $json = "{`"action`":`"click`",`"x`":$cx,`"y`":$cy}"
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
                return "click_error: $_"
            }
        }

        # Click EULA "I Accept" at multiple possible positions (window position varies)
        $eulaPositions = @(
            @(627, 433),
            @(648, 458),
            @(700, 511),
            @(717, 552)
        )
        foreach ($pos in $eulaPositions) {
            $r = Send-Click $pos[0] $pos[1]
            Write-Host "EULA click ($($pos[0]),$($pos[1])): $r"
            Start-Sleep -Seconds 2
        }

        # Wait for Talon to stabilize after EULA acceptance
        Start-Sleep -Seconds 5

        # Audio error notification X at (1242, 572)
        $r2 = Send-Click 1242 572
        Write-Host "Audio click: $r2"
        Start-Sleep -Seconds 2

        # Minimize all windows (Win+D) to clean desktop
        $winD = '{"action":"hotkey","keys":["win","d"]}'
        try {
            $cl = New-Object System.Net.Sockets.TcpClient
            $cl.Connect("127.0.0.1", 5555)
            $s = $cl.GetStream()
            $w = New-Object System.IO.StreamWriter($s)
            $w.AutoFlush = $true
            $w.WriteLine($winD)
            $r = New-Object System.IO.StreamReader($s)
            $resp = $r.ReadLine()
            Write-Host "Win+D: $resp"
            $cl.Close()
        } catch {
            Write-Host "Win+D error: $_"
        }
        Start-Sleep -Seconds 2

        $ErrorActionPreference = $prevEAP
        Write-Host "Talon launched and dialogs dismissed"
    } else {
        Write-Host "Talon is already running (PID: $($talonRunning.Id))"
    }

    # Verify community dir exists
    if (Test-Path $Script:CommunityDir) {
        $dirs = Get-ChildItem $Script:CommunityDir -Directory | Select-Object -ExpandProperty Name
        Write-Host "Community directories present: $($dirs -join ', ')"
    } else {
        Write-Host "WARNING: Community directory not found at $Script:CommunityDir"
    }

    # Minimize terminal windows
    Minimize-TerminalWindows

    Write-Host "=== browse_help_menu task setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
