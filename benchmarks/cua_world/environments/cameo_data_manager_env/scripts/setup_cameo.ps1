Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_post_start.log"
Start-Transcript -Path $logPath -Force | Out-Null

Write-Host "=== Setting up CAMEO Data Manager ==="
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ============================================================
# Phase 1: Locate CAMEO Data Manager executable
# ============================================================
Write-Host "`n--- Phase 1: Locating CAMEO Data Manager ---"

$cameoExe = $null
$savedPath = "C:\Users\Docker\cameo_path.txt"
if (Test-Path $savedPath) {
    $cameoExe = (Get-Content $savedPath -Raw).Trim()
    if (-not (Test-Path $cameoExe)) {
        $cameoExe = $null
    }
}

if (-not $cameoExe) {
    $searchPaths = @(
        "C:\Program Files (x86)\CAMEO Data Manager 4.5.1\CAMEO Data Manager.exe",
        "C:\Program Files\CAMEO Data Manager 4.5.1\CAMEO Data Manager.exe",
        "C:\Program Files (x86)\CAMEO Data Manager\CAMEO Data Manager.exe",
        "C:\Program Files\CAMEO Data Manager\CAMEO Data Manager.exe"
    )
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            $cameoExe = $path
            break
        }
    }
}

if (-not $cameoExe) {
    # Broad search
    $found = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse -Filter "CAMEO Data Manager.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) {
        $cameoExe = $found.FullName
    }
}

if ($cameoExe) {
    Write-Host "Found CAMEO at: $cameoExe"
    Set-Content -Path "C:\Users\Docker\cameo_path.txt" -Value $cameoExe -Encoding UTF8
} else {
    Write-Host "ERROR: CAMEO Data Manager not found"
    Stop-Transcript
    exit 1
}

# ============================================================
# Phase 2: Kill Edge to prevent interference
# ============================================================
Write-Host "`n--- Phase 2: Killing Edge ---"

# Disable Edge startup and session restore
$edgeRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (-not (Test-Path $edgeRegPath)) {
    New-Item -Path $edgeRegPath -Force | Out-Null
}
New-ItemProperty -Path $edgeRegPath -Name "StartupBoostEnabled" -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $edgeRegPath -Name "BackgroundModeEnabled" -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $edgeRegPath -Name "RestoreOnStartup" -Value 5 -PropertyType DWord -Force | Out-Null

# Clear Edge session data
$edgeUserData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
if (Test-Path $edgeUserData) {
    Get-ChildItem $edgeUserData -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($f in @("Current Session", "Current Tabs", "Last Session", "Last Tabs")) {
            $fPath = Join-Path $_.FullName $f
            Remove-Item $fPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# Aggressively kill Edge
for ($k = 0; $k -lt 5; $k++) {
    $ErrorActionPreference = "Continue"
    taskkill /F /IM msedge.exe 2>$null
    $ErrorActionPreference = "Stop"
    Start-Sleep -Seconds 1
}

# ============================================================
# Phase 2b: Suppress OneDrive popup
# ============================================================
Write-Host "`n--- Phase 2b: Suppressing OneDrive ---"

$ErrorActionPreference = "Continue"

# Kill OneDrive process
Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Disable OneDrive via Group Policy
$oneDrivePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
if (-not (Test-Path $oneDrivePolicy)) {
    New-Item -Path $oneDrivePolicy -Force | Out-Null
}
New-ItemProperty -Path $oneDrivePolicy -Name "DisableFileSyncNGSC" -Value 1 -PropertyType DWord -Force | Out-Null

# Remove OneDrive from startup
Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -Force -ErrorAction SilentlyContinue

# Uninstall OneDrive silently
$oneDriveSetup = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
if (-not (Test-Path $oneDriveSetup)) {
    $oneDriveSetup = "$env:SystemRoot\System32\OneDriveSetup.exe"
}
if (Test-Path $oneDriveSetup) {
    Start-Process $oneDriveSetup -ArgumentList "/uninstall" -Wait -ErrorAction SilentlyContinue
    Write-Host "OneDrive uninstalled"
}

$ErrorActionPreference = "Stop"

# ============================================================
# Phase 3: Warm-up launch to dismiss first-run dialogs
# ============================================================
Write-Host "`n--- Phase 3: Warm-up launch (dismiss first-run dialogs) ---"

# Wait for PyAutoGUI server
$pyagReady = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        $testSock = New-Object System.Net.Sockets.TcpClient
        $iar = $testSock.BeginConnect("127.0.0.1", 5555, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(2000, $false)) {
            $testSock.EndConnect($iar)
            $testSock.Close()
            $pyagReady = $true
            break
        }
        $testSock.Close()
    } catch { }
    Start-Sleep -Seconds 2
}

if ($pyagReady) {
    Write-Host "PyAutoGUI server is ready"

    # Launch CAMEO in interactive session (VBScript launcher — no cmd.exe window)
    $launchVbs = "C:\Windows\Temp\launch_cameo_warmup.vbs"
    $vbsContent = "CreateObject(`"Wscript.Shell`").Run `"`"`"$cameoExe`"`"`", 1, False"
    [System.IO.File]::WriteAllText($launchVbs, $vbsContent)

    $taskName = "LaunchCAMEO_Warmup"
    $ErrorActionPreference = "Continue"
    schtasks /Delete /TN $taskName /F 2>$null
    $startTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
    schtasks /Create /TN $taskName /TR "wscript.exe $launchVbs" /SC ONCE /ST $startTime /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN $taskName 2>$null
    $ErrorActionPreference = "Stop"

    Write-Host "Waiting for CAMEO to start..."
    Start-Sleep -Seconds 15

    # Helper function: send PyAutoGUI command
    function Send-PyAGCommand([string]$json) {
        try {
            $sock = New-Object System.Net.Sockets.TcpClient
            $iar2 = $sock.BeginConnect("127.0.0.1", 5555, $null, $null)
            if ($iar2.AsyncWaitHandle.WaitOne(3000, $false)) {
                $sock.EndConnect($iar2)
                $stream = $sock.GetStream()
                $writer = New-Object System.IO.StreamWriter($stream)
                $writer.AutoFlush = $true
                $reader = New-Object System.IO.StreamReader($stream)
                $writer.WriteLine($json)
                $resp = $reader.ReadLine()
                $sock.Close()
                return $resp
            }
            $sock.Close()
        } catch { }
        return $null
    }

    # Dismiss any first-run dialogs with Enter/Escape
    for ($d = 0; $d -lt 5; $d++) {
        Write-Host "  Dialog dismissal attempt $($d + 1)..."
        # Press Escape to close any dialog
        Send-PyAGCommand '{"action":"press","keys":"escape"}' | Out-Null
        Start-Sleep -Seconds 2
        # Press Enter as alternative
        Send-PyAGCommand '{"action":"press","keys":"enter"}' | Out-Null
        Start-Sleep -Seconds 2
    }

    # Let the app fully load
    Start-Sleep -Seconds 10

    # Dismiss OneDrive "Turn On Windows Backup" popup if present
    Write-Host "Dismissing OneDrive popup if present..."
    Send-PyAGCommand '{"action":"click","x":1135,"y":627}' | Out-Null
    Start-Sleep -Seconds 2

    # Close the app gracefully with Alt+F4
    Write-Host "Closing CAMEO warm-up instance..."
    Send-PyAGCommand '{"action":"hotkey","keys":["alt","F4"]}' | Out-Null
    Start-Sleep -Seconds 5

    # Handle any "save changes?" dialog
    Send-PyAGCommand '{"action":"press","keys":"enter"}' | Out-Null
    Start-Sleep -Seconds 3

    # Force kill if still running
    $ErrorActionPreference = "Continue"
    Get-Process | Where-Object { $_.ProcessName -like "*CAMEO*" -or $_.ProcessName -like "*cameo*" -or $_.ProcessName -like "*DataManager*" } | Stop-Process -Force -ErrorAction SilentlyContinue
    schtasks /Delete /TN $taskName /F 2>$null
    $ErrorActionPreference = "Stop"

    Write-Host "Warm-up launch complete"
} else {
    Write-Host "WARNING: PyAutoGUI server not available for warm-up"
}

# ============================================================
# Phase 3b: Relaunch CAMEO Data Manager (leave it open for user)
# ============================================================
Write-Host "`n--- Phase 3b: Relaunching CAMEO Data Manager ---"
if ($pyagReady -and $cameoExe) {
    Start-Sleep -Seconds 3

    $launchVbs2 = "C:\Windows\Temp\launch_cameo_final.vbs"
    $vbsContent2 = "CreateObject(`"Wscript.Shell`").Run `"`"`"$cameoExe`"`"`", 1, False"
    [System.IO.File]::WriteAllText($launchVbs2, $vbsContent2)

    $taskName2 = "LaunchCAMEO_Final"
    $ErrorActionPreference = "Continue"
    schtasks /Delete /TN $taskName2 /F 2>$null
    $startTime2 = (Get-Date).AddMinutes(1).ToString("HH:mm")
    schtasks /Create /TN $taskName2 /TR "wscript.exe $launchVbs2" /SC ONCE /ST $startTime2 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN $taskName2 2>$null
    $ErrorActionPreference = "Stop"

    Write-Host "Waiting for CAMEO to start..."
    Start-Sleep -Seconds 15

    # Dismiss any dialogs that appear on relaunch
    if ($pyagReady) {
        for ($d2 = 0; $d2 -lt 3; $d2++) {
            Send-PyAGCommand '{"action":"press","keys":"escape"}' | Out-Null
            Start-Sleep -Seconds 1
            Send-PyAGCommand '{"action":"press","keys":"enter"}' | Out-Null
            Start-Sleep -Seconds 1
        }
    }

    # Clean up scheduled task (but leave CAMEO running)
    $ErrorActionPreference = "Continue"
    schtasks /Delete /TN $taskName2 /F 2>$null
    $ErrorActionPreference = "Stop"
    Write-Host "CAMEO Data Manager relaunched and ready"
}

# ============================================================
# Phase 4: Kill Edge one more time
# ============================================================
Write-Host "`n--- Phase 4: Final Edge cleanup ---"
$ErrorActionPreference = "Continue"
for ($k = 0; $k -lt 3; $k++) {
    taskkill /F /IM msedge.exe 2>$null
    Start-Sleep -Seconds 1
}
$ErrorActionPreference = "Stop"

# ============================================================
# Phase 5: Write ready marker
# ============================================================
Write-Host "`n--- Phase 5: Writing ready marker ---"
Set-Content -Path "C:\Users\Docker\cameo_ready.marker" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Encoding UTF8

Write-Host "`n=== CAMEO Data Manager setup complete ==="
Stop-Transcript
