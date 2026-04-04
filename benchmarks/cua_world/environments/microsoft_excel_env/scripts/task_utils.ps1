# Shared PowerShell helpers for Microsoft Excel tasks.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-ExcelExe {
    $candidates = @(
        "C:\\Program Files\\Microsoft Office\\root\\Office16\\EXCEL.EXE",
        "C:\\Program Files (x86)\\Microsoft Office\\root\\Office16\\EXCEL.EXE",
        "C:\\Program Files\\Microsoft Office\\Office16\\EXCEL.EXE",
        "C:\\Program Files (x86)\\Microsoft Office\\Office16\\EXCEL.EXE"
    )

    foreach ($p in $candidates) {
        if (Test-Path $p) {
            return $p
        }
    }

    $searchRoots = @(
        "C:\\Program Files\\Microsoft Office",
        "C:\\Program Files (x86)\\Microsoft Office"
    )

    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) {
            continue
        }
        $found = Get-ChildItem $root -Recurse -Filter "EXCEL.EXE" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }

    throw "Could not find EXCEL.EXE in standard Office locations."
}

function Launch-ExcelWorkbookInteractive {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ExcelExe,
        [Parameter(Mandatory = $true)]
        [string] $WorkbookPath,
        [int] $WaitSeconds = 12
    )

    if (-not (Test-Path $ExcelExe)) {
        throw "Excel executable not found at: $ExcelExe"
    }
    if (-not (Test-Path $WorkbookPath)) {
        throw "Workbook not found at: $WorkbookPath"
    }

    # Create a launcher batch file so schtasks doesn't have to deal with quoting
    # paths containing spaces (e.g., Program Files).
    $launchScript = "C:\\Windows\\Temp\\launch_excel.cmd"
    $batchContent = "@echo off`r`nstart `"`" `"$ExcelExe`" `"$WorkbookPath`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchExcel_GA"
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")

    # schtasks writes informational output to stderr which triggers
    # terminating errors under $ErrorActionPreference = "Stop".
    # Temporarily relax error handling for native commands.
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        # Run Excel in the interactive desktop session. SSH runs in Session 0
        # and cannot directly show GUI windows.
        schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
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
    Send a single command to the PyAutoGUI TCP server (guest:127.0.0.1:5555).

    This is useful from SSH/session-0 hooks because it executes inside the
    interactive desktop session where GUI automation works.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Command,
        [string] $Host = "127.0.0.1",
        [int] $Port = 5555,
        [int] $ConnectTimeoutMs = 3000
    )

    $json = $Command | ConvertTo-Json -Compress
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($Host, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($ConnectTimeoutMs, $false)) {
            throw "PyAutoGUI server connect timeout to ${Host}:${Port}"
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

function Dismiss-ExcelDialogsBestEffort {
    <#
    Best-effort dismissal of Excel/OneDrive popups using the PyAutoGUI server.
    Coordinates are in the PyAutoGUI screen space (1280x720 in this env).
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
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 1166; y = 627} | Out-Null } catch { }
        Start-Sleep -Milliseconds 250
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 1236; y = 393} | Out-Null } catch { }
        Start-Sleep -Milliseconds 250

        # Trial nag + sign-in overlays.
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 1042; y = 72} | Out-Null } catch { }
        Start-Sleep -Milliseconds 250
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 1040; y = 75} | Out-Null } catch { }
        Start-Sleep -Milliseconds 250
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 234; y = 624} | Out-Null } catch { }

        # A few escapes for any remaining modals.
        Start-Sleep -Milliseconds 250
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 250
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 250
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }

        # Ensure worksheet has focus.
        Start-Sleep -Milliseconds 350
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 150; y = 300} | Out-Null } catch { }

        if ($BetweenRetriesSeconds -gt 0) {
            Start-Sleep -Seconds $BetweenRetriesSeconds
        }
    }
}
