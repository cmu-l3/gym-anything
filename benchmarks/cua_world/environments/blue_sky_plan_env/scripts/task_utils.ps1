# Shared PowerShell helpers for Blue Sky Plan tasks.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-BlueSkyPlanExe {
    <#
    .SYNOPSIS
        Finds the Blue Sky Plan Launcher executable on the system.
        BSP must be launched via BlueSkyLauncher.exe (not BlueSkyPlan.exe directly).
    .OUTPUTS
        String path to BlueSkyLauncher executable.
    #>
    # The launcher is the correct entry point - it starts nats-server + BlueSkyPlan
    $candidates = @(
        "C:\Program Files\BlueSkyPlan\Launcher\BlueSkyLauncher.exe",
        "C:\Program Files (x86)\BlueSkyPlan\Launcher\BlueSkyLauncher.exe",
        "C:\Program Files\Blue Sky Plan 5\Launcher\BlueSkyLauncher.exe"
    )

    foreach ($p in $candidates) {
        if (Test-Path $p) {
            return $p
        }
    }

    # Broader search for the launcher
    $searchRoots = @("C:\Program Files", "C:\Program Files (x86)")
    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) { continue }
        $found = Get-ChildItem $root -Recurse -Filter "BlueSkyLauncher.exe" -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }

    # Check Desktop/Public Desktop shortcuts
    $shortcutDirs = @("C:\Users\Docker\Desktop", "C:\Users\Public\Desktop")
    foreach ($dir in $shortcutDirs) {
        $shortcuts = Get-ChildItem $dir -Filter "*Blue*Sky*.lnk" -ErrorAction SilentlyContinue
        foreach ($lnk in $shortcuts) {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($lnk.FullName)
            if ($shortcut.TargetPath -like "*BlueSky*" -and (Test-Path $shortcut.TargetPath)) {
                return $shortcut.TargetPath
            }
        }
    }

    throw "Could not find Blue Sky Plan Launcher in standard locations."
}

function Setup-MesaOpenGL {
    <#
    .SYNOPSIS
        Copies Mesa software OpenGL renderer (opengl32sw.dll -> opengl32.dll) into BSP directories.
        Required because QEMU's virtio-vga only provides OpenGL ~3.x, but BSP needs 4.3+.
        The installer only ships opengl32sw.dll in Launcher/ — must also copy to BlueSkyPlan4/.
    #>
    # Source: the installer puts opengl32sw.dll in the Launcher directory
    $sourceDll = "C:\Program Files\BlueSkyPlan\Launcher\opengl32sw.dll"

    $bspDirs = @(
        "C:\Program Files\BlueSkyPlan\Launcher",
        "C:\Program Files\BlueSkyPlan\BlueSkyPlan4"
    )
    foreach ($dir in $bspDirs) {
        if (-not (Test-Path $dir)) { continue }
        $targetDll = "$dir\opengl32.dll"
        if (-not (Test-Path $targetDll)) {
            # Try local opengl32sw.dll first, then fall back to Launcher's copy
            $localSw = "$dir\opengl32sw.dll"
            if (Test-Path $localSw) {
                Copy-Item $localSw $targetDll -Force
            } elseif (Test-Path $sourceDll) {
                Copy-Item $sourceDll $targetDll -Force
            }
            if (Test-Path $targetDll) {
                Write-Host "Copied Mesa opengl32sw.dll -> opengl32.dll in $dir"
            }
        }
    }
    # Set environment variables for Mesa/Qt
    [System.Environment]::SetEnvironmentVariable("QT_OPENGL", "software", "Machine")
    [System.Environment]::SetEnvironmentVariable("MESA_GL_VERSION_OVERRIDE", "4.5", "Machine")
}

function Launch-BlueSkyPlanInteractive {
    <#
    .SYNOPSIS
        Launches Blue Sky Plan in the interactive desktop session via schtasks.
    .PARAMETER BSPExe
        Full path to BlueSkyPlan executable.
    .PARAMETER WaitSeconds
        Seconds to wait for Blue Sky Plan to fully load (default 25).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$BSPExe,
        [int]$WaitSeconds = 25
    )

    if (-not (Test-Path $BSPExe)) {
        throw "Blue Sky Plan executable not found at: $BSPExe"
    }

    # Create a launcher batch file so schtasks doesn't have to deal with quoting
    # Must set QT_OPENGL and MESA env vars for software rendering in QEMU
    $launchScript = "C:\Windows\Temp\launch_bsp.cmd"
    $batchContent = "@echo off`r`nset QT_OPENGL=software`r`nset MESA_GL_VERSION_OVERRIDE=4.5`r`nstart `"`" `"$BSPExe`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchBSP_GA"
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

    Write-Host "Blue Sky Plan launched (waited ${WaitSeconds}s)."
}

function Launch-BlueSkyPlanWithFile {
    <#
    .SYNOPSIS
        Launches Blue Sky Plan with a specific file in the interactive desktop session.
    .PARAMETER BSPExe
        Full path to BlueSkyPlan executable.
    .PARAMETER FilePath
        Path to the file to open (DICOM directory or project file).
    .PARAMETER WaitSeconds
        Seconds to wait for loading (default 30).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$BSPExe,
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [int]$WaitSeconds = 30
    )

    if (-not (Test-Path $BSPExe)) {
        throw "Blue Sky Plan executable not found at: $BSPExe"
    }

    $launchScript = "C:\Windows\Temp\launch_bsp_file.cmd"
    $batchContent = "@echo off`r`nset QT_OPENGL=software`r`nset MESA_GL_VERSION_OVERRIDE=4.5`r`nstart `"`" `"$BSPExe`" `"$FilePath`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchBSPFile_GA"
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

    Write-Host "Blue Sky Plan launched with file (waited ${WaitSeconds}s)."
}

function Invoke-PyAutoGUICommand {
    <#
    .SYNOPSIS
        Send a single command to the PyAutoGUI TCP server (127.0.0.1:5555).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Command,
        [string]$HostAddr = "127.0.0.1",
        [int]$Port = 5555,
        [int]$ConnectTimeoutMs = 3000
    )

    $json = $Command | ConvertTo-Json -Compress
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($HostAddr, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($ConnectTimeoutMs, $false)) {
            throw "PyAutoGUI server connection timeout"
        }
        $client.EndConnect($iar)

        $stream = $client.GetStream()
        $stream.ReadTimeout = 10000
        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.AutoFlush = $true
        $writer.WriteLine($json)

        Start-Sleep -Milliseconds 300

        $buf = New-Object byte[] 65536
        $count = $stream.Read($buf, 0, $buf.Length)
        $resp = [System.Text.Encoding]::UTF8.GetString($buf, 0, $count)
        return ($resp | ConvertFrom-Json)
    } catch {
        Write-Host "PyAutoGUI command failed: $($_.Exception.Message)"
        return $null
    } finally {
        $client.Close()
    }
}

function PyAutoGUI-Click {
    param([int]$X, [int]$Y, [string]$Button = "left")
    $result = Invoke-PyAutoGUICommand -Command @{action="click"; x=$X; y=$Y; button=$Button}
    Start-Sleep -Milliseconds 300
    return $result
}

function PyAutoGUI-DoubleClick {
    param([int]$X, [int]$Y)
    $result = Invoke-PyAutoGUICommand -Command @{action="doubleClick"; x=$X; y=$Y}
    Start-Sleep -Milliseconds 300
    return $result
}

function PyAutoGUI-Write {
    param([string]$Text, [double]$Interval = 0.02)
    $result = Invoke-PyAutoGUICommand -Command @{action="write"; text=$Text; interval=$Interval}
    Start-Sleep -Milliseconds 300
    return $result
}

function PyAutoGUI-Press {
    param([string]$Key)
    $result = Invoke-PyAutoGUICommand -Command @{action="press"; key=$Key}
    Start-Sleep -Milliseconds 300
    return $result
}

function PyAutoGUI-Hotkey {
    param([string[]]$Keys)
    $result = Invoke-PyAutoGUICommand -Command @{action="hotkey"; keys=$Keys}
    Start-Sleep -Milliseconds 300
    return $result
}

function PyAutoGUI-Screenshot {
    $result = Invoke-PyAutoGUICommand -Command @{action="screenshot"}
    return $result
}

function Wait-ForBlueSkyPlanWindow {
    <#
    .SYNOPSIS
        Waits for the Blue Sky Plan window to appear by checking running processes.
    .PARAMETER TimeoutSeconds
        Maximum seconds to wait (default 60).
    #>
    param([int]$TimeoutSeconds = 60)

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $proc = Get-Process | Where-Object {
            $_.ProcessName -like "*BlueSky*" -or $_.ProcessName -like "*BSP*" -or $_.ProcessName -like "*Launcher*"
        } | Select-Object -First 1
        if ($proc -and $proc.MainWindowHandle -ne 0) {
            Write-Host "Blue Sky Plan window detected (PID: $($proc.Id))"
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    Write-Host "WARNING: Blue Sky Plan window not detected after ${TimeoutSeconds}s"
    return $false
}
