# task_utils.ps1 - Shared helper functions for DreamPlan task setup scripts.
# Uses PyAutoGUI TCP server (port 5555) for GUI automation.
# NCH DreamPlan requires PyAutoGUI for installer and dialog automation.
#
# CRITICAL NOTES:
# - VBScript variable 'wsh' causes error 800A01C2 on this Win11 image. ALWAYS use 'ws'.
# - DreamPlan uses schtasks /IT to launch in interactive Session 1.
# - "Abnormal Termination Detected" dialog and "Open Auto-save Project" dialog both
#   appear after force-kill and must be handled before start screen clicks.

# =====================================================================
# PyAutoGUI TCP Communication
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
        Write-Host "PyAutoGUI send failed: $($_.Exception.Message)"
        return $null
    }
}

function PyAutoGUI-Click {
    param([int]$X, [int]$Y)
    $result = Send-PyAutoGUI -Command @{action="click"; x=$X; y=$Y}
    Write-Host "PyAutoGUI clicked ($X, $Y)"
    Start-Sleep -Milliseconds 300
    return $result
}

function PyAutoGUI-DoubleClick {
    param([int]$X, [int]$Y)
    $result = Send-PyAutoGUI -Command @{action="doubleClick"; x=$X; y=$Y}
    Write-Host "PyAutoGUI double-clicked ($X, $Y)"
    Start-Sleep -Milliseconds 300
    return $result
}

function PyAutoGUI-Press {
    param([string]$Key)
    $result = Send-PyAutoGUI -Command @{action="press"; key=$Key}
    Write-Host "PyAutoGUI pressed: $Key"
    Start-Sleep -Milliseconds 200
    return $result
}

function PyAutoGUI-Hotkey {
    param([string[]]$Keys)
    $result = Send-PyAutoGUI -Command @{action="hotkey"; keys=$Keys}
    Write-Host "PyAutoGUI hotkey: $($Keys -join '+')"
    Start-Sleep -Milliseconds 200
    return $result
}

function PyAutoGUI-Write {
    param(
        [string]$Text,
        [double]$Interval = 0.02
    )
    $result = Send-PyAutoGUI -Command @{action="write"; text=$Text; interval=$Interval}
    Write-Host "PyAutoGUI typed: $Text"
    Start-Sleep -Milliseconds 300
    return $result
}

function Test-PyAutoGUIRunning {
    <#
    .SYNOPSIS
        Returns True if the PyAutoGUI server is responding on port 5555.
    #>
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.ReceiveTimeout = 3000
        $client.SendTimeout = 3000
        $client.Connect("127.0.0.1", 5555)
        $client.Close()
        return $true
    } catch {
        return $false
    }
}

function Restart-PyAutoGUIServer {
    <#
    .SYNOPSIS
        Restarts the PyAutoGUI TCP server via schtasks.
        Server script is at C:\Windows\Temp\pyautogui_server.py (uploaded by framework).
    #>
    Write-Host "Restarting PyAutoGUI server..."
    $taskName = "PyAutoGUIServer"
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $launcherPath = "C:\Windows\Temp\restart_pyautogui_hidden.vbs"

    # Kill existing python pyautogui processes
    Get-Process python -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.CommandLine -like "*pyautogui_server*") {
            $_.Kill()
        }
    }
    Start-Sleep -Seconds 1

    # Re-create and run the task (same as framework does)
    $serverScript = "C:\Windows\Temp\pyautogui_server.py"
    $launcherContent = 'Set ws = CreateObject("WScript.Shell")' + "`r`n" +
        'ws.Run "cmd /c python ""' + $serverScript + '"" --port 5555", 0, False'
    [System.IO.File]::WriteAllText($launcherPath, $launcherContent)
    schtasks /Delete /TN $taskName /F 2>$null
    schtasks /Create /TN $taskName /TR "wscript.exe $launcherPath" /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN $taskName 2>$null
    $ErrorActionPreference = $prevEAP

    # Wait up to 15s for server to be ready
    $waited = 0
    while ($waited -lt 15) {
        Start-Sleep -Seconds 1
        $waited++
        if (Test-PyAutoGUIRunning) {
            Remove-Item $launcherPath -Force -ErrorAction SilentlyContinue
            Write-Host "PyAutoGUI server restarted successfully after ${waited}s."
            return $true
        }
    }
    Remove-Item $launcherPath -Force -ErrorAction SilentlyContinue
    Write-Host "WARNING: PyAutoGUI server not responding after restart."
    return $false
}

function Ensure-PyAutoGUIRunning {
    <#
    .SYNOPSIS
        Checks if PyAutoGUI is running; restarts it if not.
    #>
    if (Test-PyAutoGUIRunning) {
        Write-Host "PyAutoGUI server is running."
        return $true
    }
    Write-Host "PyAutoGUI server is down. Attempting restart..."
    return Restart-PyAutoGUIServer
}

# =====================================================================
# DreamPlan State Detection
# =====================================================================
# CRITICAL NOTE: (Get-Process dreamplan).MainWindowTitle from Session 0 (SSH)
# ALWAYS returns empty string, because DreamPlan's GUI window is in Session 1
# (interactive desktop) which is not accessible from Session 0.
#
# Correct approach: Use VBScript via schtasks (runs in Session 1) with
# AppActivate to check window presence, then write result to a temp file
# that Session 0 can read.
# =====================================================================

function Test-ContemporaryHouseOpen {
    <#
    .SYNOPSIS
        Returns True if DreamPlan is running with Contemporary House project loaded.
        Uses PowerShell via schtasks (Session 1) to check MainWindowTitle.
        CRITICAL: MainWindowTitle is ONLY accessible from Session 1 (not Session 0/SSH).
        VBScript AppActivate("Contemporary House") was INCORRECT because it requires
        the window title to START WITH "Contemporary House", but DreamPlan's title is
        "DreamPlan by NCH Software - Contemporary House - ..." which starts with "DreamPlan".
    #>
    $psPath = "C:\Windows\Temp\check_dp_state.ps1"
    $resultPath = "C:\Windows\Temp\dp_state_result.txt"

    # PowerShell runs in Session 1 via schtasks /IT — MainWindowTitle IS accessible there.
    $psContent = 'Start-Sleep -Seconds 2' + "`n" +
        '$proc = Get-Process dreamplan -ErrorAction SilentlyContinue | Select-Object -First 1' + "`n" +
        'if ($proc) {' + "`n" +
        '    $t = $proc.MainWindowTitle' + "`n" +
        '    if ($t -like "*Contemporary House*") {' + "`n" +
        '        [System.IO.File]::WriteAllText("C:\Windows\Temp\dp_state_result.txt", "READY")' + "`n" +
        '    } else {' + "`n" +
        '        [System.IO.File]::WriteAllText("C:\Windows\Temp\dp_state_result.txt", ("NOT_READY:" + $t))' + "`n" +
        '    }' + "`n" +
        '} else {' + "`n" +
        '    [System.IO.File]::WriteAllText("C:\Windows\Temp\dp_state_result.txt", "NOT_READY:NO_PROCESS")' + "`n" +
        '}'

    [System.IO.File]::WriteAllText($psPath, $psContent)
    Remove-Item $resultPath -Force -ErrorAction SilentlyContinue

    $taskName = "CheckDPState_GA"
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
        # CRITICAL: | Out-Null prevents schtasks stdout from polluting caller's $var = Test-ContemporaryHouseOpen
        schtasks /Delete /TN $taskName /F 2>$null | Out-Null
        schtasks /Create /TN $taskName /TR "powershell.exe -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File `"$psPath`"" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null | Out-Null
        schtasks /Run /TN $taskName 2>$null | Out-Null
        # Wait: PowerShell startup ~2-3s + Sleep 2s + file write
        Start-Sleep -Seconds 8
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null | Out-Null
        Remove-Item $psPath -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }

    if (Test-Path $resultPath) {
        $result = (Get-Content $resultPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
        Remove-Item $resultPath -Force -ErrorAction SilentlyContinue
        Write-Host "DreamPlan state check result: '$result'"
        # Explicit [bool] cast prevents schtasks stdout being captured as array by caller
        return [bool]($result -eq "READY")
    }
    Write-Host "DreamPlan state check: result file not found (PS may have failed)"
    return $false
}

function Save-ScreenshotToFile {
    <#
    .SYNOPSIS
        Takes a screenshot from Session 1 (interactive desktop) via schtasks and saves to file.
        Uses System.Windows.Forms.Screen.CopyFromScreen which requires Session 1 access.
        Saves to C:\Users\Docker\ (SSH-accessible path).
    .PARAMETER Path
        Destination path for the PNG file (on Windows filesystem).
    #>
    param([string]$Path = "C:\Users\Docker\dp_screenshot.png")

    $psPath = "C:\Windows\Temp\take_screenshot.ps1"
    $psContent = 'Add-Type -AssemblyName System.Windows.Forms' + "`n" +
        'Add-Type -AssemblyName System.Drawing' + "`n" +
        '$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds' + "`n" +
        '$bmp = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)' + "`n" +
        '$g = [System.Drawing.Graphics]::FromImage($bmp)' + "`n" +
        '$g.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)' + "`n" +
        '$bmp.Save("' + $Path + '")' + "`n" +
        '$g.Dispose()' + "`n" +
        '$bmp.Dispose()'

    [System.IO.File]::WriteAllText($psPath, $psContent)

    $taskName = "TakeScreenshot_GA"
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
        schtasks /Delete /TN $taskName /F 2>$null | Out-Null
        schtasks /Create /TN $taskName /TR "powershell.exe -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File `"$psPath`"" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null | Out-Null
        schtasks /Run /TN $taskName 2>$null | Out-Null
        Start-Sleep -Seconds 6
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null | Out-Null
        Remove-Item $psPath -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }

    if (Test-Path $Path) {
        Write-Host "Screenshot saved: $Path"
        return $true
    }
    Write-Host "Screenshot failed: $Path not found"
    return $false
}

function Get-DreamPlanTitle {
    <#
    .SYNOPSIS
        NOTE: This returns empty from Session 0. Use Test-ContemporaryHouseOpen instead.
        Returns empty string (kept for backwards compatibility).
    #>
    $proc = Get-Process dreamplan -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) {
        return $proc.MainWindowTitle
    }
    return ""
}

function Wait-ForDreamPlanTitle {
    <#
    .SYNOPSIS
        NOTE: MainWindowTitle is always empty from Session 0. This function is kept
        for backwards compatibility but will always time out. Use Test-ContemporaryHouseOpen.
    #>
    param(
        [string]$Contains,
        [int]$TimeoutSeconds = 60
    )
    Write-Host "NOTE: Wait-ForDreamPlanTitle always times out from Session 0. Use Test-ContemporaryHouseOpen."
    return $false
}

# =====================================================================
# DreamPlan Executable Discovery
# =====================================================================

function Find-DreamPlanExe {
    $savedPath = "C:\Users\Docker\dreamplan_exe_path.txt"
    if (Test-Path $savedPath) {
        $path = (Get-Content $savedPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
        if ($path -and (Test-Path $path)) { return $path }
    }
    $knownPaths = @(
        "C:\Program Files (x86)\NCH Software\DreamPlan\dreamplan.exe",
        "C:\Program Files\NCH Software\DreamPlan\dreamplan.exe",
        "C:\Program Files (x86)\NCH Software\DreamPlan\DreamPlan.exe",
        "C:\Program Files\NCH Software\DreamPlan\DreamPlan.exe"
    )
    foreach ($kp in $knownPaths) {
        if (Test-Path $kp) { return $kp }
    }
    $searchDirs = @("C:\Program Files (x86)", "C:\Program Files")
    foreach ($dir in $searchDirs) {
        $found = Get-ChildItem $dir -Recurse -Filter "dreamplan.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    throw "DreamPlan executable not found. Is it installed?"
}

# =====================================================================
# DreamPlan License Dialog Dismissal
# =====================================================================

function Dismiss-DreamPlanLicenseDialog {
    <#
    .SYNOPSIS
        Detects and dismisses the "DreamPlan Free Version" non-commercial license dialog
        that appears on Windows Enterprise on every DreamPlan launch.
        Uses VBScript AppActivate to CHECK if dialog is present BEFORE clicking.
        CRITICAL: Only clicks (640, 360) when dialog IS detected.
        Blind click at (640, 360) without detection hits "Open Saved Project" on the
        start screen, opening a file dialog and derailing the entire navigation sequence.
    #>
    $vbsPath = "C:\Windows\Temp\check_license_dialog.vbs"
    $resultPath = "C:\Windows\Temp\license_dialog_result.txt"

    $vbsContent = 'Set ws = CreateObject("WScript.Shell")' + "`r`n" +
        'Set fso = CreateObject("Scripting.FileSystemObject")' + "`r`n" +
        'Set f = fso.CreateTextFile("' + $resultPath + '", True)' + "`r`n" +
        'WScript.Sleep 500' + "`r`n" +
        'If ws.AppActivate("DreamPlan Free Version") Then' + "`r`n" +
        '    f.Write "PRESENT"' + "`r`n" +
        'Else' + "`r`n" +
        '    f.Write "ABSENT"' + "`r`n" +
        'End If' + "`r`n" +
        'f.Close'
    [System.IO.File]::WriteAllText($vbsPath, $vbsContent)
    Remove-Item $resultPath -Force -ErrorAction SilentlyContinue

    $taskName = "CheckLicenseDialog_GA"
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
        schtasks /Delete /TN $taskName /F 2>$null | Out-Null
        schtasks /Create /TN $taskName /TR "wscript.exe `"$vbsPath`"" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null | Out-Null
        schtasks /Run /TN $taskName 2>$null | Out-Null
        Start-Sleep -Seconds 4
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null | Out-Null
        Remove-Item $vbsPath -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }

    if (Test-Path $resultPath) {
        $result = (Get-Content $resultPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
        Remove-Item $resultPath -Force -ErrorAction SilentlyContinue
        Write-Host "License dialog check: '$result'"
        if ($result -eq "PRESENT") {
            Write-Host "DreamPlan Free Version dialog found. Clicking non-commercial option (640, 360)..."
            PyAutoGUI-Click -X 640 -Y 360
            Start-Sleep -Seconds 2
            PyAutoGUI-Click -X 640 -Y 360
            Start-Sleep -Seconds 2
            Write-Host "License dialog dismissed."
        } else {
            Write-Host "No license dialog present. Start screen is accessible."
        }
    } else {
        Write-Host "License dialog check: result file not found. Assuming absent."
    }
}

# =====================================================================
# DreamPlan Interactive Launch via schtasks
# =====================================================================

function Launch-DreamPlanInteractive {
    <#
    .SYNOPSIS
        Launches DreamPlan in the interactive desktop session via schtasks + VBScript.
        CRITICAL: VBScript variable must be 'ws', NOT 'wsh' (causes error 800A01C2).
    .PARAMETER WaitSeconds
        Seconds to wait after launching (default 20).
    #>
    param([int]$WaitSeconds = 20)

    $dreamplanExe = Find-DreamPlanExe

    $vbsPath = "C:\Windows\Temp\launch_dreamplan.vbs"
    $vbsContent = 'Set ws = CreateObject("WScript.Shell")' + "`r`n" +
        'ws.Run """' + $dreamplanExe + '""", 1, False'
    [System.IO.File]::WriteAllText($vbsPath, $vbsContent)

    $taskName = "LaunchDreamPlan_GA"
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
        schtasks /Create /TN $taskName /TR "wscript.exe `"$vbsPath`"" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Start-Sleep -Seconds $WaitSeconds
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $vbsPath -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }
    Write-Host "DreamPlan launched (waited ${WaitSeconds}s)."
}

function Dismiss-DreamPlanStartupDialogs {
    <#
    .SYNOPSIS
        Dismisses startup dialogs that appear after force-kill:
        1. "Abnormal Termination Detected" crash dialog -> Tab+Enter
        2. "Open Auto-save Project" recovery dialog -> Tab+Enter ("No Thanks")
        Both appear before the start screen.
    #>
    Write-Host "Dismissing startup dialogs if present..."
    $vbsPath = "C:\Windows\Temp\dismiss_startup.vbs"
    $vbsContent = 'Set ws = CreateObject("WScript.Shell")' + "`r`n" +
        'WScript.Sleep 2000' + "`r`n" +
        '''' + "`r`n" +
        "' Bring DreamPlan to the foreground first" + "`r`n" +
        'ws.AppActivate "DreamPlan"' + "`r`n" +
        'WScript.Sleep 500' + "`r`n" +
        '''' + "`r`n" +
        "' Dismiss 'Abnormal Termination' crash dialog (after force-kill)" + "`r`n" +
        'If ws.AppActivate("Abnormal Termination") Then' + "`r`n" +
        '    WScript.Sleep 500' + "`r`n" +
        '    ws.SendKeys "{TAB}"' + "`r`n" +
        '    WScript.Sleep 300' + "`r`n" +
        '    ws.SendKeys "{ENTER}"' + "`r`n" +
        '    WScript.Sleep 2000' + "`r`n" +
        'End If' + "`r`n" +
        '''' + "`r`n" +
        "' Dismiss 'Open Auto-save Project' dialog" + "`r`n" +
        'If ws.AppActivate("Auto-save") Then' + "`r`n" +
        '    WScript.Sleep 500' + "`r`n" +
        '    ws.SendKeys "{TAB}"' + "`r`n" +
        '    WScript.Sleep 300' + "`r`n" +
        '    ws.SendKeys "{ENTER}"' + "`r`n" +
        '    WScript.Sleep 2000' + "`r`n" +
        'End If' + "`r`n" +
        '''' + "`r`n" +
        "' Ensure DreamPlan is in foreground after all dismissals" + "`r`n" +
        'ws.AppActivate "DreamPlan"' + "`r`n" +
        'WScript.Sleep 500'
    [System.IO.File]::WriteAllText($vbsPath, $vbsContent)

    $taskName = "DismissStartup_GA"
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
        schtasks /Create /TN $taskName /TR "wscript.exe `"$vbsPath`"" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Start-Sleep -Seconds 8
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $vbsPath -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }
}

function Open-ContemporaryHouseFromStartScreen {
    <#
    .SYNOPSIS
        Navigates DreamPlan's start screen to open the Contemporary House sample project.
        Uses fixed sleeps (NOT window title polling — MainWindowTitle is always empty from Session 0).
        - "View Sample Project": (768, 260)
        - "Contemporary House" thumbnail: (452, 324)
        - "Open Project" button: (857, 570)
    .PARAMETER MaxWaitSec
        Maximum seconds to wait for sample dialog (default 45; first-time download needs ~45s).
    #>
    param([int]$MaxWaitSec = 45)

    # Ensure PyAutoGUI is running before clicking
    Ensure-PyAutoGUIRunning

    # Diagnostic screenshot: state before clicking "View Sample Project"
    Save-ScreenshotToFile -Path "C:\Users\Docker\nav_step0_before_click.png"

    Write-Host "Clicking 'View Sample Project' on start screen..."
    PyAutoGUI-Click -X 768 -Y 260

    # Wait for sample selection dialog to appear.
    # First-time: samples download takes ~30-45s. After caching: ~3s.
    # Use MaxWaitSec parameter so callers can override.
    Write-Host "Waiting ${MaxWaitSec}s for sample dialog to appear..."
    Start-Sleep -Seconds $MaxWaitSec

    # Diagnostic screenshot: state after waiting for sample dialog
    Save-ScreenshotToFile -Path "C:\Users\Docker\nav_step1_after_dialog_wait.png"

    # Check DreamPlan process is still alive
    $proc = Get-Process dreamplan -ErrorAction SilentlyContinue
    if (-not $proc) {
        Write-Host "ERROR: DreamPlan process died while waiting for sample dialog."
        return $false
    }

    Write-Host "Selecting 'Contemporary House'..."
    PyAutoGUI-Click -X 452 -Y 324
    Start-Sleep -Seconds 2
    # Retry in case dialog needs extra time
    PyAutoGUI-Click -X 452 -Y 324
    Start-Sleep -Seconds 2

    # Diagnostic screenshot: state after selecting Contemporary House
    Save-ScreenshotToFile -Path "C:\Users\Docker\nav_step2_after_select.png"

    Write-Host "Clicking 'Open Project'..."
    PyAutoGUI-Click -X 857 -Y 570

    # Wait for project to load. Cannot use window title from Session 0.
    # Contemporary House 3D rendering takes ~10-15 seconds.
    Write-Host "Waiting 30s for Contemporary House to load..."
    Start-Sleep -Seconds 30

    # Diagnostic screenshot: state after project load wait
    Save-ScreenshotToFile -Path "C:\Users\Docker\nav_step3_after_load.png"

    Write-Host "Navigation sequence complete (project should be loading or loaded)."
    return $true
}

function Complete-DreamPlanTutorial {
    <#
    .SYNOPSIS
        Completes/dismisses the "Click to Get Started" tutorial overlay by
        starting and immediately canceling it. After Cancel, the 3D view is
        clean and the tutorial won't appear again in this session.
        - "Click to Get Started" button: (640, 335)
        - Trace wizard Cancel button: (194, 312)
    #>
    Write-Host "Dismissing tutorial overlay (start+cancel)..."

    # Check if tutorial is visible by looking for the overlay via PyAutoGUI
    # Simple approach: click "Click to Get Started" which starts the Trace wizard
    Ensure-PyAutoGUIRunning
    PyAutoGUI-Click -X 640 -Y 335
    Start-Sleep -Seconds 5

    # Cancel the Trace wizard to return to clean 3D view
    # Cancel button is at the bottom of the left panel in the Trace wizard
    Write-Host "Clicking Cancel on Trace wizard..."
    PyAutoGUI-Click -X 194 -Y 312
    Start-Sleep -Seconds 3

    # Verify we're back to 3D view (title should still show Contemporary House)
    $title = Get-DreamPlanTitle
    if ($title -like "*Contemporary House*") {
        Write-Host "Tutorial dismissed. Back to 3D view with Contemporary House."
        return $true
    } else {
        Write-Host "WARNING: After tutorial dismiss, title is: $title"
        return $false
    }
}

function Launch-DreamPlanWithSample {
    <#
    .SYNOPSIS
        Full launch sequence: launch DreamPlan, dismiss startup dialogs,
        navigate start screen, open Contemporary House, dismiss tutorial.
        Used during post_start warm-up and recovery.
    .PARAMETER WaitSeconds
        Seconds to wait for DreamPlan to initially load (default 20).
    .PARAMETER SampleWaitSec
        Seconds to wait for sample dialog to appear (default 20 for cached samples;
        use 60 for first-time setup when samples need downloading).
    #>
    param(
        [int]$WaitSeconds = 45,
        [int]$SampleWaitSec = 20
    )

    # Clear any visible consoles from the interactive desktop before launching DreamPlan.
    Write-Host "Preparing desktop for DreamPlan launch..."
    Ensure-PyAutoGUIRunning
    Minimize-ConsoleAndBringDreamPlanToFront

    Launch-DreamPlanInteractive -WaitSeconds $WaitSeconds

    Dismiss-DreamPlanStartupDialogs

    # Detect and dismiss "DreamPlan Free Version" non-commercial license dialog.
    # CRITICAL: Must be conditional — blind click at (640, 360) hits "Open Saved Project"
    # when the dialog is absent, derailing the entire navigation sequence.
    Dismiss-DreamPlanLicenseDialog

    $opened = Open-ContemporaryHouseFromStartScreen -MaxWaitSec $SampleWaitSec
    if (-not $opened) {
        Write-Host "WARNING: Open-ContemporaryHouseFromStartScreen reported failure. Continuing anyway..."
        # Don't return early - DreamPlan process may still be running
    }

    # Wait for 3D rendering to settle
    Start-Sleep -Seconds 5

    # Dismiss tutorial overlay if present (start+cancel pattern)
    Complete-DreamPlanTutorial
    return $true
}

function Verify-DreamPlanState {
    <#
    .SYNOPSIS
        Verifies DreamPlan is running with Contemporary House loaded.
        Uses VBScript AppActivate (Session 1) to correctly detect window state.
        Returns True if correct, False otherwise.
    #>
    $ready = Test-ContemporaryHouseOpen
    if ($ready) {
        Write-Host "DreamPlan state verified: Contemporary House is loaded."
    } else {
        Write-Host "DreamPlan state mismatch: Contemporary House window not found."
    }
    return $ready
}

function Ensure-DreamPlanReadyForTask {
    <#
    .SYNOPSIS
        Primary pre_task function. Verifies DreamPlan is in the correct state
        (Contemporary House loaded, no tutorial overlay). If not, performs
        recovery steps.

        IMPORTANT: Uses Test-ContemporaryHouseOpen (VBScript via schtasks in Session 1)
        to detect state — NOT Get-DreamPlanTitle (MainWindowTitle from Session 0 is
        always empty for GUI windows in Session 1).
    #>

    # Ensure PyAutoGUI is running (may need restart after loadvm)
    Write-Host "Ensuring PyAutoGUI is running..."
    Ensure-PyAutoGUIRunning

    # Clear any visible consoles and restore DreamPlan focus if it is already running.
    Write-Host "Preparing DreamPlan desktop state..."
    Minimize-ConsoleAndBringDreamPlanToFront

    # Dismiss any startup dialogs that may appear after loadvm restore
    # (e.g. "Abnormal Termination" or "Open Auto-save Project" dialogs).
    # This must happen BEFORE checking window state — dialogs block the Contemporary House window.
    Dismiss-DreamPlanStartupDialogs

    # Check if DreamPlan is already in the correct state using PowerShell in Session 1.
    # CRITICAL: MainWindowTitle is only accessible from Session 1, not from Session 0/SSH.
    # VBScript AppActivate was WRONG — it requires title to start with the search string,
    # but DreamPlan's title is "DreamPlan by NCH Software - Contemporary House - ..."
    Write-Host "Checking if Contemporary House is already open (via PowerShell in Session 1)..."
    $alreadyOpen = Test-ContemporaryHouseOpen

    if ($alreadyOpen) {
        Write-Host "DreamPlan is running with Contemporary House. Dismissing any overlays..."

        # Dismiss any tooltip/overlay that may have appeared. Press Escape (harmless if nothing there).
        PyAutoGUI-Press -Key "escape"
        Start-Sleep -Seconds 1

        # Click a neutral area in the 3D viewport to ensure DreamPlan has focus.
        # Avoid the menu bar or toolbar which could trigger unintended actions.
        PyAutoGUI-Click -X 640 -Y 400
        Start-Sleep -Seconds 1

        Write-Host "DreamPlan ready for task."
        return $true
    }

    # DreamPlan not in expected state - need to recover
    Write-Host "Contemporary House not found. Performing recovery launch..."

    # Kill any existing DreamPlan
    Stop-DreamPlan

    # Full launch sequence with contemporary house.
    # WaitSeconds=45: DreamPlan takes 40+ seconds to show its window on this VM.
    # SampleWaitSec=45: generous wait for sample dialog (covers both cached and re-download).
    $success = Launch-DreamPlanWithSample -WaitSeconds 45 -SampleWaitSec 45

    if (-not $success) {
        Write-Host "WARNING: Recovery launch may have failed."
    }

    # Final verify using PowerShell Session 1 detection
    $finalReady = Test-ContemporaryHouseOpen
    if ($finalReady) {
        Write-Host "Recovery launch verified: Contemporary House is now open."
    } else {
        Write-Host "WARNING: Could not verify Contemporary House is open after recovery launch."
    }
    return $finalReady
}

function Close-DreamPlanGracefully {
    $proc = Get-Process dreamplan, DreamPlan -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) {
        Write-Host "DreamPlan not running, nothing to close."
        return
    }

    $vbsPath = "C:\Windows\Temp\close_dreamplan.vbs"
    $vbsContent = 'Set ws = CreateObject("WScript.Shell")' + "`r`n" +
        'ws.AppActivate "DreamPlan"' + "`r`n" +
        'WScript.Sleep 500' + "`r`n" +
        'ws.SendKeys "%{F4}"' + "`r`n" +
        'WScript.Sleep 3000' + "`r`n" +
        'ws.SendKeys "n"'
    [System.IO.File]::WriteAllText($vbsPath, $vbsContent)

    $taskName = "CloseDreamPlan_GA"
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
        schtasks /Create /TN $taskName /TR "wscript.exe `"$vbsPath`"" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN $taskName 2>$null
        Start-Sleep -Seconds 8
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null
        Remove-Item $vbsPath -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }

    Start-Sleep -Seconds 2
    $stillRunning = Get-Process dreamplan, DreamPlan -ErrorAction SilentlyContinue
    if ($stillRunning) {
        Write-Host "DreamPlan still running after graceful close, force-killing..."
        Stop-DreamPlan
    } else {
        Write-Host "DreamPlan closed gracefully."
    }
}

# =====================================================================
# Process Management
# =====================================================================

function Stop-DreamPlan {
    Get-Process dreamplan -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process DreamPlan -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "DreamPlan processes stopped."
}

function Wait-ForDreamPlanProcess {
    param([int]$TimeoutSeconds = 30)
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $proc = Get-Process dreamplan, DreamPlan -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($proc) {
            Write-Host "DreamPlan process detected after ${elapsed}s"
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    Write-Host "WARNING: DreamPlan process not detected within ${TimeoutSeconds}s"
    return $false
}

# =====================================================================
# Edge Browser Killer (prevents auto-restore interference)
# =====================================================================

function Start-EdgeKillerTask {
    $taskName = "KillEdge_GA"
    $vbsPath = "C:\Windows\Temp\kill_edge.vbs"
    $vbsContent = 'Set ws = CreateObject("Wscript.Shell")' + "`r`n" +
        'ws.Run "cmd /c for /L %i in (1,1,60) do (taskkill /F /IM msedge.exe >nul 2>&1 & timeout /t 2 >nul)", 0, False'
    [System.IO.File]::WriteAllText($vbsPath, $vbsContent)

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
    schtasks /Create /TN $taskName /TR "wscript.exe $vbsPath" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN $taskName 2>$null
    $ErrorActionPreference = $prevEAP
    Write-Host "Edge killer task started (hidden)."
}

function Stop-EdgeKillerTask {
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    schtasks /Delete /TN "KillEdge_GA" /F 2>$null
    $ErrorActionPreference = $prevEAP
    Write-Host "Edge killer task stopped."
}

# =====================================================================
# Win32 API Helpers (for window management only)
# =====================================================================

if (-not ([System.Management.Automation.PSTypeName]'DreamPlanWin32').Type) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DreamPlanWin32 {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
}

function Minimize-ConsoleAndBringDreamPlanToFront {
    <#
    .SYNOPSIS
        Runs in Session 1 to minimize any visible console-style windows and,
        if DreamPlan is already running, restore it to the foreground.
    #>
    $psPath = "C:\Windows\Temp\focus_dreamplan_windows.ps1"
    $psContent = @'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class DreamPlanWindowTask {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@

Get-Process | Where-Object {
    ($_.ProcessName -match "cmd|powershell|python|WindowsTerminal|wt|conhost") -and
    $_.MainWindowHandle -ne [IntPtr]::Zero
} | ForEach-Object {
    [DreamPlanWindowTask]::ShowWindow($_.MainWindowHandle, 6) | Out-Null
}

$proc = Get-Process dreamplan, DreamPlan -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
    [DreamPlanWindowTask]::ShowWindow($proc.MainWindowHandle, 9) | Out-Null
    [DreamPlanWindowTask]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
}
'@
    [System.IO.File]::WriteAllText($psPath, $psContent)

    $taskName = "FocusDreamPlan_GA"
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
        schtasks /Delete /TN $taskName /F 2>$null | Out-Null
        schtasks /Create /TN $taskName /TR "powershell.exe -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File `"$psPath`"" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null | Out-Null
        schtasks /Run /TN $taskName 2>$null | Out-Null
        Start-Sleep -Seconds 3
    } finally {
        schtasks /Delete /TN $taskName /F 2>$null | Out-Null
        Remove-Item $psPath -Force -ErrorAction SilentlyContinue
        $ErrorActionPreference = $prevEAP
    }
    Write-Host "Interactive console windows minimized; DreamPlan activated when present."
}
