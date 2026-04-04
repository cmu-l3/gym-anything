# Shared PowerShell helpers for Visual Studio 2022 tasks.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-VS2022Exe {
    <#
    Search standard installation paths for devenv.exe.
    VS 2022 Community installs to Program Files (not x86 -- it is 64-bit).
    #>
    $candidates = @(
        "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\devenv.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\devenv.exe"
    )

    foreach ($p in $candidates) {
        if (Test-Path $p) {
            return $p
        }
    }

    # Search more broadly
    $vsRoot = "C:\Program Files\Microsoft Visual Studio\2022"
    if (Test-Path $vsRoot) {
        $found = Get-ChildItem $vsRoot -Recurse -Filter "devenv.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    throw "Could not find devenv.exe in standard Visual Studio locations."
}

function Find-DotnetExe {
    <#
    Find the dotnet CLI executable.
    #>
    $candidates = @(
        "C:\Program Files\dotnet\dotnet.exe",
        "$env:ProgramFiles\dotnet\dotnet.exe"
    )

    foreach ($p in $candidates) {
        if (Test-Path $p) {
            return $p
        }
    }

    # Check PATH
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($dotnet) { return $dotnet.Source }

    throw "Could not find dotnet.exe."
}

function Launch-VS2022Interactive {
    <#
    Launch Visual Studio in the interactive desktop session.
    SSH runs in Session 0 which cannot display GUI windows, so we use
    schtasks with /IT to run in the interactive session.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string] $DevenvExe,
        [string] $SolutionPath = "",
        [string] $ExtraArgs = "",
        [int] $WaitSeconds = 20
    )

    if (-not (Test-Path $DevenvExe)) {
        throw "devenv.exe not found at: $DevenvExe"
    }

    $launchScript = "C:\Windows\Temp\launch_vs.cmd"
    $cmdLine = "start `"`" `"$DevenvExe`" /nosplash"
    if ($SolutionPath -and (Test-Path $SolutionPath)) {
        $cmdLine += " `"$SolutionPath`""
    }
    if ($ExtraArgs) {
        $cmdLine += " $ExtraArgs"
    }
    $batchContent = "@echo off`r`n$cmdLine"
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchVS_GA"
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")

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

function Kill-AllVS2022 {
    <#
    Kill all Visual Studio processes. VS runs multiple sub-processes.
    #>
    $vsProcessNames = @(
        "devenv",
        "MSBuild",
        "VBCSCompiler",
        "ServiceHub.Host.dotnet.x64",
        "ServiceHub.IdentityHost",
        "ServiceHub.IndexingService",
        "ServiceHub.ThreadedWaitDialog",
        "ServiceHub.VSDetouredHost",
        "vshost",
        "PerfWatson2"
    )

    foreach ($name in $vsProcessNames) {
        Get-Process $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    # Also kill any remaining VS-related processes
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -like "ServiceHub*" -or $_.ProcessName -like "Microsoft.ServiceHub*"
    } | Stop-Process -Force -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 3
}

function Invoke-PyAutoGUICommand {
    <#
    Send a single command to the PyAutoGUI TCP server (guest:127.0.0.1:5555).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Command,
        [string] $HostAddr = "127.0.0.1",
        [int] $Port = 5555,
        [int] $ConnectTimeoutMs = 3000
    )

    $json = $Command | ConvertTo-Json -Compress
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($HostAddr, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($ConnectTimeoutMs, $false)) {
            throw "PyAutoGUI server connect timeout to ${HostAddr}:${Port}"
        }
        $client.EndConnect($iar)

        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true
        $writer.WriteLine($json)

        $reader = New-Object System.IO.StreamReader($stream)
        $line = $reader.ReadLine()
        if (-not $line) { throw "PyAutoGUI server returned empty response" }
        $resp = $line | ConvertFrom-Json
        if ($resp.success -eq $false) { throw "PyAutoGUI error: $($resp.error)" }
        return $resp
    } finally {
        try { $client.Close() } catch { }
    }
}

function Dismiss-VSDialogsBestEffort {
    <#
    Best-effort dismissal of VS 2022 first-run dialogs via PyAutoGUI.
    Coordinates are in PyAutoGUI screen space (1280x720 for this env).

    First-run dialog sequence (observed on VS 2022 Community 17.14):
    1. "Sign in to Visual Studio" -- Click "Skip and add accounts later" at (930, 442)
    2. "Personalize your Visual Studio experience" (theme picker) -- Click "Start Visual Studio" at (930, 487)
    3. "Are you sure you want to exit?" may appear from stray Escape -- Click "No" at (755, 418)

    After first-run is completed, subsequent launches skip these dialogs.
    #>
    param(
        [int] $Retries = 3,
        [int] $InitialWaitSeconds = 5,
        [int] $BetweenRetriesSeconds = 3
    )

    if ($InitialWaitSeconds -gt 0) {
        Start-Sleep -Seconds $InitialWaitSeconds
    }

    for ($i = 0; $i -lt $Retries; $i++) {
        # Click "No" on "Are you sure you want to exit?" if present
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 755; y = 418} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        # Click "Skip and add accounts later" on sign-in dialog
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 930; y = 442} | Out-Null } catch { }
        Start-Sleep -Seconds 2

        # Click "Start Visual Studio" on theme picker
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 930; y = 487} | Out-Null } catch { }
        Start-Sleep -Seconds 2

        # Escape to dismiss any remaining modal dialogs
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "escape"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        # Close any "What's New" or info tabs with Ctrl+W
        try { Invoke-PyAutoGUICommand -Command @{action = "hotkey"; keys = @("ctrl", "w")} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        if ($BetweenRetriesSeconds -gt 0) {
            Start-Sleep -Seconds $BetweenRetriesSeconds
        }
    }
}
