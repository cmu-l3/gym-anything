Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up Jolly Lobby Track environment ==="

    # ---- 1. Disable OneDrive (safety net) ----
    Write-Host "Disabling OneDrive..."
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -Name "OneDrive" -ErrorAction SilentlyContinue

    # ---- 2. Locate Lobby Track executable ----
    Write-Host "Locating Lobby Track executable..."
    $lobbyExe = $null

    # Check saved path from install
    $savedPath = "C:\Users\Docker\lobbytrack_path.txt"
    if (Test-Path $savedPath) {
        $candidate = (Get-Content $savedPath -Raw).Trim()
        if (Test-Path $candidate) {
            $lobbyExe = $candidate
        }
    }

    # Search known paths
    if (-not $lobbyExe) {
        $searchPaths = @(
            "C:\Program Files (x86)\Jolly Technologies\Lobby Track\LobbyTrack.exe",
            "C:\Program Files\Jolly Technologies\Lobby Track\LobbyTrack.exe",
            "C:\Program Files (x86)\Jolly\Lobby Track\LobbyTrack.exe",
            "C:\Program Files\Jolly\Lobby Track\LobbyTrack.exe",
            "C:\Program Files (x86)\LobbyTrack\LobbyTrack.exe",
            "C:\Program Files\LobbyTrack\LobbyTrack.exe"
        )
        foreach ($p in $searchPaths) {
            if (Test-Path $p) {
                $lobbyExe = $p
                break
            }
        }
    }

    # Broader search
    if (-not $lobbyExe) {
        $found = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse `
            -Filter "LobbyTrack*.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch "Setup|Uninstall" } |
            Select-Object -First 1
        if ($found) {
            $lobbyExe = $found.FullName
        }
    }

    if ($lobbyExe) {
        Write-Host "Found Lobby Track at: $lobbyExe"
        [System.IO.File]::WriteAllText("C:\Users\Docker\lobbytrack_path.txt", $lobbyExe)
    } else {
        Write-Host "WARNING: Lobby Track executable not found"
    }

    # ---- 3. Create working directories ----
    Write-Host "Setting up working directories..."
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents" | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop" | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\LobbyTrack\data" | Out-Null

    # ---- 4. Copy data files from workspace ----
    if (Test-Path "C:\workspace\data") {
        Write-Host "Copying visitor data from workspace..."
        Copy-Item "C:\workspace\data\*" -Destination "C:\Users\Docker\LobbyTrack\data\" `
            -Recurse -Force -ErrorAction SilentlyContinue
        # Also copy to Documents for easy access
        Copy-Item "C:\workspace\data\*.csv" -Destination "C:\Users\Docker\Documents\" `
            -Force -ErrorAction SilentlyContinue
    }

    # ---- 5. Warm-up launch of Lobby Track ----
    # First launch may trigger: registration dialogs, license prompts,
    # database creation, .NET runtime dialogs. This warm-up clears them.
    if ($lobbyExe) {
        Write-Host "Warming up Lobby Track (first-run cycle)..."

        # PyAutoGUI helper for warm-up
        function Send-WarmupPyAutoGUI([string]$json) {
            $client = New-Object System.Net.Sockets.TcpClient
            $ar = $client.BeginConnect("127.0.0.1", 5555, $null, $null)
            $waited = $ar.AsyncWaitHandle.WaitOne(5000, $false)
            if (-not $waited -or -not $client.Connected) {
                $client.Close()
                return $null
            }
            $client.EndConnect($ar)
            $stream = $client.GetStream()
            $stream.ReadTimeout = 10000
            $stream.WriteTimeout = 5000
            $writer = New-Object System.IO.StreamWriter($stream)
            $writer.AutoFlush = $true
            $writer.WriteLine($json)
            $reader = New-Object System.IO.StreamReader($stream)
            $line = $reader.ReadLine()
            $client.Close()
            return $line
        }

        function WarmupClick([int]$x, [int]$y) {
            $json = "{`"action`":`"click`",`"x`":$x,`"y`":$y}"
            $resp = Send-WarmupPyAutoGUI $json
            Write-Host "  WarmupClick($x,$y) -> $resp"
            return $resp
        }

        function WarmupPress([string]$key) {
            $json = "{`"action`":`"press`",`"key`":`"$key`"}"
            $resp = Send-WarmupPyAutoGUI $json
            Write-Host "  WarmupPress($key) -> $resp"
            return $resp
        }

        $prevEAP = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"

            # Launch Lobby Track in Session 1
            $lobbyDir = Split-Path $lobbyExe -Parent
            $warmupBat = "C:\Windows\Temp\warmup_lobbytrack.bat"
            [System.IO.File]::WriteAllText($warmupBat, "@echo off`r`ncd /d `"$lobbyDir`"`r`nstart `"`" `"$lobbyExe`"")
            $taskName = "WarmupLobbyTrack_GA"
            schtasks /Create /TN $taskName /TR $warmupBat `
                /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN $taskName 2>$null
            Write-Host "Launched Lobby Track in interactive session"

            # Wait for process to appear
            $maxWait = 30
            for ($i = 0; $i -lt $maxWait; $i++) {
                $proc = Get-Process | Where-Object { $_.Name -match "LobbyTrack|Lobby" } -ErrorAction SilentlyContinue
                if ($proc) {
                    Write-Host "Lobby Track process found"
                    break
                }
                Start-Sleep -Seconds 1
            }
            Start-Sleep -Seconds 15

            # Dismiss startup dialogs — Lobby Track Free shows two dialogs on every launch:
            # 1. FREE Edition Classification → Click "Continue" at (641, 401)
            # 2. Configure Workstation wizard → Uncheck "Show at startup" (391, 523), close X (884, 184)
            Write-Host "Dismissing startup dialogs..."

            # Dialog 0: Language Selection → Press Enter to accept English
            WarmupPress "enter"
            Start-Sleep -Seconds 5

            # Dialog 1: FREE Edition Classification → Click Continue
            WarmupClick 641 401
            Start-Sleep -Seconds 3

            # Dialog 2: Configure Workstation → Uncheck "Show at startup" + Close
            WarmupClick 391 523
            Start-Sleep -Seconds 1
            WarmupClick 884 184
            Start-Sleep -Seconds 2

            # Generic fallback for any remaining dialogs
            WarmupPress "escape"
            Start-Sleep -Seconds 1
            WarmupPress "enter"
            Start-Sleep -Seconds 1

            Write-Host "Warmup dialog dismissal complete"

            # Kill warm-up instance
            Write-Host "Closing warm-up instance..."
            Get-Process | Where-Object { $_.Name -match "LobbyTrack|Lobby" } |
                Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3

            # Cleanup
            schtasks /Delete /TN $taskName /F 2>$null
            Remove-Item $warmupBat -Force -ErrorAction SilentlyContinue
        } finally {
            $ErrorActionPreference = $prevEAP
        }
        Write-Host "Lobby Track warm-up complete."
    } else {
        Write-Host "WARNING: Skipping warm-up - Lobby Track executable not found"
    }

    # ---- 6. Minimize terminal windows ----
    Write-Host "Minimizing terminal windows..."
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Setup {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
    Get-Process cmd -ErrorAction SilentlyContinue | ForEach-Object {
        [Win32Setup]::ShowWindow($_.MainWindowHandle, 6) | Out-Null
    }

    Write-Host "=== Jolly Lobby Track environment setup complete ==="
    if ($lobbyExe) {
        Write-Host "Lobby Track exe: $lobbyExe"
    }
    Write-Host "Data dir: C:\Users\Docker\LobbyTrack\data"
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
