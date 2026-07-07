# Shared PowerShell helpers for eQUEST tasks.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-EqExe {
    <#
    Locate the eQUEST executable across common installation paths.
    Returns the full path or throws if not found.
    #>
    # Check exact paths first (directory may include build number like eQUEST 3-65-7175)
    $candidates = @(
        "C:\Program Files (x86)\eQUEST 3-65-7175\eQUEST.exe",
        "C:\Program Files (x86)\eQUEST 3-65\eQUEST.exe",
        "C:\Program Files\eQUEST 3-65-7175\eQUEST.exe",
        "C:\Program Files\eQUEST 3-65\eQUEST.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) {
            return $p
        }
    }

    # Glob search for eQUEST 3-65* directories
    $searchRoots = @("C:\Program Files (x86)", "C:\Program Files")
    foreach ($root in $searchRoots) {
        $dirs = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "eQUEST 3-65*" }
        foreach ($d in $dirs) {
            $exe = "$($d.FullName)\eQUEST.exe"
            if (Test-Path $exe) { return $exe }
        }
    }

    # Broadest search
    foreach ($root in $searchRoots) {
        $found = Get-ChildItem $root -Recurse -Filter "eQUEST.exe" -ErrorAction SilentlyContinue -Depth 3 | Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    throw "Could not find eQUEST.exe in standard installation locations."
}

function Restore-EqRegistration {
    <#
    Restore eQUEST registration values in both INI files.
    eQUEST corrupts the Registration section (Status/Special fields) on every run,
    which causes "Invalid PreviousRunDate" errors on subsequent launches.
    This function must be called BEFORE every eQUEST launch.
    #>
    $regCode = "Code=9349417631702397005-001"
    $regStatus = "Status=1000"
    $regSpecial = "Special=581413115"
    $regSection = "[Registration]`r`n$regCode`r`n$regStatus`r`n$regSpecial`r`n"

    # Restore data directory INI
    $dataIni = "C:\Users\Docker\Documents\eQUEST 3-65-7175 Data\eQUEST.INI"
    if (Test-Path $dataIni) {
        $content = Get-Content $dataIni -Raw
        $content = $content -replace '\[Registration\][\s\S]*?(?=\[|$)', $regSection
        [System.IO.File]::WriteAllText($dataIni, $content, [System.Text.Encoding]::ASCII)
        Write-Host "Registration restored in data dir INI."
    }

    # Restore install directory INI
    $eqExe = $null
    try { $eqExe = Find-EqExe } catch { }
    if ($eqExe) {
        $installDir = Split-Path $eqExe -Parent
        $installIni = "$installDir\eQUEST.ini"
        $dataPath = "C:\Users\Docker\Documents\eQUEST 3-65-7175 Data\"
        $projPath = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\"
        $iniContent = "[paths]`r`nDataPath=`"$dataPath`"`r`nProjPath=`"$projPath`"`r`n`r`n$regSection"
        [System.IO.File]::WriteAllText($installIni, $iniContent, [System.Text.Encoding]::ASCII)
        Write-Host "Registration restored in install dir INI."
    }
}

function Test-EqRendered {
    <#
    True once eQUEST has actually rendered a window. A hung cold-boot launch
    leaves the process at ~5MB working set with no window; a rendered eQUEST is
    ~25-30MB and/or has a main window handle.
    #>
    $procs = Get-Process eQUEST -ErrorAction SilentlyContinue
    if (-not $procs) { return $false }
    foreach ($p in @($procs)) {
        if ($p.WorkingSet64 -gt 15MB -or $p.MainWindowHandle -ne 0) { return $true }
    }
    return $false
}

function Launch-EqProjectInteractive {
    <#
    Launch eQUEST with a project file in the interactive desktop session.
    Uses schtasks /IT to run in Session 1 (visible on VNC).
    Restores registration before each launch and retries until eQUEST renders.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string] $EqExe,
        [Parameter(Mandatory = $false)]
        [string] $ProjectPath = "",
        [int] $WaitSeconds = 25,
        [int] $MaxAttempts = 4
    )

    if (-not (Test-Path $EqExe)) {
        throw "eQUEST executable not found at: $EqExe"
    }

    # Create a launcher batch file to avoid quoting issues with schtasks
    $launchScript = "C:\Windows\Temp\launch_equest.cmd"
    if ($ProjectPath -and (Test-Path $ProjectPath)) {
        $batchContent = "@echo off`r`nstart `"`" `"$EqExe`" `"$ProjectPath`""
    } else {
        $batchContent = "@echo off`r`nstart `"`" `"$EqExe`""
    }
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchEquest_GA"
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        # Cold-boot interactive sessions can hang eQUEST's first launch (the process
        # starts but its window never renders; working set stuck ~5MB). Launch, verify
        # it actually rendered (working set climbs past the hung baseline), and retry
        # (kill + relaunch) until it does. This is what makes a cold post_start boot
        # equivalent to a savevm checkpoint that pre-bakes a warmed, rendered eQUEST.
        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            # eQUEST corrupts its registration on every run; restore before each launch.
            Restore-EqRegistration
            # Clear any prior (possibly hung) eQUEST before (re)launching.
            Get-Process | Where-Object { $_.ProcessName -like "*quest*" } | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2

            $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
            schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN $taskName 2>$null
            schtasks /Delete /TN $taskName /F 2>$null

            # Poll for eQUEST to render.
            $waited = 0
            while ($waited -lt $WaitSeconds) {
                Start-Sleep -Seconds 3
                $waited += 3
                if (Test-EqRendered) { break }
            }
            if (Test-EqRendered) {
                Write-Host "eQUEST rendered on attempt $attempt."
                return
            }
            Write-Host "eQUEST did not render on attempt $attempt (cold-boot hang); retrying..."
        }
        Write-Host "WARNING: eQUEST failed to render after $MaxAttempts attempts."
    } finally {
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }
}

function Invoke-PyAutoGUICommand {
    <#
    Send a single command to the PyAutoGUI TCP server (guest:127.0.0.1:5555).
    Executes inside the interactive desktop session where GUI automation works.
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

function Dismiss-EqDialogsBestEffort {
    <#
    Best-effort dismissal of eQUEST startup dialogs using PyAutoGUI server.
    Handles: Registration prompt, Startup Options dialog, OneDrive popup.
    Coordinates are in the PyAutoGUI screen space (1280x720).

    eQUEST startup dialog layout (1280x720):
      - "Select an Existing Project to Open" radio: (442, 331)
      - "OK" button: (629, 422)
      - "Exit" button: (821, 422)
      - Close X: (847, 234)
    OneDrive "No thanks": (1167, 626)
    #>
    param(
        [int] $Retries = 3,
        [int] $InitialWaitSeconds = 5,
        [int] $BetweenRetriesSeconds = 2
    )

    if ($InitialWaitSeconds -gt 0) {
        Start-Sleep -Seconds $InitialWaitSeconds
    }

    for ($i = 0; $i -lt $Retries; $i++) {
        # Dismiss OneDrive "No thanks" button
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 1167; y = 626} | Out-Null } catch { }
        Start-Sleep -Milliseconds 300

        # Close eQUEST Startup Options dialog via X button
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 847; y = 234} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        # Press Escape to dismiss any remaining modals
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        if ($BetweenRetriesSeconds -gt 0) {
            Start-Sleep -Seconds $BetweenRetriesSeconds
        }
    }
}

function Wait-ForEqWindow {
    <#
    Wait for an eQUEST window to appear.
    Returns $true if found within timeout, $false otherwise.
    #>
    param(
        [int] $TimeoutSeconds = 30,
        [int] $PollIntervalSeconds = 2
    )

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $proc = Get-Process | Where-Object { $_.ProcessName -like "*quest*" -and $_.MainWindowTitle -ne "" } | Select-Object -First 1
        if ($proc) {
            Write-Host "eQUEST window found: $($proc.MainWindowTitle)"
            return $true
        }
        Start-Sleep -Seconds $PollIntervalSeconds
        $elapsed += $PollIntervalSeconds
    }
    Write-Host "WARNING: eQUEST window not found within $TimeoutSeconds seconds."
    return $false
}
