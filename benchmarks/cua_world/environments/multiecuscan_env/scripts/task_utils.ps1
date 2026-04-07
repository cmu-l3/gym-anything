# task_utils.ps1 - Shared utilities for Multiecuscan tasks
# Source this file at the beginning of every task script:
#   . C:\workspace\scripts\task_utils.ps1

function Find-MultiecuscanExe {
    <#
    .SYNOPSIS
        Searches well-known paths for Multiecuscan.exe
    .OUTPUTS
        Full path to Multiecuscan.exe or $null
    #>
    $knownPaths = @(
        "C:\Program Files\Multiecuscan\Multiecuscan.exe",
        "C:\Program Files (x86)\Multiecuscan\Multiecuscan.exe",
        "C:\Program Files\FESSoft\Multiecuscan\Multiecuscan.exe",
        "C:\Program Files (x86)\FESSoft\Multiecuscan\Multiecuscan.exe"
    )

    foreach ($p in $knownPaths) {
        if (Test-Path $p) { return $p }
    }

    # Check saved path from setup
    $savedPath = "C:\Users\Docker\Desktop\MultiecuscanTasks\.mes_exe_path"
    if (Test-Path $savedPath) {
        $sp = (Get-Content $savedPath -Raw).Trim()
        if (Test-Path $sp) { return $sp }
    }

    # Recursive search as last resort
    $found = Get-ChildItem -Path "C:\Program Files", "C:\Program Files (x86)" -Recurse -Filter "Multiecuscan.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }

    return $null
}

# =====================================================================
# PyAutoGUI TCP Communication (for Session 1 GUI automation)
# =====================================================================

function Send-PyAutoGUI {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Command,
        [int]$Port = 5555,
        [int]$TimeoutMs = 10000
    )
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect("127.0.0.1", $Port)
        $stream = $client.GetStream()
        $stream.ReadTimeout = $TimeoutMs
        $json = ($Command | ConvertTo-Json -Compress) + "`n"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        $buffer = New-Object byte[] 4096
        $read = $stream.Read($buffer, 0, $buffer.Length)
        $response = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
        $stream.Close()
        $client.Close()
        return $response
    } catch {
        return $null
    }
}

function PyAutoGUI-Press {
    param([string]$Key)
    Send-PyAutoGUI -Command @{action="press"; key=$Key} | Out-Null
    Start-Sleep -Milliseconds 200
}

function PyAutoGUI-Hotkey {
    param([string[]]$Keys)
    Send-PyAutoGUI -Command @{action="hotkey"; keys=$Keys} | Out-Null
    Start-Sleep -Milliseconds 200
}

function PyAutoGUI-Write {
    param([string]$Text, [double]$Interval = 0.02)
    Send-PyAutoGUI -Command @{action="write"; text=$Text; interval=$Interval} | Out-Null
    Start-Sleep -Milliseconds 300
}

function Launch-MultiecuscanInteractive {
    <#
    .SYNOPSIS
        Launches Multiecuscan in the interactive Windows desktop session.
        Uses PowerShell Start-Process via schtasks /IT to work around
        Session 0 isolation (SSH runs in Session 0, GUI needs Session 1).
    .PARAMETER MesExe
        Full path to Multiecuscan.exe
    .PARAMETER WaitSeconds
        Seconds to wait after launch before returning (default: 25)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$MesExe,
        [int]$WaitSeconds = 25
    )

    # Use C:\Temp (fixed path accessible from both Session 0 and Session 1)
    $tempDir = "C:\Temp"
    New-Item -ItemType Directory -Path $tempDir -Force -ErrorAction SilentlyContinue | Out-Null

    $logFile = "$tempDir\mes_launch.log"
    "$(Get-Date) - Launch-MultiecuscanInteractive starting for: $MesExe" | Out-File $logFile -Append

    # Ensure Task Scheduler service is running
    try {
        $svc = Get-Service -Name "Schedule" -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne "Running") {
            Write-Host "Starting Task Scheduler service..."
            Start-Service -Name "Schedule" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }
    } catch { }

    # ── Strategy 0: PyAutoGUI Win+R (most reliable, runs in Session 1) ────
    Write-Host "Attempt 0: Win+R via PyAutoGUI..."
    $pyguiOk = Send-PyAutoGUI -Command @{action="ping"}
    if ($pyguiOk) {
        $launchBat = "$tempDir\launchmes.cmd"
        [System.IO.File]::WriteAllText($launchBat, "@echo off`r`nstart `"`" `"$MesExe`"")

        PyAutoGUI-Press -Key "escape"
        Start-Sleep -Seconds 1
        PyAutoGUI-Hotkey -Keys @("win", "r")
        Start-Sleep -Seconds 2
        PyAutoGUI-Write -Text $launchBat
        Start-Sleep -Seconds 1
        PyAutoGUI-Press -Key "enter"

        # Poll for process
        $elapsed = 0
        $running = $null
        while ($elapsed -lt $WaitSeconds) {
            Start-Sleep -Seconds 2
            $elapsed += 2
            $running = Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" }
            if ($running) {
                Write-Host "Multiecuscan detected via Win+R after ${elapsed}s (PID: $($running.Id -join ', '))"
                "$(Get-Date) - Win+R launch succeeded (PID: $($running.Id -join ', '))" | Out-File $logFile -Append
                return $true
            }
        }
        Write-Host "  Win+R attempt: process not detected."
        "$(Get-Date) - Win+R attempt failed" | Out-File $logFile -Append
    } else {
        Write-Host "  PyAutoGUI not available, skipping Win+R."
    }

    # ── Strategy 0b: schtasks with simple CMD batch (fewer moving parts) ──
    Write-Host "Attempt 0b: schtasks CMD batch..."
    $launchBat2 = "$tempDir\launchmes_cmd.cmd"
    [System.IO.File]::WriteAllText($launchBat2, "@echo off`r`nstart `"`" `"$MesExe`"")
    $taskNameCmd = "LaunchMES_cmd_$(Get-Random)"
    $prevEAP2 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN $taskNameCmd /TR "cmd /c `"$launchBat2`"" /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>&1 | Out-Null
    schtasks /Run /TN $taskNameCmd 2>&1 | Out-Null
    $ErrorActionPreference = $prevEAP2

    $elapsed = 0
    $running = $null
    while ($elapsed -lt $WaitSeconds) {
        Start-Sleep -Seconds 2
        $elapsed += 2
        $running = Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" }
        if ($running) {
            Write-Host "Multiecuscan detected via CMD batch after ${elapsed}s (PID: $($running.Id -join ', '))"
            "$(Get-Date) - CMD batch launch succeeded (PID: $($running.Id -join ', '))" | Out-File $logFile -Append
            schtasks /Delete /TN $taskNameCmd /F 2>$null
            Remove-Item $launchBat2 -Force -ErrorAction SilentlyContinue
            return $true
        }
    }
    schtasks /Delete /TN $taskNameCmd /F 2>$null
    Remove-Item $launchBat2 -Force -ErrorAction SilentlyContinue
    Write-Host "  CMD batch attempt: process not detected."
    "$(Get-Date) - CMD batch attempt failed" | Out-File $logFile -Append

    # Create a PowerShell launch script that runs in the interactive session.
    # This uses the same proven pattern as dismiss_dialogs (CMD -> PowerShell),
    # which is known to work reliably via schtasks /IT.
    $ps1File = "$tempDir\launch_mes.ps1"
    $ps1Content = @"
`$logFile = "$logFile"
try {
    "`$(Get-Date) - PS1: Starting Multiecuscan from interactive session" | Out-File `$logFile -Append
    Start-Process -FilePath "$MesExe"
    Start-Sleep -Seconds 3
    `$proc = Get-Process | Where-Object { `$_.ProcessName -match "Multiecuscan" -or `$_.ProcessName -match "b-mes" }
    if (`$proc) {
        "`$(Get-Date) - PS1: Multiecuscan running (PID: `$(`$proc.Id -join ', '))" | Out-File `$logFile -Append
    } else {
        "`$(Get-Date) - PS1: Multiecuscan NOT detected after Start-Process" | Out-File `$logFile -Append
    }
} catch {
    "`$(Get-Date) - PS1 ERROR: `$(`$_.Exception.Message)" | Out-File `$logFile -Append
}
"@
    Set-Content -Path $ps1File -Value $ps1Content

    Write-Host "Launch script written to $ps1File"
    "$(Get-Date) - Created PS1=$ps1File" | Out-File $logFile -Append

    # Launch via schtasks with HIDDEN window to avoid visible CMD/PS terminals
    $taskName = "LaunchMES_$(Get-Random)"
    $trCmd = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$ps1File`""
    $createOut = schtasks /Create /SC ONCE /IT /TR "$trCmd" /TN $taskName /SD 01/01/2099 /ST 00:00 /RL HIGHEST /F 2>&1
    Write-Host "schtasks /Create: $createOut"
    "$(Get-Date) - schtasks /Create: $createOut" | Out-File $logFile -Append

    $runOut = schtasks /Run /TN $taskName 2>&1
    Write-Host "schtasks /Run: $runOut"
    "$(Get-Date) - schtasks /Run: $runOut" | Out-File $logFile -Append

    # Poll for process with timeout
    Write-Host "Waiting up to $WaitSeconds seconds for Multiecuscan to start..."
    $elapsed = 0
    $running = $null
    while ($elapsed -lt $WaitSeconds) {
        Start-Sleep -Seconds 2
        $elapsed += 2
        $running = Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" }
        if ($running) {
            Write-Host "Multiecuscan detected after ${elapsed}s (PID: $($running.Id -join ', '))"
            "$(Get-Date) - Detected after ${elapsed}s (PID: $($running.Id -join ', '))" | Out-File $logFile -Append
            break
        }
    }

    # Clean up scheduled task (but NOT the log file)
    schtasks /Delete /TN $taskName /F 2>&1 | Out-Null
    Remove-Item $ps1File -Force -ErrorAction SilentlyContinue

    if ($running) {
        return $true
    }

    # Retry: launch PowerShell directly via schtasks (no CMD wrapper)
    Write-Host "First launch attempt failed. Retrying..."
    "$(Get-Date) - First attempt failed, retrying with direct PowerShell" | Out-File $logFile -Append

    $ps1File2 = "$tempDir\launch_mes_retry.ps1"
    Set-Content -Path $ps1File2 -Value "Start-Process -FilePath `"$MesExe`" -ErrorAction Stop"

    $taskName2 = "LaunchMES_retry_$(Get-Random)"
    $createOut2 = schtasks /Create /SC ONCE /IT /TR "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$ps1File2`"" /TN $taskName2 /SD 01/01/2099 /ST 00:00 /RL HIGHEST /F 2>&1
    Write-Host "schtasks /Create (retry): $createOut2"
    "$(Get-Date) - Retry schtasks /Create: $createOut2" | Out-File $logFile -Append

    $runOut2 = schtasks /Run /TN $taskName2 2>&1
    Write-Host "schtasks /Run (retry): $runOut2"
    "$(Get-Date) - Retry schtasks /Run: $runOut2" | Out-File $logFile -Append

    Start-Sleep -Seconds 15
    schtasks /Delete /TN $taskName2 /F 2>&1 | Out-Null
    Remove-Item $ps1File2 -Force -ErrorAction SilentlyContinue

    $running = Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" }
    if ($running) {
        Write-Host "Multiecuscan is running after retry (PID: $($running.Id -join ', '))"
        "$(Get-Date) - Retry succeeded (PID: $($running.Id -join ', '))" | Out-File $logFile -Append
        return $true
    }

    # Last resort: try double-click via explorer
    Write-Host "Retry failed. Trying explorer launch..."
    "$(Get-Date) - Retry failed, trying explorer" | Out-File $logFile -Append
    $taskName3 = "LaunchMES_explorer_$(Get-Random)"
    schtasks /Create /SC ONCE /IT /TR "explorer `"$MesExe`"" /TN $taskName3 /SD 01/01/2099 /ST 00:00 /RL HIGHEST /F 2>&1 | Out-Null
    schtasks /Run /TN $taskName3 2>&1 | Out-Null
    Start-Sleep -Seconds 15
    schtasks /Delete /TN $taskName3 /F 2>&1 | Out-Null

    $running = Get-Process | Where-Object { $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes" }
    if ($running) {
        Write-Host "Multiecuscan is running via explorer (PID: $($running.Id -join ', '))"
        "$(Get-Date) - Explorer launch succeeded" | Out-File $logFile -Append
        return $true
    } else {
        Write-Host "WARNING: All launch attempts failed. Check $logFile on the VM."
        "$(Get-Date) - ALL LAUNCH ATTEMPTS FAILED" | Out-File $logFile -Append
        return $false
    }
}

function Stop-Multiecuscan {
    <#
    .SYNOPSIS
        Stops all Multiecuscan processes
    #>
    Get-Process | Where-Object {
        $_.ProcessName -match "Multiecuscan" -or $_.ProcessName -match "b-mes"
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Get-TaskStartTimestamp {
    <#
    .SYNOPSIS
        Returns the current epoch timestamp and saves it to a file
    .PARAMETER TaskName
        Name of the task (used for file naming)
    #>
    param([string]$TaskName)

    $timestamp = [int][double]::Parse((Get-Date -UFormat %s))
    $tsFile = "C:\Users\Docker\Desktop\MultiecuscanTasks\${TaskName}_start_timestamp.txt"
    Set-Content -Path $tsFile -Value $timestamp
    Write-Host "Task start timestamp: $timestamp"
    return $timestamp
}

function Run-DismissDialogs {
    <#
    .SYNOPSIS
        Runs dismiss_dialogs.ps1 in the interactive session via schtasks.
        Polls for completion marker file to synchronize (instead of blind sleep).
        Uses -WindowStyle Hidden to avoid creating visible terminal windows.
    .PARAMETER MaxWaitSeconds
        Maximum seconds to wait for dismiss to complete (default: 90)
    #>
    param([int]$MaxWaitSeconds = 90)

    $dismissScript = "C:\workspace\scripts\dismiss_dialogs.ps1"
    if (-not (Test-Path $dismissScript)) {
        Write-Host "WARNING: dismiss_dialogs.ps1 not found"
        return
    }

    $tempDir = "C:\Temp"
    New-Item -ItemType Directory -Path $tempDir -Force -ErrorAction SilentlyContinue | Out-Null

    # Delete old completion marker
    Remove-Item "$tempDir\dismiss_complete.txt" -Force -ErrorAction SilentlyContinue

    # Launch dismiss_dialogs.ps1 via schtasks with HIDDEN window (no visible CMD/PS terminal)
    $taskName = "DismissDialogs_$(Get-Random)"
    $trCmd = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$dismissScript`""
    $createOut = schtasks /Create /SC ONCE /IT /TR "$trCmd" /TN $taskName /SD 01/01/2099 /ST 00:00 /RL HIGHEST /F 2>&1
    Write-Host "DismissDialogs schtasks /Create: $createOut"
    $runOut = schtasks /Run /TN $taskName 2>&1
    Write-Host "DismissDialogs schtasks /Run: $runOut"

    # Poll for completion marker (dismiss_dialogs.ps1 writes C:\Temp\dismiss_complete.txt when done)
    Write-Host "Waiting for dismiss_dialogs.ps1 to complete (max ${MaxWaitSeconds}s)..."
    $elapsed = 0
    while ($elapsed -lt $MaxWaitSeconds) {
        Start-Sleep -Seconds 2
        $elapsed += 2
        if (Test-Path "$tempDir\dismiss_complete.txt") {
            $result = (Get-Content "$tempDir\dismiss_complete.txt" -Raw).Trim()
            Write-Host "dismiss_dialogs completed after ${elapsed}s: $result"
            break
        }
        if ($elapsed % 10 -eq 0) {
            Write-Host "  Still waiting for dismiss_dialogs... (${elapsed}s)"
        }
    }

    if (-not (Test-Path "$tempDir\dismiss_complete.txt")) {
        Write-Host "WARNING: dismiss_dialogs did not complete within ${MaxWaitSeconds}s"
    }

    schtasks /Delete /TN $taskName /F 2>&1 | Out-Null
}

function Kill-OneDriveAndNotifications {
    <#
    .SYNOPSIS
        Kills OneDrive and other notification processes from SSH session.
        Called before MES launch to prevent popups from appearing.
    #>
    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "OneDriveSetup" -Force -ErrorAction SilentlyContinue
    Stop-Process -Name "MicrosoftEdgeUpdate" -Force -ErrorAction SilentlyContinue
    Write-Host "Killed OneDrive and notification processes"
}

function Ensure-DataFile {
    <#
    .SYNOPSIS
        Ensures a data file exists on the Desktop from workspace mount
    .PARAMETER FileName
        Name of the file in C:\workspace\data\
    .PARAMETER DestDir
        Destination directory (default: MultiecuscanData)
    #>
    param(
        [string]$FileName,
        [string]$DestDir = "C:\Users\Docker\Desktop\MultiecuscanData"
    )

    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    $src = "C:\workspace\data\$FileName"
    $dst = "$DestDir\$FileName"
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        Write-Host "Data file ready: $dst"
        return $dst
    } else {
        Write-Host "WARNING: Data file not found: $src"
        return $null
    }
}
