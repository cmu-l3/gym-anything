# Shared PowerShell helpers for Microsoft Word 2010 tasks.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-WordExe {
    <#
    Search standard Office installation paths for WINWORD.EXE.
    Office 2010 installs to Office14 under Program Files (x86) on 64-bit Windows.
    #>
    $candidates = @(
        "C:\Program Files (x86)\Microsoft Office\Office14\WINWORD.EXE",
        "C:\Program Files\Microsoft Office\Office14\WINWORD.EXE",
        "C:\Program Files (x86)\Microsoft Office\root\Office14\WINWORD.EXE",
        "C:\Program Files\Microsoft Office\root\Office14\WINWORD.EXE"
    )

    foreach ($p in $candidates) {
        if (Test-Path $p) {
            return $p
        }
    }

    # Search more broadly in standard Office directories
    $searchRoots = @(
        "C:\Program Files (x86)\Microsoft Office",
        "C:\Program Files\Microsoft Office"
    )

    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) {
            continue
        }
        $found = Get-ChildItem $root -Recurse -Filter "WINWORD.EXE" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }

    throw "Could not find WINWORD.EXE in standard Office locations."
}

function Launch-WordDocumentInteractive {
    <#
    Launch Word with a document in the interactive desktop session.
    SSH runs in Session 0 which cannot display GUI windows, so we use
    schtasks with /IT to run in the interactive session.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string] $WordExe,
        [string] $DocumentPath = "",
        [int] $WaitSeconds = 12
    )

    if (-not (Test-Path $WordExe)) {
        throw "Word executable not found at: $WordExe"
    }

    # Create a launcher batch file so schtasks doesn't have to deal with
    # quoting paths containing spaces (e.g., Program Files (x86)).
    $launchScript = "C:\Windows\Temp\launch_word.cmd"
    if ($DocumentPath -and (Test-Path $DocumentPath)) {
        $batchContent = "@echo off`r`nstart `"`" `"$WordExe`" `"$DocumentPath`""
    } else {
        $batchContent = "@echo off`r`nstart `"`" `"$WordExe`""
    }
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchWord_GA"
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

function Invoke-PyAutoGUICommand {
    <#
    Send a single command to the PyAutoGUI TCP server (guest:127.0.0.1:5555).
    This executes inside the interactive desktop session where GUI automation works.
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

function Dismiss-WordDialogsBestEffort {
    <#
    Best-effort dismissal of Word 2010 startup dialogs via PyAutoGUI.
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
        # Dismiss "Help Protect and Improve Microsoft Office" first-run dialog
        # Click "Don't make changes" radio at (336, 412), then OK at (971, 521)
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 336; y = 412} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 971; y = 521} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        # Send Escape key to dismiss any modal dialogs
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        # Send another Escape
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        # Close Document Recovery panel if present (Close button at ~216, 628)
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 216; y = 628} | Out-Null } catch { }
        Start-Sleep -Milliseconds 500

        # Click on the document area to ensure Word has focus
        # (approximate center of document area at 1280x720)
        try { Invoke-PyAutoGUICommand -Command @{action = "click"; x = 640; y = 400} | Out-Null } catch { }
        Start-Sleep -Milliseconds 300

        # Another Escape for any remaining modals
        try { Invoke-PyAutoGUICommand -Command @{action = "press"; keys = "esc"} | Out-Null } catch { }

        if ($BetweenRetriesSeconds -gt 0) {
            Start-Sleep -Seconds $BetweenRetriesSeconds
        }
    }
}
