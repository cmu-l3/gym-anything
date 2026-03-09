# task_utils.ps1 - Shared helper functions for NinjaTrader 8 task setup scripts.

# =====================================================================
# PyAutoGUI TCP Communication
# =====================================================================
# The PyAutoGUI server runs in the interactive desktop session on port 5555.
# These functions communicate with it over TCP from SSH (Session 0).
# This approach is required because Win32 API clicks via schtasks do NOT
# work for NinjaTrader (unlike Power BI Desktop).

function Send-PyAutoGUI {
    <#
    .SYNOPSIS
        Sends a command to the PyAutoGUI TCP server on localhost:5555.
    .PARAMETER Command
        Hashtable representing the JSON command (e.g. @{action="click"; x=100; y=200}).
    .PARAMETER Port
        PyAutoGUI server port (default 5555).
    .PARAMETER TimeoutMs
        Read timeout in milliseconds (default 5000).
    .OUTPUTS
        Hashtable with the parsed JSON response.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Command,
        [int]$Port = 5555,
        [int]$TimeoutMs = 5000
    )

    $tcp = $null
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect("localhost", $Port)
        $stream = $tcp.GetStream()
        $stream.ReadTimeout = $TimeoutMs
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true

        # Convert hashtable to JSON
        $json = $Command | ConvertTo-Json -Compress
        $writer.WriteLine($json)

        Start-Sleep -Milliseconds 300

        $buf = New-Object byte[] 65536
        $count = $stream.Read($buf, 0, $buf.Length)
        $resp = [System.Text.Encoding]::UTF8.GetString($buf, 0, $count)
        return ($resp | ConvertFrom-Json)
    } catch {
        Write-Host "PyAutoGUI send failed: $($_.Exception.Message)"
        return $null
    } finally {
        if ($tcp) { $tcp.Close() }
    }
}

function PyAutoGUI-Click {
    <#
    .SYNOPSIS
        Clicks at the given screen coordinates via PyAutoGUI server.
    #>
    param([int]$X, [int]$Y)
    $result = Send-PyAutoGUI -Command @{action="click"; x=$X; y=$Y}
    if ($result -and $result.success) {
        Write-Host "Clicked ($X, $Y)"
    } else {
        Write-Host "Click ($X, $Y) may have failed"
    }
    Start-Sleep -Milliseconds 300
}

function PyAutoGUI-Press {
    <#
    .SYNOPSIS
        Presses a key via PyAutoGUI server.
    #>
    param([string]$Key)
    $result = Send-PyAutoGUI -Command @{action="press"; key=$Key}
    if ($result -and $result.success) {
        Write-Host "Pressed: $Key"
    }
    Start-Sleep -Milliseconds 300
}

function PyAutoGUI-Hotkey {
    <#
    .SYNOPSIS
        Sends a hotkey combination via PyAutoGUI server.
    #>
    param([string[]]$Keys)
    $result = Send-PyAutoGUI -Command @{action="hotkey"; keys=$Keys}
    if ($result -and $result.success) {
        Write-Host "Hotkey: $($Keys -join '+')"
    }
    Start-Sleep -Milliseconds 300
}

function PyAutoGUI-Write {
    <#
    .SYNOPSIS
        Types text via PyAutoGUI server.
    #>
    param([string]$Text, [double]$Interval = 0.02)
    $result = Send-PyAutoGUI -Command @{action="write"; text=$Text; interval=$Interval}
    if ($result -and $result.success) {
        Write-Host "Typed: $Text"
    }
    Start-Sleep -Milliseconds 300
}

# =====================================================================
# NinjaTrader Executable Discovery
# =====================================================================

function Find-NTExe {
    <#
    .SYNOPSIS
        Finds the NinjaTrader 8 executable on the system.
        Prefers 64-bit (bin64) over 32-bit (bin).
    .OUTPUTS
        String path to NinjaTrader.exe
    #>
    $searchPaths = @(
        "C:\Program Files (x86)\NinjaTrader 8\bin64\NinjaTrader.exe",
        "C:\Program Files (x86)\NinjaTrader 8\bin\NinjaTrader.exe",
        "C:\Program Files\NinjaTrader 8\bin64\NinjaTrader.exe",
        "C:\Program Files\NinjaTrader 8\bin\NinjaTrader.exe"
    )

    foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            return $p
        }
    }

    # Broader search
    $found = Get-ChildItem "C:\Program Files (x86)" -Recurse -Filter "NinjaTrader.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) {
        $found = Get-ChildItem "C:\Program Files" -Recurse -Filter "NinjaTrader.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($found) {
        return $found.FullName
    }

    throw "NinjaTrader executable not found. Is it installed?"
}

# =====================================================================
# NinjaTrader Interactive Launch
# =====================================================================

function Launch-NTInteractive {
    <#
    .SYNOPSIS
        Launches NinjaTrader 8 in the interactive desktop session via schtasks.
    .PARAMETER NTExe
        Full path to NinjaTrader.exe.
    .PARAMETER WaitSeconds
        Seconds to wait for NinjaTrader to fully load (default 15).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$NTExe,
        [int]$WaitSeconds = 15
    )

    $launchScript = "C:\Windows\Temp\launch_ninjatrader.cmd"
    $batchContent = "@echo off`r`nstart `"`" `"$NTExe`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchNT_GA"
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $launchScript -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }

    Write-Host "NinjaTrader launched (waited ${WaitSeconds}s)."
}
