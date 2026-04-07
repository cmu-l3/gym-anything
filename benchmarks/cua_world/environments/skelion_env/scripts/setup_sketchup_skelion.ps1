Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

# Helper: send one JSON command to the PyAutoGUI TCP server on port 5555
function Send-GUI {
    param([string]$Json, [int]$TimeoutMs = 5000)
    try {
        $sock = New-Object System.Net.Sockets.TcpClient
        $iar  = $sock.BeginConnect("127.0.0.1", 5555, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { $sock.Close(); return $null }
        $sock.EndConnect($iar)
        $stream = $sock.GetStream()
        $bytes  = [System.Text.Encoding]::ASCII.GetBytes($Json + "`n")
        $stream.Write($bytes, 0, $bytes.Length)
        $buf  = New-Object byte[] 4096
        $n    = $stream.Read($buf, 0, 4096)
        $resp = [System.Text.Encoding]::ASCII.GetString($buf, 0, $n)
        $sock.Close()
        return $resp
    } catch { return $null }
}

try {
    Write-Host "=== Setting up SketchUp Make 2017 + Skelion Environment ==="

    # -------------------------------------------------------------------
    # 1. Find SketchUp executable
    # -------------------------------------------------------------------
    Write-Host "--- Locating SketchUp ---"

    $suExe = $null
    $savedPath = "C:\Users\Docker\sketchup_path.txt"
    if (Test-Path $savedPath) {
        $suExe = (Get-Content $savedPath -Raw).Trim()
        if (-not (Test-Path $suExe)) { $suExe = $null }
    }
    if (-not $suExe) {
        $suExe = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse -Filter "SketchUp.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "2017" } | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $suExe) {
        throw "SketchUp.exe not found. Installation may have failed."
    }
    Write-Host "SketchUp found at: $suExe"

    # -------------------------------------------------------------------
    # 2. Set registry keys to suppress SketchUp first-run dialogs
    # -------------------------------------------------------------------
    Write-Host "--- Configuring SketchUp registry settings ---"

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $suRegBase = "HKCU:\SOFTWARE\SketchUp\SketchUp 2017"
    @("$suRegBase", "$suRegBase\Common", "$suRegBase\Preferences", "$suRegBase\Licenses") |
        ForEach-Object { if (-not (Test-Path $_)) { New-Item -Path $_ -Force 2>$null | Out-Null } }

    New-ItemProperty -Path "$suRegBase\Common"       -Name "AcceptedEULA"       -Value 1      -PropertyType DWord  -Force 2>$null | Out-Null
    New-ItemProperty -Path "$suRegBase\Preferences"  -Name "CheckForUpdates"    -Value 0      -PropertyType DWord  -Force 2>$null | Out-Null
    New-ItemProperty -Path "$suRegBase\Common"       -Name "WelcomeScreenShown" -Value 1      -PropertyType DWord  -Force 2>$null | Out-Null
    New-ItemProperty -Path "$suRegBase\Common"       -Name "LicenseType"        -Value "Make" -PropertyType String -Force 2>$null | Out-Null

    $ErrorActionPreference = $prevEAP
    Write-Host "Registry keys set"

    # -------------------------------------------------------------------
    # 3. Pre-create SketchUp user data directories
    # -------------------------------------------------------------------
    $suUserBase = "C:\Users\Docker\AppData\Roaming\SketchUp\SketchUp 2017\SketchUp"
    New-Item -ItemType Directory -Force -Path "$suUserBase\Plugins"    | Out-Null
    New-Item -ItemType Directory -Force -Path "$suUserBase\Components"  | Out-Null
    New-Item -ItemType Directory -Force -Path "$suUserBase\Styles"      | Out-Null
    Write-Host "SketchUp user directories created"

    # -------------------------------------------------------------------
    # 4. Set default template in registry
    # -------------------------------------------------------------------
    Write-Host "--- Setting default SketchUp template ---"

    $templateDirs = @(
        "C:\ProgramData\SketchUp\SketchUp 2017\Resources\en-US\Templates",
        "C:\Program Files\SketchUp\SketchUp 2017\Resources\en-US\Templates",
        "C:\Program Files (x86)\SketchUp\SketchUp 2017\Resources\en-US\Templates"
    )

    $defaultTemplate = $null
    foreach ($dir in $templateDirs) {
        if (Test-Path $dir) {
            $tmpl = Get-ChildItem $dir -Filter "*.skp" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "Architect|Simple|Plan" } | Select-Object -First 1
            if (-not $tmpl) {
                $tmpl = Get-ChildItem $dir -Filter "*.skp" -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            if ($tmpl) { $defaultTemplate = $tmpl.FullName; break }
        }
    }

    if ($defaultTemplate) {
        $prevEAP2 = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        New-ItemProperty -Path "$suRegBase\Preferences" -Name "DefaultTemplate" -Value $defaultTemplate -PropertyType String -Force 2>$null | Out-Null
        $ErrorActionPreference = $prevEAP2
        Write-Host "Default template set: $defaultTemplate"
    } else {
        Write-Host "No template found; SketchUp will use built-in default"
    }

    # -------------------------------------------------------------------
    # 5. Create batch file wrapper for launching SketchUp
    #    schtasks /TR cannot handle paths with spaces; using a .bat wrapper
    #    avoids the quoting problem.
    # -------------------------------------------------------------------
    Write-Host "--- Creating launch batch wrapper ---"

    New-Item -ItemType Directory -Force -Path "C:\temp" | Out-Null
    $batPath = "C:\temp\launch_su_warmup.bat"
    Set-Content -Path $batPath -Value "@echo off`r`nstart `"`" `"$suExe`"" -Encoding ASCII
    Write-Host "Batch wrapper: $batPath"

    # -------------------------------------------------------------------
    # 6. Warm-up launch: load Skelion plugin, create Solar_Project.skp,
    #    and dismiss all first-run dialogs.
    #
    #    Dialog sequence (confirmed via interactive testing):
    #      a) Welcome screen with "Start using SketchUp" button (~25s to appear)
    #      b) Template selection dialog → press Enter for default
    #      c) SketchUp workspace loads (~15s more)
    #      d) 2D Bool plugin dialog (if present) at (277, 123)
    #      e) Skelion EULA dialog — Accept button at (191, 396)
    #      f) Skelion notification dialog — OK button at (793, 326)
    #      g) Ruby timer fires after 3s: Solar_Project.skp created on Desktop
    # -------------------------------------------------------------------
    Write-Host "--- Warm-up launch of SketchUp to initialize Skelion and create building model ---"

    $taskName = "SketchUp_Warmup"
    $prevEAP3 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    # Kill any stale SketchUp
    Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    schtasks /Delete /TN $taskName /F 2>$null
    schtasks /Create /TN $taskName /TR $batPath /SC ONCE /ST "00:00" /RL HIGHEST /IT /F 2>$null
    schtasks /Run    /TN $taskName 2>$null
    Write-Host "SketchUp launched via schtasks"

    # Wait for Welcome screen to appear (CEF renders it after ~20-25s on first launch)
    Write-Host "Waiting 25s for Welcome screen..."
    Start-Sleep -Seconds 25

    # Click "Start using SketchUp" button
    Write-Host "Clicking 'Start using SketchUp'..."
    Send-GUI '{"action":"click","x":949,"y":669}' | Out-Null
    Start-Sleep -Seconds 3

    # Press Enter to accept default template (template selection dialog)
    Write-Host "Accepting default template..."
    Send-GUI '{"action":"press","key":"return"}' | Out-Null
    Start-Sleep -Seconds 2
    Send-GUI '{"action":"press","key":"return"}' | Out-Null

    # Wait for SketchUp workspace to fully load
    Write-Host "Waiting 20s for SketchUp workspace to load..."
    Start-Sleep -Seconds 20

    # Dismiss 2D Bool plugin dialog (close button at top-right of dialog)
    Write-Host "Dismissing 2D Bool dialog (if present)..."
    Send-GUI '{"action":"click","x":277,"y":123}' | Out-Null
    Start-Sleep -Milliseconds 800

    # Accept Skelion EULA dialog
    Write-Host "Accepting Skelion EULA (if present)..."
    Send-GUI '{"action":"click","x":191,"y":396}' | Out-Null
    Start-Sleep -Milliseconds 800

    # Dismiss Skelion notification dialog
    Write-Host "Dismissing Skelion notification (if present)..."
    Send-GUI '{"action":"click","x":793,"y":326}' | Out-Null
    Start-Sleep -Milliseconds 800

    # Click workspace to clear any remaining focus issues
    Send-GUI '{"action":"click","x":640,"y":400}' | Out-Null
    Start-Sleep -Seconds 1

    # Wait for Ruby plugin timer to fire and create Solar_Project.skp
    Write-Host "Waiting for Ruby plugin to create Solar_Project.skp..."
    $buildingCreated = $false
    for ($w = 0; $w -lt 18; $w++) {
        if (Test-Path "C:\Users\Docker\Desktop\Solar_Project.skp") {
            $buildingCreated = $true
            Write-Host "Solar_Project.skp created! ($($w * 5)s elapsed)"
            break
        }
        Start-Sleep -Seconds 5
        Write-Host "Waiting... ($($w * 5 + 5)s elapsed)"
    }

    if (-not $buildingCreated) {
        Write-Host "WARNING: Solar_Project.skp not auto-created within 90s."
        Write-Host "This may indicate the Ruby plugin did not run."
        Write-Host "Tasks will attempt to create it on first run."
    }

    # Save the model (Ctrl+S) — ensures SketchUp registers the file path in MRU
    Write-Host "Saving model..."
    Send-GUI '{"action":"hotkey","keys":["ctrl","s"]}' | Out-Null
    Start-Sleep -Seconds 3
    # Dismiss "Save As" dialog if it appeared (for unsaved new model)
    Send-GUI '{"action":"press","key":"return"}' | Out-Null
    Start-Sleep -Seconds 2

    # Close SketchUp gracefully (Alt+F4)
    Write-Host "Closing SketchUp..."
    Send-GUI '{"action":"hotkey","keys":["alt","F4"]}' | Out-Null
    Start-Sleep -Seconds 4

    # Force-kill if still running
    Get-Process SketchUp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    schtasks /Delete /TN $taskName /F 2>$null
    $ErrorActionPreference = $prevEAP3

    # -------------------------------------------------------------------
    # 7. Disable Edge auto-start and clean up browsers
    # -------------------------------------------------------------------
    Write-Host "--- Disabling Edge auto-start ---"
    $ErrorActionPreference = "Continue"

    $edgeRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if (-not (Test-Path $edgeRegPath)) { New-Item -Path $edgeRegPath -Force 2>$null | Out-Null }
    New-ItemProperty -Path $edgeRegPath -Name "StartupBoostEnabled"  -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
    New-ItemProperty -Path $edgeRegPath -Name "BackgroundModeEnabled" -Value 0 -PropertyType DWord -Force 2>$null | Out-Null
    New-ItemProperty -Path $edgeRegPath -Name "RestoreOnStartup"      -Value 5 -PropertyType DWord -Force 2>$null | Out-Null

    $edgeUserData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    if (Test-Path $edgeUserData) {
        Get-ChildItem $edgeUserData -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            foreach ($f in @("Current Session", "Current Tabs", "Last Session", "Last Tabs")) {
                Remove-Item (Join-Path $_.FullName $f) -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    taskkill /F /IM OneDrive.exe 2>$null

    for ($k = 0; $k -lt 5; $k++) {
        taskkill /F /IM msedge.exe 2>$null
        Start-Sleep -Seconds 1
    }

    $ErrorActionPreference = "Stop"

    # -------------------------------------------------------------------
    # 8. Verify installation
    # -------------------------------------------------------------------
    Write-Host "--- Verification ---"
    Write-Host "SketchUp exe:         $(Test-Path $suExe)"
    Write-Host "Solar_Project.skp:    $(Test-Path 'C:\Users\Docker\Desktop\Solar_Project.skp')"

    $pluginsDir = "C:\Users\Docker\AppData\Roaming\SketchUp\SketchUp 2017\SketchUp\Plugins"
    Write-Host "Skelion installed:    $(Test-Path "$pluginsDir\skelion.rb")"

    Write-Host "=== SketchUp Make 2017 + Skelion Setup Complete ==="

} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
