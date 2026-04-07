Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing SketchUp Make 2017 + Skelion Solar Plugin ==="

    $tempDir = "C:\temp\skelion_install"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop" | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\temp" | Out-Null

    # Force TLS 1.2 for all web requests
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # -------------------------------------------------------------------
    # 1. Download and install SketchUp Make 2017
    #    Prefer the pre-downloaded copy in /workspace/data/ (mounted from
    #    examples/skelion_env/data/) to avoid slow archive.org downloads.
    # -------------------------------------------------------------------
    Write-Host "--- Obtaining SketchUp Make 2017 ---"

    $sketchupInstaller = "$tempDir\SketchUpMake2017.exe"
    $sketchupDownloaded = $false

    # Check for pre-mounted installer first (fastest path)
    $localCopy = "C:\workspace\data\SketchUpMake2017.exe"
    if ((Test-Path $localCopy) -and (Get-Item $localCopy).Length -gt 10MB) {
        Write-Host "Using pre-mounted SketchUp installer: $localCopy"
        Copy-Item $localCopy $sketchupInstaller -Force
        $sketchupDownloaded = $true
    }

    # Fall back to download if no local copy
    if (-not $sketchupDownloaded) {
        Write-Host "No local installer found, downloading..."
        $sketchupUrls = @(
            "https://archive.org/download/sketchupmake-2017-2-2555-90782-en-x64/sketchupmake-2017-2-2555-90782-en-x64.exe",
            "https://archive.org/download/sketchupmake2017/SketchUpMake-2017-2-2555-90782-en-x64.exe"
        )

        foreach ($url in $sketchupUrls) {
            try {
                Write-Host "Trying SketchUp download: $url"
                Invoke-WebRequest -Uri $url -OutFile $sketchupInstaller -UseBasicParsing -TimeoutSec 600
                if ((Test-Path $sketchupInstaller) -and (Get-Item $sketchupInstaller).Length -gt 10MB) {
                    Write-Host "SketchUp downloaded ($([math]::Round((Get-Item $sketchupInstaller).Length/1MB,1)) MB)"
                    $sketchupDownloaded = $true
                    break
                }
            } catch {
                Write-Host "Failed from $url : $($_.Exception.Message)"
            }
        }
    }

    if (-not $sketchupDownloaded) {
        throw "ERROR: Could not obtain SketchUp Make 2017."
    }

    Write-Host "--- Installing SketchUp Make 2017 silently ---"

    # SketchUp Make 2017 is a 7z self-extracting archive that launches setup.exe.
    # The installer requires an interactive desktop session (Session 1) to run —
    # it hangs indefinitely in Session 0 (SSH). Use schtasks /IT to run in Session 1.
    $installBat = "C:\temp\install_sketchup.bat"
    $installLog = "C:\temp\sketchup_install_done.flag"
    Remove-Item $installLog -Force -ErrorAction SilentlyContinue
    $batContent = @"
@echo off
"$sketchupInstaller" /S
echo %ERRORLEVEL% > "$installLog"
"@
    Set-Content -Path $installBat -Value $batContent -Encoding ASCII

    # Run via schtasks /IT so it executes in the interactive VNC session
    # Temporarily relax error handling — schtasks returns non-zero on "task not found"
    $prevEAP_inst = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    schtasks /Delete /TN "InstallSU" /F 2>&1 | Out-Null
    schtasks /Create /TN "InstallSU" /TR $installBat /SC ONCE /ST "00:00" /RL HIGHEST /IT /F 2>&1 | Out-Null
    schtasks /Run /TN "InstallSU" 2>&1 | Out-Null
    $ErrorActionPreference = $prevEAP_inst
    Write-Host "SketchUp installer launched in interactive session via schtasks"

    # The outer EXE is a 7z self-extractor — it returns immediately after launching
    # the inner setup.exe. Wait for SketchUp.exe to appear on disk (up to 10 minutes).
    $installTimeout = 600
    $elapsed = 0
    $suInstalled = $false
    $suCheckPaths = @(
        "C:\Program Files\SketchUp\SketchUp 2017\SketchUp.exe",
        "C:\Program Files (x86)\SketchUp\SketchUp 2017\SketchUp.exe"
    )
    while (-not $suInstalled -and $elapsed -lt $installTimeout) {
        Start-Sleep -Seconds 10
        $elapsed += 10
        foreach ($chk in $suCheckPaths) {
            if (Test-Path $chk) { $suInstalled = $true; break }
        }
        if ($elapsed % 30 -eq 0) { Write-Host "  Waiting for SketchUp install... ($elapsed s)" }
    }

    # Also wait for setup.exe to finish (it may still be configuring)
    if ($suInstalled) {
        $setupWait = 0
        while ($setupWait -lt 120) {
            $setupProcs = Get-Process -Name "setup" -ErrorAction SilentlyContinue
            if (-not $setupProcs) { break }
            Start-Sleep -Seconds 5
            $setupWait += 5
        }
        Write-Host "SketchUp installed successfully after $elapsed seconds"
    } else {
        Write-Host "WARNING: SketchUp install timed out after $installTimeout seconds"
    }

    $ErrorActionPreference = "Continue"
    schtasks /Delete /TN "InstallSU" /F 2>&1 | Out-Null
    $ErrorActionPreference = $prevEAP_inst

    $suPaths = @(
        "C:\Program Files\SketchUp\SketchUp 2017\SketchUp.exe",
        "C:\Program Files (x86)\SketchUp\SketchUp 2017\SketchUp.exe"
    )
    $suExe = $null
    foreach ($p in $suPaths) {
        if (Test-Path $p) { $suExe = $p; break }
    }
    if (-not $suExe) {
        $suExe = Get-ChildItem "C:\Program Files","C:\Program Files (x86)" -Recurse -Filter "SketchUp.exe" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match "2017" } | Select-Object -First 1 -ExpandProperty FullName
    }
    if ($suExe) {
        Write-Host "SketchUp found at: $suExe"
        Set-Content "C:\Users\Docker\sketchup_path.txt" $suExe -Encoding UTF8
    } else {
        Write-Host "WARNING: SketchUp.exe not found after install."
    }

    # -------------------------------------------------------------------
    # 2. Download and install Skelion plugin
    #    Prefer the pre-mounted copy in /workspace/data/ to avoid network issues.
    # -------------------------------------------------------------------
    Write-Host "--- Obtaining Skelion plugin ---"

    $skelionRbz = "$tempDir\Skelion.rbz"
    $skelionDownloaded = $false

    # Check for pre-mounted plugin
    $localSkelion = "C:\workspace\data\Skelion.rbz"
    if ((Test-Path $localSkelion) -and (Get-Item $localSkelion).Length -gt 10KB) {
        Write-Host "Using pre-mounted Skelion plugin: $localSkelion"
        Copy-Item $localSkelion $skelionRbz -Force
        $skelionDownloaded = $true
    }

    # Fall back to download
    if (-not $skelionDownloaded) {
        $skelionUrls = @(
            "https://skelion.com/en/Skelion_skelion_v5.5.2.rbz",
            "https://skelion.com/files/Skelion_skelion_v5.5.2.rbz",
            "https://skelion.com/Skelion_skelion_v5.5.2.rbz"
        )

        foreach ($url in $skelionUrls) {
            try {
                Write-Host "Trying Skelion download: $url"
                Invoke-WebRequest -Uri $url -OutFile $skelionRbz -UseBasicParsing -TimeoutSec 120
                if ((Test-Path $skelionRbz) -and (Get-Item $skelionRbz).Length -gt 10KB) {
                    Write-Host "Skelion downloaded ($([math]::Round((Get-Item $skelionRbz).Length/1KB,1)) KB)"
                    $skelionDownloaded = $true
                    break
                }
            } catch {
                Write-Host "Failed from $url : $($_.Exception.Message)"
            }
        }
    }

    if (-not $skelionDownloaded) {
        Write-Host "WARNING: Could not download Skelion. Continuing without it."
    } else {
        $pluginsDir = "C:\Users\Docker\AppData\Roaming\SketchUp\SketchUp 2017\SketchUp\Plugins"
        New-Item -ItemType Directory -Force -Path $pluginsDir | Out-Null

        $skelionZip = "$tempDir\Skelion.zip"
        Copy-Item $skelionRbz $skelionZip -Force

        $extractDir = "$tempDir\skelion_extracted"
        New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        Expand-Archive -Path $skelionZip -DestinationPath $extractDir -Force 2>&1 | ForEach-Object { Write-Host $_ }
        $ErrorActionPreference = $prevEAP

        Get-ChildItem $extractDir -Recurse | ForEach-Object {
            $relPath = $_.FullName.Substring($extractDir.Length + 1)
            $destPath = Join-Path $pluginsDir $relPath
            if ($_.PSIsContainer) {
                New-Item -ItemType Directory -Force -Path $destPath | Out-Null
            } else {
                New-Item -ItemType Directory -Force -Path (Split-Path $destPath -Parent) | Out-Null
                Copy-Item $_.FullName $destPath -Force
            }
        }
        Write-Host "Skelion installed to: $pluginsDir"
    }

    # -------------------------------------------------------------------
    # 3. Install Python 3.11 + PyAutoGUI
    # -------------------------------------------------------------------
    Write-Host "--- Checking Python installation ---"

    $pythonExe = $null
    $existingPython = Get-Command python -ErrorAction SilentlyContinue
    if ($existingPython) {
        $pythonExe = $existingPython.Source
        Write-Host "Python already installed: $pythonExe"
    } else {
        Write-Host "Installing Python 3.11..."
        $pyUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
        $pyInstaller = "$tempDir\python-3.11.9-amd64.exe"
        Invoke-WebRequest -Uri $pyUrl -OutFile $pyInstaller -UseBasicParsing -TimeoutSec 300
        Start-Process $pyInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_pip=1" -Wait
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        $pythonExe = "C:\Program Files\Python311\python.exe"
        if (-not (Test-Path $pythonExe)) { $pythonExe = "C:\Python311\python.exe" }
        Write-Host "Python installed at: $pythonExe"
    }

    if ($pythonExe -and (Test-Path $pythonExe)) {
        $prevEAP2 = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & $pythonExe -m pip install --quiet pyautogui pillow pywin32 2>&1 | ForEach-Object { Write-Host $_ }
        $ErrorActionPreference = $prevEAP2
        Write-Host "PyAutoGUI and dependencies installed"
    }

    # -------------------------------------------------------------------
    # 4. CRITICAL: Set ANGLE OpenGL backend for CEF rendering
    #    SketchUp's License dialog uses CEF (Chromium Embedded Framework)
    #    which tries to use D3D11 for rendering. On VirtIO GPU VMs, D3D11
    #    initialization hangs indefinitely. Setting ANGLE_DEFAULT_PLATFORM=gl
    #    forces CEF to use Mesa3D software OpenGL instead, which works reliably.
    # -------------------------------------------------------------------
    Write-Host "--- Configuring GPU/rendering environment for VirtIO compatibility ---"

    # Force ANGLE to use OpenGL backend (uses Mesa3D software renderer via WGL)
    [System.Environment]::SetEnvironmentVariable("ANGLE_DEFAULT_PLATFORM", "gl", "Machine")
    # Ensure Mesa3D software OpenGL is used (already in SketchUp dir as opengl32.dll/libgallium_wgl.dll)
    [System.Environment]::SetEnvironmentVariable("LIBGL_ALWAYS_SOFTWARE", "1", "Machine")
    [System.Environment]::SetEnvironmentVariable("GALLIUM_DRIVER", "softpipe", "Machine")
    # Remove conflicting D3D11 env var if previously set
    [System.Environment]::SetEnvironmentVariable("ANGLE_D3D11_FEATURE_LEVEL_11_0", $null, "Machine")
    Write-Host "ANGLE_DEFAULT_PLATFORM=gl set (forces software OpenGL for CEF)"

    # -------------------------------------------------------------------
    # 5. Add firewall rules to block SketchUp from reaching license servers
    #    This prevents the License dialog CEF from hanging on network timeout.
    #    Blocking only remote (Internet) connections; loopback IPC still works.
    # -------------------------------------------------------------------
    Write-Host "--- Adding firewall rules to block SketchUp license verification ---"

    $prevEAP3 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    # Remove any previous rules
    Remove-NetFirewallRule -DisplayName "Block SketchUp WebHelper HTTPS" -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName "Block SketchUp HTTPS" -ErrorAction SilentlyContinue

    # Block outbound HTTP/HTTPS from sketchup_webhelper.exe (CEF renderer)
    $webHelper = "C:\Program Files\SketchUp\SketchUp 2017\sketchup_webhelper.exe"
    if (Test-Path $webHelper) {
        New-NetFirewallRule -DisplayName "Block SketchUp WebHelper HTTPS" `
            -Direction Outbound -Program $webHelper `
            -Protocol TCP -RemotePort 80,443 -RemoteAddress Internet `
            -Action Block -Enabled True | Out-Null
        Write-Host "Firewall: blocked sketchup_webhelper.exe outbound HTTP/HTTPS"
    }

    # Block outbound HTTP/HTTPS from SketchUp.exe main process
    if ($suExe -and (Test-Path $suExe)) {
        New-NetFirewallRule -DisplayName "Block SketchUp HTTPS" `
            -Direction Outbound -Program $suExe `
            -Protocol TCP -RemotePort 80,443 -RemoteAddress Internet `
            -Action Block -Enabled True | Out-Null
        Write-Host "Firewall: blocked SketchUp.exe outbound HTTP/HTTPS"
    }
    $ErrorActionPreference = $prevEAP3

    # -------------------------------------------------------------------
    # 6. Create building model Ruby startup script
    #    Creates a realistic flat-roof commercial building on SketchUp startup.
    #    The building has a main section + annex wing (L-shape) with parapet
    #    walls and rooftop HVAC unit — more realistic than a plain box.
    # -------------------------------------------------------------------
    Write-Host "--- Creating SketchUp building model startup script ---"

    $pluginsDir2 = "C:\Users\Docker\AppData\Roaming\SketchUp\SketchUp 2017\SketchUp\Plugins"
    New-Item -ItemType Directory -Force -Path $pluginsDir2 | Out-Null

    $rubyScript = @'
# auto_create_solar_building.rb
# Creates a realistic flat-roof commercial building for solar panel design.
# Only runs once — skips if Solar_Project.skp already exists.

SOLAR_PROJECT_FILE = "C:/Users/Docker/Desktop/Solar_Project.skp"
SOLAR_PROJECT_CREATED = "C:/Users/Docker/solar_project_created.flag"

def create_solar_building
  return if File.exist?(SOLAR_PROJECT_CREATED)

  model = Sketchup.active_model
  return unless model

  begin
    model.start_operation("Create Solar Building", true)
    model.entities.clear!

    ents = model.entities

    # ----- Main building block: 20m wide x 15m deep x 4.5m tall -----
    mw = 20.m; md = 15.m; mh = 4.5.m

    # Ground footprint
    base_pts = [
      Geom::Point3d.new(0, 0, 0),
      Geom::Point3d.new(mw, 0, 0),
      Geom::Point3d.new(mw, md, 0),
      Geom::Point3d.new(0, md, 0)
    ]
    base_face = ents.add_face(base_pts)
    base_face.reverse! if base_face.normal.z < 0
    base_face.pushpull(mh)

    # Parapet walls on main building roof (0.4m tall, 0.2m thick)
    ph = 0.4.m; pt = 0.2.m
    # North parapet
    np_pts = [
      Geom::Point3d.new(0, md - pt, mh),
      Geom::Point3d.new(mw, md - pt, mh),
      Geom::Point3d.new(mw, md, mh),
      Geom::Point3d.new(0, md, mh)
    ]
    np_face = ents.add_face(np_pts)
    np_face.reverse! if np_face.normal.z < 0
    np_face.pushpull(ph)

    # South parapet
    sp_pts = [
      Geom::Point3d.new(0, 0, mh),
      Geom::Point3d.new(mw, 0, mh),
      Geom::Point3d.new(mw, pt, mh),
      Geom::Point3d.new(0, pt, mh)
    ]
    sp_face = ents.add_face(sp_pts)
    sp_face.reverse! if sp_face.normal.z < 0
    sp_face.pushpull(ph)

    # East parapet
    ep_pts = [
      Geom::Point3d.new(mw - pt, pt, mh),
      Geom::Point3d.new(mw, pt, mh),
      Geom::Point3d.new(mw, md - pt, mh),
      Geom::Point3d.new(mw - pt, md - pt, mh)
    ]
    ep_face = ents.add_face(ep_pts)
    ep_face.reverse! if ep_face.normal.z < 0
    ep_face.pushpull(ph)

    # West parapet
    wp_pts = [
      Geom::Point3d.new(0, pt, mh),
      Geom::Point3d.new(pt, pt, mh),
      Geom::Point3d.new(pt, md - pt, mh),
      Geom::Point3d.new(0, md - pt, mh)
    ]
    wp_face = ents.add_face(wp_pts)
    wp_face.reverse! if wp_face.normal.z < 0
    wp_face.pushpull(ph)

    # HVAC unit on roof: 3m x 2m x 1.2m, placed at NE corner of roof
    hw = 3.m; hd = 2.m; hh = 1.2.m
    hvac_x = mw - hw - 1.m; hvac_y = md - hd - 1.m
    hvac_pts = [
      Geom::Point3d.new(hvac_x, hvac_y, mh),
      Geom::Point3d.new(hvac_x + hw, hvac_y, mh),
      Geom::Point3d.new(hvac_x + hw, hvac_y + hd, mh),
      Geom::Point3d.new(hvac_x, hvac_y + hd, mh)
    ]
    hvac_face = ents.add_face(hvac_pts)
    hvac_face.reverse! if hvac_face.normal.z < 0
    hvac_face.pushpull(hh)

    # Stairwell access on roof: 2m x 2m x 2.5m at SW corner
    sh = 2.5.m; sw = 2.m
    stair_pts = [
      Geom::Point3d.new(1.m, 1.m, mh),
      Geom::Point3d.new(1.m + sw, 1.m, mh),
      Geom::Point3d.new(1.m + sw, 1.m + sw, mh),
      Geom::Point3d.new(1.m, 1.m + sw, mh)
    ]
    stair_face = ents.add_face(stair_pts)
    stair_face.reverse! if stair_face.normal.z < 0
    stair_face.pushpull(sh)

    # Store building metadata (no geo-location — set_location task should start blank)
    model.set_attribute("SolarProject", "BuildingType", "Commercial")
    model.set_attribute("SolarProject", "RoofArea_m2", (mw - 2*pt) * (md - 2*pt))

    # Orient camera for good isometric roof view
    eye = Geom::Point3d.new(mw * 2.0, -md * 0.8, mh * 3.5)
    target = Geom::Point3d.new(mw / 2, md / 2, mh)
    up = Geom::Vector3d.new(0, 0, 1)
    model.active_view.camera.set(eye, target, up)
    model.active_view.zoom_extents

    model.commit_operation

    # Save to Desktop
    model.save(SOLAR_PROJECT_FILE)
    File.open(SOLAR_PROJECT_CREATED, 'w') { |f| f.write(Time.now.to_s) }

    puts "Solar Project building created: #{SOLAR_PROJECT_FILE}"
    puts "Building: 20mx15m main section, 4.5m height, parapet walls, HVAC unit, stairwell access"
  rescue => e
    model.abort_operation rescue nil
    puts "Error creating solar building: #{e.message}"
    puts e.backtrace.join("\n")
  end
end

UI.start_timer(3.0, false) { create_solar_building }
'@

    $rubyScriptPath = Join-Path $pluginsDir2 "auto_create_solar_building.rb"
    [System.IO.File]::WriteAllText($rubyScriptPath, $rubyScript, [System.Text.Encoding]::UTF8)
    Write-Host "Ruby startup script created at: $rubyScriptPath"

    # -------------------------------------------------------------------
    # 7. Create desktop shortcut for SketchUp
    # -------------------------------------------------------------------
    if ($suExe) {
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut("C:\Users\Docker\Desktop\SketchUp Make 2017.lnk")
        $shortcut.TargetPath = $suExe
        $shortcut.WorkingDirectory = Split-Path $suExe -Parent
        $shortcut.Save()
        Write-Host "Desktop shortcut created"
    }

    Write-Host "=== SketchUp Make 2017 + Skelion Installation Complete ==="

} catch {
    Write-Host "FATAL ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    throw
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
