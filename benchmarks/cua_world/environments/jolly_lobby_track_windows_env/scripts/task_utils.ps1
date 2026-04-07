# Shared utility functions for Jolly Lobby Track Windows environment tasks.

# ---- Paths ----
$Script:DataDir = "C:\Users\Docker\LobbyTrack\data"
$Script:DocumentsDir = "C:\Users\Docker\Documents"
$Script:DesktopDir = "C:\Users\Docker\Desktop"

function Find-LobbyTrackExe {
    <#
    .SYNOPSIS
    Locates the Lobby Track executable.
    #>

    # Check saved path first (handle corrupt/null-byte files gracefully)
    $savedPath = "C:\Users\Docker\lobbytrack_path.txt"
    if (Test-Path $savedPath) {
        try {
            $candidate = (Get-Content $savedPath -Raw).Trim("`0", " ", "`r", "`n")
            if ($candidate -and $candidate.Length -gt 3 -and (Test-Path $candidate)) {
                return $candidate
            }
        } catch {
            Write-Host "Warning: Could not read lobbytrack_path.txt: $_"
        }
    }

    # Search known paths
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
            return $p
        }
    }

    # Broader search
    $found = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse `
        -Filter "LobbyTrack*.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch "Setup|Uninstall" } |
        Select-Object -First 1
    if ($found) {
        return $found.FullName
    }

    throw "Could not find Lobby Track executable"
}

function Launch-LobbyTrackInteractive {
    <#
    .SYNOPSIS
    Launches Lobby Track in the interactive desktop session (Session 1) via schtasks.
    #>
    param(
        [string] $LobbyExe = "",
        [int] $WaitSeconds = 20
    )

    if (-not $LobbyExe) {
        $LobbyExe = Find-LobbyTrackExe
    }

    if (-not (Test-Path $LobbyExe)) {
        throw "Lobby Track executable not found at: $LobbyExe"
    }

    # Kill any existing instances first
    Close-LobbyTrack

    # Must cd to install dir for DLL dependencies
    $lobbyDir = Split-Path $LobbyExe -Parent
    $launchScript = "C:\Windows\Temp\launch_lobbytrack.bat"
    $batchContent = "@echo off`r`ncd /d `"$lobbyDir`"`r`nstart `"`" `"$LobbyExe`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchLobbyTrack_GA"

    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN $taskName /TR $launchScript `
            /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }

    # Wait for window to appear
    Wait-ForLobbyTrackWindow -TimeoutSeconds 60

    # Dismiss any startup dialogs
    Dismiss-LobbyTrackDialogs
}

function Close-LobbyTrack {
    <#
    .SYNOPSIS
    Cleanly closes all Lobby Track processes.
    #>
    $processNames = @("LobbyTrack", "Lobby Track", "LobbyTrackFree")
    foreach ($name in $processNames) {
        Get-Process $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    # Also kill by pattern
    Get-Process | Where-Object { $_.Name -match "LobbyTrack|Lobby" } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Wait-ForLobbyTrackWindow {
    <#
    .SYNOPSIS
    Polls for a Lobby Track window to appear.
    #>
    param(
        [int] $TimeoutSeconds = 60
    )

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $procs = Get-Process | Where-Object {
            $_.Name -match "LobbyTrack|Lobby" -and $_.MainWindowTitle -ne ""
        } -ErrorAction SilentlyContinue
        if ($procs) {
            Write-Host "Lobby Track window detected"
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    Write-Host "WARNING: Lobby Track window not detected within ${TimeoutSeconds}s"
    return $false
}

function Test-LobbyTrackRunning {
    <#
    .SYNOPSIS
    Checks if Lobby Track is currently running with a visible window.
    #>
    $procs = Get-Process | Where-Object {
        $_.Name -match "LobbyTrack|Lobby" -and $_.MainWindowTitle -ne ""
    } -ErrorAction SilentlyContinue
    return ($null -ne $procs)
}

function Ensure-LobbyTrackRunning {
    <#
    .SYNOPSIS
    Ensures Lobby Track is running. Launches it if not already running.
    Retries up to 2 times.
    #>
    if (Test-LobbyTrackRunning) {
        Write-Host "Lobby Track is already running"
        Dismiss-LobbyTrackDialogs
        return
    }

    $maxAttempts = 2
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Write-Host "Starting Lobby Track (attempt $attempt of $maxAttempts)..."
        try {
            Launch-LobbyTrackInteractive
            if (Test-LobbyTrackRunning) {
                Write-Host "Lobby Track started successfully"
                return
            }
        } catch {
            Write-Host "Launch attempt $attempt failed: $_"
        }

        if ($attempt -lt $maxAttempts) {
            Write-Host "Retrying..."
            Start-Sleep -Seconds 5
        }
    }

    Write-Host "WARNING: Lobby Track may not have started after $maxAttempts attempts"
}

function Dismiss-LobbyTrackDialogs {
    <#
    .SYNOPSIS
    Dismisses common Lobby Track first-run dialogs (registration, activation, tips).
    Uses PyAutoGUI TCP server and keyboard shortcuts.
    #>

    # Try running the dedicated dismiss script
    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (Test-Path $dismissScript) {
        $prevEAP = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            & powershell -ExecutionPolicy Bypass -File $dismissScript 2>$null
        } finally {
            $ErrorActionPreference = $prevEAP
        }
    }

    # Run dialog dismissal sequence twice with delays to handle timing variability.
    # Dialogs appear asynchronously after app launch and may not all be present on first pass.
    for ($pass = 1; $pass -le 2; $pass++) {
        Write-Host "Dialog dismissal pass $pass..."

        # Dialog 0: Language Selection → Press Enter to accept English
        Start-Sleep -Seconds 3
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "enter"} } catch { }
        Start-Sleep -Seconds 5

        # Dialog 1: FREE Edition Classification → Click "Continue" at (640, 399)
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 640; y = 399} } catch { }
        Start-Sleep -Seconds 3

        # Dialog 2: Configure Workstation → Uncheck "Show at startup" + Close
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 391; y = 523} } catch { }
        Start-Sleep -Seconds 1
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 884; y = 184} } catch { }
        Start-Sleep -Seconds 2

        # Generic fallback dismissals
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "escape"} } catch { }
    }
    Start-Sleep -Seconds 1
    try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "enter"} } catch { }
    Start-Sleep -Seconds 1
}

# ---- PyAutoGUI Helper Functions ----

function Invoke-PyAutoGUICommand {
    <#
    .SYNOPSIS
    Sends a command to the PyAutoGUI TCP server running on port 5555.
    #>
    param(
        [Parameter(Mandatory = $true)] [hashtable] $Command,
        [string] $ServerHost = "127.0.0.1",
        [int] $Port = 5555,
        [int] $ConnectTimeoutMs = 3000
    )

    $json = $Command | ConvertTo-Json -Compress
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($ServerHost, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($ConnectTimeoutMs, $false)) {
            throw "PyAutoGUI server connection timeout"
        }
        $client.EndConnect($iar)

        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true
        $writer.WriteLine($json)

        $reader = New-Object System.IO.StreamReader($stream)
        $line = $reader.ReadLine()
        if (-not $line) { throw "Empty response from PyAutoGUI server" }
        $resp = $line | ConvertFrom-Json
        if ($resp.success -eq $false) {
            throw "PyAutoGUI error: $($resp.error)"
        }
        return $resp
    } finally {
        try { $client.Close() } catch { }
    }
}

function PyAutoGUI-Click {
    <#
    .SYNOPSIS
    Clicks at the given coordinates via PyAutoGUI server.
    Coordinates are in 1280x720 screen space.
    #>
    param(
        [Parameter(Mandatory = $true)] [int] $X,
        [Parameter(Mandatory = $true)] [int] $Y
    )
    Invoke-PyAutoGUICommand -Command @{action = "click"; x = $X; y = $Y}
}

function PyAutoGUI-DoubleClick {
    <#
    .SYNOPSIS
    Double-clicks at the given coordinates via PyAutoGUI server.
    #>
    param(
        [Parameter(Mandatory = $true)] [int] $X,
        [Parameter(Mandatory = $true)] [int] $Y
    )
    Invoke-PyAutoGUICommand -Command @{action = "doubleClick"; x = $X; y = $Y}
}

function PyAutoGUI-Press {
    <#
    .SYNOPSIS
    Presses a key via PyAutoGUI server.
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $Keys
    )
    Invoke-PyAutoGUICommand -Command @{action = "press"; keys = $Keys}
}

function PyAutoGUI-Type {
    <#
    .SYNOPSIS
    Types text via PyAutoGUI server.
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $Text
    )
    Invoke-PyAutoGUICommand -Command @{action = "typewrite"; text = $Text}
}

function PyAutoGUI-Hotkey {
    <#
    .SYNOPSIS
    Presses a hotkey combination via PyAutoGUI server.
    #>
    param(
        [Parameter(Mandatory = $true)] [string[]] $Keys
    )
    Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = $Keys}
}

function Minimize-TerminalWindows {
    <#
    .SYNOPSIS
    Minimizes all cmd.exe windows to keep the desktop clean.
    #>
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Min {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
    Get-Process cmd -ErrorAction SilentlyContinue | ForEach-Object {
        [Win32Min]::ShowWindow($_.MainWindowHandle, 6) | Out-Null
    }
}

function Record-TaskStartTime {
    <#
    .SYNOPSIS
    Records the task start time for verification purposes.
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $TaskName
    )
    $epoch = [int][double]::Parse((Get-Date -UFormat %s))
    [System.IO.File]::WriteAllText("C:\Windows\Temp\${TaskName}_start_time", "$epoch")
    Write-Host "Task $TaskName start time: $(Get-Date)"
}
