# Shared utility functions for Talon environment tasks.

# ---- Paths ----
$Script:TalonExe = "C:\Program Files\Talon\talon.exe"
$Script:TalonUserDir = "C:\Users\Docker\AppData\Roaming\Talon\user"
$Script:CommunityDir = Join-Path $Script:TalonUserDir "community"
$Script:TalonTasksDir = "C:\Users\Docker\Desktop\TalonTasks"

function Find-TalonExe {
    <#
    .SYNOPSIS
    Locates the Talon executable.
    #>
    if (Test-Path $Script:TalonExe) {
        return $Script:TalonExe
    }
    $found = Get-ChildItem "C:\Program Files\Talon" -Recurse -Filter "talon.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        return $found.FullName
    }
    throw "Could not find talon.exe"
}

function Find-Editor {
    <#
    .SYNOPSIS
    Finds the best available text editor (Notepad++ or Notepad).
    Returns full path.
    #>
    $npp = "C:\Program Files\Notepad++\notepad++.exe"
    if (Test-Path $npp) {
        return $npp
    }
    return "notepad.exe"
}

function Test-TalonRunning {
    # True once Talon is running with a non-trivial working set.
    # Talon is a system-tray app with no main window, so we check process
    # existence and working set rather than MainWindowHandle.
    $procs = Get-Process talon -ErrorAction SilentlyContinue
    if (-not $procs) { return $false }
    foreach ($p in @($procs)) {
        if ($p.WorkingSet64 -gt 10MB -or $p.MainWindowHandle -ne 0) { return $true }
    }
    return $false
}

function Launch-TalonInteractive {
    <#
    .SYNOPSIS
    Launches Talon in the interactive desktop session via schtasks /IT (Session 1).
    Retries until Talon is confirmed running, to survive cold-boot launch hangs.
    Talon is a system-tray app so it won't have a visible main window.
    #>
    param(
        [string] $TalonExe = "",
        [int] $WaitSeconds = 25,
        [int] $MaxAttempts = 4
    )

    if (-not $TalonExe) {
        $TalonExe = Find-TalonExe
    }

    if (-not (Test-Path $TalonExe)) {
        throw "Talon executable not found at: $TalonExe"
    }

    $launchScript = "C:\Windows\Temp\launch_talon.cmd"
    $batchContent = "@echo off`r`nstart `"`" `"$TalonExe`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchTalon_GA"
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        # Cold-boot interactive sessions can hang the first launch. Launch, verify
        # Talon is actually running (working set climbs past the hung baseline),
        # and retry (kill + relaunch) until it does.
        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            Kill-AllTalon
            $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
            schtasks /Create /TN $taskName /TR "cmd /c $launchScript" `
                /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN $taskName 2>$null
            schtasks /Delete /TN $taskName /F 2>$null
            $waited = 0
            while ($waited -lt $WaitSeconds) {
                Start-Sleep -Seconds 3
                $waited += 3
                if (Test-TalonRunning) { break }
            }
            if (Test-TalonRunning) {
                Write-Host "Talon running on attempt $attempt."
                return
            }
            Write-Host "Talon did not start on attempt $attempt (cold-boot hang); retrying..."
        }
        Write-Host "WARNING: Talon failed to start after $MaxAttempts attempts."
    } finally {
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }
}

function Kill-AllTalon {
    <#
    .SYNOPSIS
    Force-kills all Talon-related processes.
    #>
    $processNames = @("talon", "talon_app")
    foreach ($name in $processNames) {
        Get-Process $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

function Open-FileInteractive {
    <#
    .SYNOPSIS
    Opens a file in the text editor via schtasks (interactive session).
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $FilePath,
        [int] $WaitSeconds = 8
    )

    if (-not (Test-Path $FilePath)) {
        throw "File not found: $FilePath"
    }

    $editor = Find-Editor
    $launchScript = "C:\Windows\Temp\open_file.cmd"
    $batchContent = "@echo off`r`nstart `"`" `"$editor`" `"$FilePath`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "OpenFile_GA"
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")

    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN $taskName /TR "cmd /c $launchScript" `
            /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }
}

function Open-FolderInteractive {
    <#
    .SYNOPSIS
    Opens a folder in Windows Explorer via schtasks (interactive session).
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $FolderPath,
        [int] $WaitSeconds = 5
    )

    if (-not (Test-Path $FolderPath)) {
        throw "Folder not found: $FolderPath"
    }

    $launchScript = "C:\Windows\Temp\open_folder.cmd"
    $batchContent = "@echo off`r`nstart explorer `"$FolderPath`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "OpenFolder_GA"
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")

    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN $taskName /TR "cmd /c $launchScript" `
            /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }
}

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
