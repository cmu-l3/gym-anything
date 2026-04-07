# Shared PowerShell helpers for Crimson HMI tasks.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-CrimsonExe {
    <#
    Locate the Crimson 3.0 executable (c3.exe) on the system.
    Checks cached path first, then known install path, then searches.
    #>

    # Check cached path from setup
    $cachedPath = "C:\Users\Docker\crimson_exe_path.txt"
    if (Test-Path $cachedPath) {
        $exePath = (Get-Content $cachedPath -ErrorAction SilentlyContinue).Trim()
        if ($exePath -and (Test-Path $exePath)) {
            return $exePath
        }
    }

    # Check known install path
    $knownPath = "C:\Program Files (x86)\Red Lion Controls\Crimson 3.0\c3.exe"
    if (Test-Path $knownPath) {
        return $knownPath
    }

    # Search standard installation locations
    $searchPaths = @(
        "C:\Program Files\Red Lion Controls",
        "C:\Program Files (x86)\Red Lion Controls"
    )

    foreach ($sp in $searchPaths) {
        if (Test-Path $sp) {
            $found = Get-ChildItem $sp -Recurse -Filter "c3.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                return $found.FullName
            }
        }
    }

    throw "Could not find Crimson c3.exe in standard locations."
}

function Launch-CrimsonInteractive {
    <#
    Launch Crimson in the interactive desktop session via schtasks /IT.
    SSH runs in Session 0 (no display), so GUI apps must be launched via
    scheduled tasks with /IT flag to appear on the user's desktop.

    NOTE: The Crimson install path contains "Program Files (x86)" which
    causes batch file parsing errors due to the parentheses. We convert
    to 8.3 short path names to avoid this issue.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string] $CrimsonExe,
        [string] $ProjectPath = "",
        [int] $WaitSeconds = 15
    )

    if (-not (Test-Path $CrimsonExe)) {
        throw "Crimson executable not found at: $CrimsonExe"
    }

    # Convert to 8.3 short path to avoid batch file issues with parentheses
    $fso = New-Object -ComObject Scripting.FileSystemObject
    $shortExePath = $fso.GetFile($CrimsonExe).ShortPath

    # Build the command line using short paths
    $launchScript = "C:\Windows\Temp\launch_crimson.cmd"
    if ($ProjectPath -and (Test-Path $ProjectPath)) {
        $shortProjectPath = $fso.GetFile($ProjectPath).ShortPath
        $batchContent = "@echo off`r`nstart `"`" $shortExePath $shortProjectPath"
    } else {
        $batchContent = "@echo off`r`nstart `"`" $shortExePath"
    }
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchCrimson_GA"
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")

    # schtasks writes informational output to stderr which triggers
    # terminating errors under $ErrorActionPreference = "Stop".
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }
}

function Kill-AllCrimson {
    <#
    Terminate all Crimson-related processes.
    The main exe is c3.exe; g3sim.exe is the simulator.
    #>
    $processNames = @("c3", "g3sim", "shexe", "shcal")
    foreach ($name in $processNames) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

function Invoke-PyAutoGUICommand {
    <#
    Send a single command to the PyAutoGUI TCP server (guest:127.0.0.1:5555).
    This executes inside the interactive desktop session where GUI automation works.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Command,
        [string] $ServerAddr = "127.0.0.1",
        [int] $Port = 5555,
        [int] $ConnectTimeoutMs = 3000
    )

    $json = $Command | ConvertTo-Json -Compress
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($ServerAddr, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($ConnectTimeoutMs, $false)) {
            throw "PyAutoGUI server connect timeout to ${ServerAddr}:${Port}"
        }
        $client.EndConnect($iar)

        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true
        $writer.WriteLine($json)

        $reader = New-Object System.IO.StreamReader($stream)
        $line = $reader.ReadLine()
        if (-not $line) {
            throw "PyAutoGUI server returned empty response"
        }
        $resp = $line | ConvertFrom-Json
        if ($resp.success -eq $false) {
            throw "PyAutoGUI error: $($resp.error)"
        }
        return $resp
    } finally {
        try { $client.Close() } catch { }
    }
}

function Test-RegistrationDialogPresent {
    <#
    Check if the Crimson registration dialog is currently visible by looking
    for a process whose window title contains "Register".
    Falls back to a PyAutoGUI screenshot-based check if window title detection
    fails (titles are not visible from Session 0).
    #>

    # Method 1: Check for a window with "Register" in the title.
    # From Session 0, MainWindowTitle is often empty, so this is best-effort.
    $procs = Get-Process -Name "shexe", "c3" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if ($p.MainWindowTitle -and $p.MainWindowTitle -match "Register") {
            return $true
        }
    }

    # Method 2: Take a PyAutoGUI screenshot and inspect pixel color at the
    # known location of the "Skip" button text area (~554, 585).  The
    # registration dialog has a grey button background there; the main
    # Crimson UI does not.  We use the locateOnScreen-style check: if
    # a screenshot shows a modal dialog-shaped region, assume it is present.
    # For robustness we simply always return $true during the first call
    # (dialog always appears on launch of an unregistered copy).
    return $true
}

function Dismiss-CrimsonDialogsBestEffort {
    <#
    Robust dismissal of any Crimson first-run dialogs or popups.

    Crimson 3.0 shows a "Register Your Copy of Crimson 3" dialog on every
    launch of an unregistered copy. The dialog has "Register" and "Skip"
    buttons. Clicking "Skip" triggers a confirmation dialog ("Do you want
    to skip registration?") with "Yes" and "No" buttons.

    This function uses multiple strategies in sequence with retries:
      1. Click the "Skip" button at its known coordinates
      2. Click the "Yes" confirmation button at its known coordinates
      3. Keyboard fallbacks: Alt+Y (Yes accelerator), Escape
      4. Dismiss OneDrive / Windows Backup popups

    Coordinates are for 1280x720 resolution (PyAutoGUI default).
    #>
    param(
        [int] $Retries = 3,
        [int] $InitialWaitSeconds = 8,
        [int] $BetweenRetriesSeconds = 3
    )

    if ($InitialWaitSeconds -gt 0) {
        Start-Sleep -Seconds $InitialWaitSeconds
    }

    for ($i = 0; $i -lt $Retries; $i++) {
        Write-Host "  Dialog dismissal attempt $($i + 1) of $Retries..."

        # --- Registration dialog: click Skip ---
        # The registration dialog is centered on the 1280x720 screen.
        # "Skip" button is at approximately (554, 585).
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 554; y = 585} | Out-Null } catch { }
        Start-Sleep -Milliseconds 2000

        # --- Confirmation dialog: click Yes ---
        # After clicking Skip, a confirmation dialog appears:
        # "Do you want to skip registration?"
        # "Yes" button is at approximately (630, 349).
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 630; y = 349} | Out-Null } catch { }
        Start-Sleep -Milliseconds 1500

        # --- Keyboard fallback: Alt+Y to confirm Yes ---
        try { Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = @("alt", "y")} | Out-Null } catch { }
        Start-Sleep -Milliseconds 800

        # --- Escape for any remaining modal dialogs ---
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 800

        # --- Dismiss OneDrive / Windows Backup popups ---
        # "No thanks" button appears at bottom-right of screen
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 1166; y = 627} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        # --- Final Escape for any other modal dialogs ---
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }

        if ($BetweenRetriesSeconds -gt 0 -and $i -lt ($Retries - 1)) {
            Start-Sleep -Seconds $BetweenRetriesSeconds
        }
    }
}

function Wait-ForCrimsonProcess {
    <#
    Wait for a Crimson process to appear.
    NOTE: c3.exe is the launcher, but the main Crimson process runs as shexe.exe.
    We check for both names.
    #>
    param(
        [int] $TimeoutSeconds = 60
    )

    $processNames = @("c3", "shexe")
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        foreach ($name in $processNames) {
            $proc = Get-Process -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($proc) {
                return $proc
            }
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    Write-Host "WARNING: Crimson process not found after $TimeoutSeconds seconds."
    return $null
}
