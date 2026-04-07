Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up ADAudit Plus environment ==="

    # ------------------------------------------------------------------
    # 1. Determine install directory
    # ------------------------------------------------------------------
    $installDir = $null
    $markerFile = "C:\Windows\Temp\adaudit_install_dir.txt"
    if (Test-Path $markerFile) {
        $installDir = (Get-Content $markerFile -Raw).Trim()
    }
    if (-not $installDir -or -not (Test-Path $installDir)) {
        foreach ($p in @(
            "C:\Program Files\ManageEngine\ADAudit Plus",
            "C:\ManageEngine\ADAudit Plus",
            "C:\Program Files (x86)\ManageEngine\ADAudit Plus"
        )) {
            if (Test-Path $p) { $installDir = $p; break }
        }
    }
    if (-not $installDir) { throw "ADAudit Plus install directory not found" }
    Write-Host "Install directory: $installDir"
    $binDir = "$installDir\bin"

    # ------------------------------------------------------------------
    # 2. Ensure service is running
    # ------------------------------------------------------------------
    Write-Host "Ensuring ADAudit Plus is running..."

    $svc = Get-Service | Where-Object { $_.DisplayName -like "*ADAudit*" } | Select-Object -First 1
    if ($svc) {
        if ($svc.Status -ne "Running") {
            Write-Host "Starting service via net start..."
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            net start "ADAudit Plus" 2>$null
            $ErrorActionPreference = $prevEAP
            Start-Sleep -Seconds 5
            $svc = Get-Service | Where-Object { $_.DisplayName -like "*ADAudit*" } | Select-Object -First 1
        }
        Write-Host "Service: $($svc.Name) - $($svc.Status)"
    } else {
        Write-Host "No Windows service found, starting via run.bat..."
        $prev = Get-Location
        Set-Location $binDir
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c run.bat" -WindowStyle Hidden
        Set-Location $prev
        Start-Sleep -Seconds 10
    }

    # ------------------------------------------------------------------
    # 3. Wait for HTTP readiness
    # ------------------------------------------------------------------
    Write-Host "Waiting for web server on port 8081..."
    $timeout = 300
    $elapsed = 0
    $ready = $false
    while ($elapsed -lt $timeout) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:8081/" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 400) {
                Write-Host "Web server ready (HTTP $($r.StatusCode)) after ${elapsed}s"
                $ready = $true
                break
            }
        } catch {}
        Start-Sleep -Seconds 5
        $elapsed += 5
        if ($elapsed % 30 -eq 0) { Write-Host "  Still waiting... ${elapsed}s" }
    }
    if (-not $ready) {
        Write-Host "WARNING: Web server not responding after ${timeout}s"
    }

    # ------------------------------------------------------------------
    # 4. Generate real Windows Security events
    # ------------------------------------------------------------------
    Write-Host "Generating real Windows Security events..."
    $genScript = "C:\workspace\data\generate_audit_events.ps1"
    if (Test-Path $genScript) {
        & $genScript
    } else {
        Write-Host "WARNING: generate_audit_events.ps1 not found at $genScript"
    }

    # ------------------------------------------------------------------
    # 5. Enable local audit policies
    # ------------------------------------------------------------------
    Write-Host "Configuring local audit policies..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    auditpol /set /category:"Account Logon" /success:enable /failure:enable 2>$null
    auditpol /set /category:"Account Management" /success:enable /failure:enable 2>$null
    auditpol /set /category:"Logon/Logoff" /success:enable /failure:enable 2>$null
    auditpol /set /category:"Object Access" /success:enable /failure:enable 2>$null
    auditpol /set /category:"Policy Change" /success:enable /failure:enable 2>$null
    auditpol /set /category:"System" /success:enable /failure:enable 2>$null
    $ErrorActionPreference = $prevEAP
    Write-Host "Audit policies configured"

    # ------------------------------------------------------------------
    # 6. Add workgroup server via browser automation
    # ------------------------------------------------------------------
    # ADAudit Plus redirects all navigation to "Add Domain Details" until
    # at least one domain or workgroup server is configured.
    # We add the local machine as a workgroup server so agents can navigate.
    Write-Host "Adding local machine as workgroup server..."

    $pyagPort = 5555
    function Send-PyAG2 {
        param([hashtable]$Cmd)
        try {
            $c = New-Object System.Net.Sockets.TcpClient
            $c.ReceiveTimeout = 5000
            $c.Connect("127.0.0.1", $pyagPort)
            $s = $c.GetStream()
            $json = ($Cmd | ConvertTo-Json -Compress) + "`n"
            $b = [System.Text.Encoding]::UTF8.GetBytes($json)
            $s.Write($b, 0, $b.Length)
            $s.Flush()
            Start-Sleep -Milliseconds 300
            $resp = ""
            if ($s.DataAvailable) {
                $buf = New-Object byte[] 4096
                $n = $s.Read($buf, 0, $buf.Length)
                $resp = [System.Text.Encoding]::UTF8.GetString($buf, 0, $n)
            }
            $c.Close()
            return $resp
        } catch { return $null }
    }
    function PyAG2-Click([int]$X, [int]$Y) {
        Write-Host "  click ($X, $Y)"
        Send-PyAG2 @{action="click"; x=$X; y=$Y}
        Start-Sleep -Milliseconds 500
    }
    function PyAG2-Type([string]$Text) {
        Write-Host "  type '$Text'"
        Send-PyAG2 @{action="typewrite"; text=$Text}
        Start-Sleep -Milliseconds 300
    }
    function PyAG2-Press([string]$Key) {
        Write-Host "  press '$Key'"
        Send-PyAG2 @{action="press"; key=$Key}
        Start-Sleep -Milliseconds 300
    }
    function PyAG2-Hotkey([string[]]$Keys) {
        Write-Host "  hotkey $($Keys -join '+')"
        Send-PyAG2 @{action="hotkey"; keys=$Keys}
        Start-Sleep -Milliseconds 300
    }

    # Wait for PyAutoGUI server
    $pyagReady = $false
    for ($i = 0; $i -lt 10; $i++) {
        $r = Send-PyAG2 @{action="moveTo"; x=640; y=360}
        if ($null -ne $r) { $pyagReady = $true; break }
        Start-Sleep -Seconds 2
    }

    if ($pyagReady) {
        # Kill any existing Edge
        Get-Process -Name "msedge" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # Minimize all windows
        PyAG2-Hotkey @("win", "d")
        Start-Sleep -Seconds 2

        # Launch Edge to login page.
        # FRE and password popups disabled via registry policies set during pre_start.
        $edgeBatch = "C:\Windows\Temp\launch_edge_wg.cmd"
        "@echo off`r`nstart `"`" `"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`" --start-maximized --no-first-run --disable-sync --no-default-browser-check --disable-features=msEdgeOnRampFRE `"http://localhost:8081/`"" | Out-File -FilePath $edgeBatch -Encoding ASCII

        $prevEAP2 = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        schtasks /Delete /TN LaunchEdgeWG /F 2>$null
        schtasks /Create /TN LaunchEdgeWG /TR "cmd /c $edgeBatch" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN LaunchEdgeWG 2>$null
        $ErrorActionPreference = $prevEAP2

        Write-Host "Waiting for login page..."
        Start-Sleep -Seconds 20
        schtasks /Delete /TN LaunchEdgeWG /F 2>$null
        Remove-Item $edgeBatch -Force -ErrorAction SilentlyContinue

        # Login: type username (in case not pre-filled), then password, then click LOGIN
        Write-Host "Logging in..."
        PyAG2-Click 915 265          # Username field
        Start-Sleep -Seconds 1
        PyAG2-Hotkey @("ctrl", "a")  # Select all
        Start-Sleep -Milliseconds 200
        PyAG2-Type "admin"           # Type username
        Start-Sleep -Milliseconds 500
        PyAG2-Click 915 309          # Password field
        Start-Sleep -Seconds 1
        PyAG2-Type "Admin"
        Start-Sleep -Milliseconds 200
        PyAG2-Hotkey @("shift", "2") # @
        Start-Sleep -Milliseconds 200
        PyAG2-Type "2024"
        Start-Sleep -Milliseconds 500
        PyAG2-Click 788 467          # LOGIN button
        Start-Sleep -Seconds 10

        # After login, we land on Domain Settings page.
        # Click "Add Workgroup Server" button at ~(1169, 173)
        Write-Host "Clicking Add Workgroup Server..."
        PyAG2-Click 1169 173
        Start-Sleep -Seconds 3

        # On the Workgroup Servers Configuration page, click "+ Add Server" at ~(1205, 310)
        Write-Host "Clicking + Add Server..."
        PyAG2-Click 1205 310
        Start-Sleep -Seconds 3

        # Fill Server Name field at ~(660, 365)
        Write-Host "Filling server form..."
        PyAG2-Click 660 365
        Start-Sleep -Seconds 1
        PyAG2-Type "localhost"
        Start-Sleep -Milliseconds 500

        # Fill Username at ~(660, 423)
        PyAG2-Click 660 423
        Start-Sleep -Seconds 1
        PyAG2-Type "Docker"
        Start-Sleep -Milliseconds 500

        # Fill Password at ~(660, 465)
        PyAG2-Click 660 465
        Start-Sleep -Seconds 1
        PyAG2-Type "GymAnything123"
        Start-Sleep -Milliseconds 200
        PyAG2-Hotkey @("shift", "1") # !
        Start-Sleep -Milliseconds 300

        # Click Save at ~(540, 635)
        Write-Host "Saving workgroup server..."
        PyAG2-Click 540 635
        Start-Sleep -Seconds 5

        # Close Edge
        Write-Host "Closing browser..."
        Get-Process -Name "msedge" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3

        Write-Host "Workgroup server added (localhost)"

        # Relaunch Edge to ADAudit Plus main page so it's visible on screen
        Start-Sleep -Seconds 3
        Write-Host "Relaunching Edge to ADAudit Plus..."
        $edgeBatch2 = "C:\Windows\Temp\launch_edge_main.cmd"
        "@echo off`r`nstart `"`" `"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`" --start-maximized --no-first-run --disable-sync --no-default-browser-check --disable-features=msEdgeOnRampFRE `"http://localhost:8081/`"" | Out-File -FilePath $edgeBatch2 -Encoding ASCII

        $prevEAP3 = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        schtasks /Delete /TN LaunchEdgeMain /F 2>$null
        schtasks /Create /TN LaunchEdgeMain /TR "cmd /c $edgeBatch2" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN LaunchEdgeMain 2>$null
        $ErrorActionPreference = $prevEAP3
        Start-Sleep -Seconds 10
        schtasks /Delete /TN LaunchEdgeMain /F 2>$null
        Remove-Item $edgeBatch2 -Force -ErrorAction SilentlyContinue
        Write-Host "Edge relaunched to ADAudit Plus"
    } else {
        Write-Host "WARNING: PyAutoGUI not available - skipping workgroup server addition"

        # Still launch Edge to ADAudit Plus even without PyAutoGUI
        Write-Host "Launching Edge to ADAudit Plus..."
        $edgeBatch2 = "C:\Windows\Temp\launch_edge_main.cmd"
        "@echo off`r`nstart `"`" `"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`" --start-maximized --no-first-run --disable-sync --no-default-browser-check --disable-features=msEdgeOnRampFRE `"http://localhost:8081/`"" | Out-File -FilePath $edgeBatch2 -Encoding ASCII

        $prevEAP3 = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        schtasks /Delete /TN LaunchEdgeMain /F 2>$null
        schtasks /Create /TN LaunchEdgeMain /TR "cmd /c $edgeBatch2" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
        schtasks /Run /TN LaunchEdgeMain 2>$null
        $ErrorActionPreference = $prevEAP3
        Start-Sleep -Seconds 10
        schtasks /Delete /TN LaunchEdgeMain /F 2>$null
        Remove-Item $edgeBatch2 -Force -ErrorAction SilentlyContinue
    }

    # ------------------------------------------------------------------
    # 7. Create desktop shortcut (section renumbered from 6)
    # ------------------------------------------------------------------
    $desktopPath = "C:\Users\Docker\Desktop"
    if (Test-Path $desktopPath) {
        $shortcutPath = "$desktopPath\ADAudit Plus Console.url"
        @"
[InternetShortcut]
URL=http://localhost:8081/
"@ | Out-File -FilePath $shortcutPath -Encoding ASCII
        Write-Host "Desktop shortcut created"
    }

    # ------------------------------------------------------------------
    # 8. Write ready marker
    # ------------------------------------------------------------------
    "OK" | Out-File -FilePath "C:\Windows\Temp\adaudit_ready.marker" -Encoding ASCII -NoNewline
    Write-Host "=== ADAudit Plus environment setup complete ==="

} catch {
    Write-Host "ERROR: $_"
    Write-Host $_.ScriptStackTrace
    throw
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
