# Shared PowerShell helpers for Microsoft Excel 2010 tasks.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-ExcelExe {
    <#
    Search standard Office installation paths for EXCEL.EXE.
    Office 2010 installs to Office14 under Program Files (x86) on 64-bit Windows.
    #>
    $candidates = @(
        "C:\Program Files (x86)\Microsoft Office\Office14\EXCEL.EXE",
        "C:\Program Files\Microsoft Office\Office14\EXCEL.EXE",
        "C:\Program Files (x86)\Microsoft Office\root\Office14\EXCEL.EXE",
        "C:\Program Files\Microsoft Office\root\Office14\EXCEL.EXE"
    )

    foreach ($p in $candidates) {
        if (Test-Path $p) {
            return $p
        }
    }

    # Search more broadly
    $searchRoots = @(
        "C:\Program Files (x86)\Microsoft Office",
        "C:\Program Files\Microsoft Office"
    )

    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) { continue }
        $found = Get-ChildItem $root -Recurse -Filter "EXCEL.EXE" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    throw "Could not find EXCEL.EXE in standard Office locations."
}

function Test-ExcelRendered {
    # True once Excel has a real window. A hung/early launch has no main window
    # handle; a rendered Excel has a window handle (survives idle working-set trim).
    $procs = Get-Process EXCEL -ErrorAction SilentlyContinue
    if (-not $procs) { return $false }
    foreach ($p in @($procs)) {
        if ($p.MainWindowHandle -ne 0 -or $p.WorkingSet64 -gt 25MB) { return $true }
    }
    return $false
}

function Launch-ExcelDocumentInteractive {
    <#
    Launch Excel with a workbook in the interactive desktop session via schtasks /IT
    (Session 1). Retries until Excel actually renders, to survive cold-boot launch hangs.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string] $ExcelExe,
        [string] $DocumentPath = "",
        [int] $WaitSeconds = 25,
        [int] $MaxAttempts = 4
    )

    if (-not (Test-Path $ExcelExe)) {
        throw "Excel executable not found at: $ExcelExe"
    }

    $launchScript = "C:\Windows\Temp\launch_excel.cmd"
    if ($DocumentPath -and (Test-Path $DocumentPath)) {
        $batchContent = "@echo off`r`nstart `"`" `"$ExcelExe`" `"$DocumentPath`""
    } else {
        $batchContent = "@echo off`r`nstart `"`" `"$ExcelExe`""
    }
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchExcel_GA"
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        # Cold-boot interactive sessions can hang the first GUI launch. Launch, verify
        # Excel actually rendered a window, and retry (kill + relaunch) until it does.
        # Replaces the savevm checkpoint that pre-baked a warmed, rendered Excel.
        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            Get-Process EXCEL -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
            schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN $taskName 2>$null
            schtasks /Delete /TN $taskName /F 2>$null
            $waited = 0
            while ($waited -lt $WaitSeconds) {
                Start-Sleep -Seconds 3
                $waited += 3
                if (Test-ExcelRendered) { break }
            }
            if (Test-ExcelRendered) {
                Write-Host "Excel rendered on attempt $attempt."
                return
            }
            Write-Host "Excel did not render on attempt $attempt (cold-boot hang); retrying..."
        }
        Write-Host "WARNING: Excel failed to render after $MaxAttempts attempts."
    } finally {
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }
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

function Dismiss-ExcelDialogsBestEffort {
    <#
    Best-effort dismissal of Excel 2010 startup dialogs via PyAutoGUI.
    Coordinates are in PyAutoGUI screen space (1280x720 for this env).
    #>
    param(
        [int] $Retries = 4,
        [int] $InitialWaitSeconds = 3,
        [int] $BetweenRetriesSeconds = 2
    )

    if ($InitialWaitSeconds -gt 0) {
        Start-Sleep -Seconds $InitialWaitSeconds
    }

    for ($i = 0; $i -lt $Retries; $i++) {
        # Escape to dismiss modal dialogs
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        # Close Document Recovery panel if present (Close button at ~216, 628)
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 216; y = 628} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        # Click on spreadsheet area to ensure Excel has focus
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 400; y = 350} | Out-Null } catch { }
        Start-Sleep -Milliseconds 300

        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }

        if ($BetweenRetriesSeconds -gt 0) {
            Start-Sleep -Seconds $BetweenRetriesSeconds
        }
    }
}
