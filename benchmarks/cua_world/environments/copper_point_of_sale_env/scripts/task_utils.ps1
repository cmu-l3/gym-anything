# task_utils.ps1 - Shared helper functions for Copper POS task setup scripts.
# Uses PyAutoGUI TCP server (port 5555) for GUI automation.
# Win32 API clicks from SSH Session 0 do NOT work for Copper POS.

# =====================================================================
# PyAutoGUI TCP Communication
# =====================================================================

# The PyAutoGUI server runs in the interactive desktop session on port 5555.
# It is started automatically by the gym_anything framework.

function Send-PyAutoGUI {
    <#
    .SYNOPSIS
        Sends a command to the PyAutoGUI TCP server on localhost:5555.
    .PARAMETER Command
        Hashtable command to send (converted to JSON).
    .PARAMETER Port
        PyAutoGUI server port (default 5555).
    #>
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
        Write-Host "PyAutoGUI send failed: $($_.Exception.Message)"
        return $null
    }
}

function PyAutoGUI-Click {
    <#
    .SYNOPSIS
        Clicks at the given screen coordinates via PyAutoGUI server.
    #>
    param([int]$X, [int]$Y)
    $result = Send-PyAutoGUI -Command @{action="click"; x=$X; y=$Y}
    Write-Host "PyAutoGUI clicked ($X, $Y)"
    Start-Sleep -Milliseconds 300
    return $result
}

function PyAutoGUI-Press {
    <#
    .SYNOPSIS
        Presses a key via PyAutoGUI server.
    #>
    param([string]$Key)
    $result = Send-PyAutoGUI -Command @{action="press"; key=$Key}
    Write-Host "PyAutoGUI pressed: $Key"
    Start-Sleep -Milliseconds 200
    return $result
}

function PyAutoGUI-Hotkey {
    <#
    .SYNOPSIS
        Sends a hotkey combination via PyAutoGUI server.
    #>
    param([string[]]$Keys)
    $result = Send-PyAutoGUI -Command @{action="hotkey"; keys=$Keys}
    Write-Host "PyAutoGUI hotkey: $($Keys -join '+')"
    Start-Sleep -Milliseconds 200
    return $result
}

function PyAutoGUI-Write {
    <#
    .SYNOPSIS
        Types text via PyAutoGUI server.
    #>
    param(
        [string]$Text,
        [double]$Interval = 0.02
    )
    $result = Send-PyAutoGUI -Command @{action="write"; text=$Text; interval=$Interval}
    Write-Host "PyAutoGUI typed: $Text"
    Start-Sleep -Milliseconds 300
    return $result
}

# =====================================================================
# Copper POS Executable Discovery
# =====================================================================

function Find-CopperExe {
    <#
    .SYNOPSIS
        Finds the Copper Point of Sale executable on the system.
    .OUTPUTS
        String path to the Copper POS executable.
    #>

    # First check saved path from post_start
    $savedPath = "C:\Users\Docker\copper_exe_path.txt"
    if (Test-Path $savedPath) {
        $path = (Get-Content $savedPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
        if ($path -and (Test-Path $path)) {
            return $path
        }
    }

    # Check known location
    $knownPath = "C:\Program Files (x86)\NCH Software\Copper\copper.exe"
    if (Test-Path $knownPath) {
        return $knownPath
    }

    # Broader search
    $found = Get-ChildItem "C:\Program Files (x86)" -Recurse -Filter "copper.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        return $found.FullName
    }

    throw "Copper POS executable not found. Is it installed?"
}

# =====================================================================
# Copper POS Interactive Launch via schtasks
# =====================================================================

function Launch-CopperInteractive {
    <#
    .SYNOPSIS
        Launches Copper POS in the interactive desktop session.
        Tries PyAutoGUI Win+R first (most reliable for Session 1), then
        schtasks fallbacks with process polling and retry logic.
    .PARAMETER WaitSeconds
        Seconds to poll for Copper process per attempt (default 20).
    #>
    param(
        [int]$WaitSeconds = 20
    )

    $copperExe = Find-CopperExe
    Write-Host "Launching Copper POS from: $copperExe"

    # Ensure Task Scheduler service is running (needed for schtasks fallbacks)
    try {
        $svc = Get-Service -Name "Schedule" -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne "Running") {
            Start-Service -Name "Schedule" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }
    } catch { }

    # Create a batch launcher at a path with no spaces (safe for PyAutoGUI typing)
    $launchBat = "C:\Windows\Temp\launchcopper.cmd"
    [System.IO.File]::WriteAllText($launchBat, "@echo off`r`nstart `"`" `"$copperExe`"")

    # ── Strategy 1: PyAutoGUI Win+R (runs directly in Session 1) ──────────
    Write-Host "Attempt 1: Win+R via PyAutoGUI..."
    $pyguiOk = Send-PyAutoGUI -Command @{action="ping"}
    if ($pyguiOk) {
        # Press Escape first to dismiss any existing dialogs/menus
        PyAutoGUI-Press -Key "escape"
        Start-Sleep -Seconds 1
        PyAutoGUI-Hotkey -Keys @("win", "r")
        Start-Sleep -Seconds 2
        PyAutoGUI-Write -Text $launchBat
        Start-Sleep -Seconds 1
        PyAutoGUI-Press -Key "enter"
        Start-Sleep -Seconds 3

        if (Wait-ForCopperProcess -TimeoutSeconds $WaitSeconds) {
            Write-Host "Copper POS launched via Win+R."
            return
        }
        Write-Host "  Win+R attempt: process not detected."
    } else {
        Write-Host "  PyAutoGUI not available, skipping Win+R."
    }

    # ── Strategy 2: schtasks with CMD batch ───────────────────────────────
    Write-Host "Attempt 2: schtasks CMD batch..."
    $taskName = "LaunchCopper_GA_$(Get-Random)"
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN $taskName /TR "cmd /c `"$launchBat`"" /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>&1 | Out-Null
    schtasks /Run /TN $taskName 2>&1 | Out-Null
    $ErrorActionPreference = $prevEAP

    if (Wait-ForCopperProcess -TimeoutSeconds $WaitSeconds) {
        schtasks /Delete /TN $taskName /F 2>$null
        Write-Host "Copper POS launched via schtasks CMD."
        return
    }
    schtasks /Delete /TN $taskName /F 2>$null
    Write-Host "  schtasks CMD attempt: process not detected."

    # ── Strategy 3: schtasks with PowerShell Start-Process ────────────────
    Write-Host "Attempt 3: schtasks PowerShell..."
    $ps1File = "C:\Windows\Temp\launch_copper_ps.ps1"
    Set-Content -Path $ps1File -Value "Start-Process -FilePath `"$copperExe`""
    $taskName2 = "LaunchCopper_GA_$(Get-Random)"
    $trCmd = "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NonInteractive -File `"$ps1File`""
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN $taskName2 /TR "$trCmd" /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>&1 | Out-Null
    schtasks /Run /TN $taskName2 2>&1 | Out-Null
    $ErrorActionPreference = $prevEAP

    if (Wait-ForCopperProcess -TimeoutSeconds $WaitSeconds) {
        schtasks /Delete /TN $taskName2 /F 2>$null
        Remove-Item $ps1File -Force -ErrorAction SilentlyContinue
        Write-Host "Copper POS launched via schtasks PowerShell."
        return
    }
    schtasks /Delete /TN $taskName2 /F 2>$null
    Remove-Item $ps1File -Force -ErrorAction SilentlyContinue
    Write-Host "  schtasks PowerShell attempt: process not detected."

    # ── Strategy 4: Explorer launch ───────────────────────────────────────
    Write-Host "Attempt 4: Explorer launch..."
    $taskName3 = "LaunchCopper_GA_$(Get-Random)"
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN $taskName3 /TR "explorer `"$copperExe`"" /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>&1 | Out-Null
    schtasks /Run /TN $taskName3 2>&1 | Out-Null
    $ErrorActionPreference = $prevEAP

    if (Wait-ForCopperProcess -TimeoutSeconds $WaitSeconds) {
        schtasks /Delete /TN $taskName3 /F 2>$null
        Write-Host "Copper POS launched via Explorer."
        return
    }
    schtasks /Delete /TN $taskName3 /F 2>$null

    # Clean up
    Remove-Item $launchBat -Force -ErrorAction SilentlyContinue
    Write-Host "WARNING: All launch attempts failed for Copper POS."
}

# =====================================================================
# Process Management
# =====================================================================

function Stop-Copper {
    <#
    .SYNOPSIS
        Stops all Copper POS processes.
    #>
    Get-Process copper -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "Copper POS processes stopped."
}

function Wait-ForCopperProcess {
    <#
    .SYNOPSIS
        Waits for a Copper POS process to appear.
    .PARAMETER TimeoutSeconds
        Maximum seconds to wait (default 30).
    .OUTPUTS
        Boolean - true if process found, false if timeout.
    #>
    param([int]$TimeoutSeconds = 30)

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $copperProc = Get-Process copper -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($copperProc) {
            Write-Host "Copper POS process detected after ${elapsed}s"
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    Write-Host "WARNING: Copper POS process not detected within ${TimeoutSeconds}s"
    return $false
}

# =====================================================================
# Win32 API Helpers (for window management only)
# =====================================================================

if (-not ([System.Management.Automation.PSTypeName]'CopperWin32').Type) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CopperWin32 {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
}

function Minimize-Terminals {
    <#
    .SYNOPSIS
        Minimizes all command prompt and terminal windows.
    #>
    Get-Process cmd -ErrorAction SilentlyContinue | ForEach-Object {
        [CopperWin32]::ShowWindow($_.MainWindowHandle, 6) | Out-Null
    }
    Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID } | ForEach-Object {
        [CopperWin32]::ShowWindow($_.MainWindowHandle, 6) | Out-Null
    }
}
