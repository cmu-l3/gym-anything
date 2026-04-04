###############################################################################
# install_topocal.ps1 — pre_start hook
# Downloads and installs TopoCal topographic CAD software on Windows 11
# TopoCal 2025 v9.0.961 (InnoSetup installer, installs to Program Files (x86))
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Installing TopoCal ==="

    # -------------------------------------------------------------------------
    # Phase 1: Create working directories
    # -------------------------------------------------------------------------
    Write-Host "--- Phase 1: Creating directories ---"

    $tempDir = "C:\Windows\Temp\topocal_install"
    $desktopDir = "C:\Users\Docker\Desktop"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    New-Item -ItemType Directory -Path $desktopDir -Force | Out-Null

    # -------------------------------------------------------------------------
    # Phase 2: Pre-create firewall rules to suppress dialogs
    # -------------------------------------------------------------------------
    Write-Host "--- Phase 2: Creating firewall rules ---"

    $ErrorActionPreference = "Continue"
    netsh advfirewall firewall add rule name="TopoCal Allow" dir=in action=allow program="C:\Program Files (x86)\TopoCal 2025\TopoCal 2025.exe" 2>$null
    netsh advfirewall firewall add rule name="TopoCal Allow Out" dir=out action=allow program="C:\Program Files (x86)\TopoCal 2025\TopoCal 2025.exe" 2>$null
    $ErrorActionPreference = "Stop"

    # -------------------------------------------------------------------------
    # Phase 3: Obtain TopoCal installer
    # -------------------------------------------------------------------------
    Write-Host "--- Phase 3: Obtaining TopoCal installer ---"

    $installerPath = "$tempDir\TopoCal_Setup.exe"
    $downloaded = $false

    # PRIMARY: Use pre-shipped installer from mounted data (most reliable)
    $mountedInstaller = "C:\workspace\data\topocalsetup.exe"
    if (Test-Path $mountedInstaller) {
        Copy-Item $mountedInstaller $installerPath -Force
        $fileInfo = Get-Item $installerPath
        if ($fileInfo.Length -gt 1MB) {
            Write-Host "Using pre-shipped installer from mount: $($fileInfo.Length) bytes"
            $downloaded = $true
        }
    }

    # FALLBACK: Try downloading from mirrors
    if (-not $downloaded) {
        $urls = @(
            "https://descargas.downloadspg.com/v2/TopoCal_5_0_252.exe",
            "https://www.topocal.com/topocalsetup.exe"
        )

        foreach ($url in $urls) {
            if ($downloaded) { break }
            Write-Host "Trying download: $url"
            try {
                $webClient = New-Object System.Net.WebClient
                $webClient.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                $webClient.DownloadFile($url, $installerPath)
                $fileInfo = Get-Item $installerPath -ErrorAction SilentlyContinue
                if ($fileInfo -and $fileInfo.Length -gt 1MB) {
                    Write-Host "Downloaded successfully: $($fileInfo.Length) bytes"
                    $downloaded = $true
                } else {
                    Write-Host "File too small or missing, trying next URL..."
                    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
                }
            } catch {
                Write-Host "Download failed: $_"
            }
        }
    }

    if (-not $downloaded) {
        throw "Failed to obtain TopoCal installer from all sources"
    }

    # -------------------------------------------------------------------------
    # Phase 4: Install TopoCal (InnoSetup silent install)
    # -------------------------------------------------------------------------
    Write-Host "--- Phase 4: Installing TopoCal ---"

    # TopoCal 2025 is InnoSetup-based, installs to C:\Program Files (x86)\TopoCal 2025\
    Write-Host "Running InnoSetup silent install..."
    $silentArgs = @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-")
    $process = Start-Process -FilePath $installerPath -ArgumentList $silentArgs -PassThru -Wait
    Write-Host "Installer exit code: $($process.ExitCode)"

    # -------------------------------------------------------------------------
    # Phase 5: Verify installation
    # -------------------------------------------------------------------------
    Write-Host "--- Phase 5: Verifying installation ---"

    $installDir = $null
    # TopoCal 2025 installs to "C:\Program Files (x86)\TopoCal 2025\"
    # with executable "TopoCal 2025.exe"
    $searchPaths = @(
        @{ Dir = "C:\Program Files (x86)\TopoCal 2025"; Exe = "TopoCal 2025.exe" },
        @{ Dir = "C:\Program Files\TopoCal 2025"; Exe = "TopoCal 2025.exe" },
        @{ Dir = "C:\Program Files (x86)\TopoCal"; Exe = "TopoCal.exe" },
        @{ Dir = "C:\Program Files\TopoCal"; Exe = "TopoCal.exe" }
    )

    $exeName = $null
    foreach ($sp in $searchPaths) {
        $testPath = Join-Path $sp.Dir $sp.Exe
        if (Test-Path $testPath) {
            $installDir = $sp.Dir
            $exeName = $sp.Exe
            Write-Host "Found TopoCal at: $installDir\$exeName"
            break
        }
    }

    if (-not $installDir) {
        # Broader search for any TopoCal*.exe
        $found = Get-ChildItem -Path "C:\" -Filter "TopoCal*.exe" -Recurse -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -notmatch "unins" } |
                 Select-Object -First 1
        if ($found) {
            $installDir = $found.DirectoryName
            $exeName = $found.Name
            Write-Host "Found TopoCal via search: $($found.FullName)"
        }
    }

    if ($installDir -and $exeName) {
        # Save install path and exe name for other scripts
        Set-Content -Path "C:\Windows\Temp\topocal_install_dir.txt" -Value $installDir
        Set-Content -Path "C:\Windows\Temp\topocal_exe_name.txt" -Value $exeName
        Write-Host "TopoCal install directory: $installDir"
        Write-Host "TopoCal executable: $exeName"
    } else {
        throw "TopoCal executable not found after installation!"
    }

    # -------------------------------------------------------------------------
    # Phase 5b: Install NOP-patched Tpc4_Printer.dll
    # The original DLL has a conditional exit (JZ) at offset 0x6CDE1 that fires
    # during the Lite activation PictureBox click handler. The NOP patch (6×0x90)
    # replaces the JZ instruction so the code always falls through to the
    # activation path, allowing the Lite license check to proceed.
    # -------------------------------------------------------------------------
    Write-Host "--- Phase 5b: Installing NOP-patched Tpc4_Printer.dll ---"

    $patchedDll = "C:\workspace\data\Tpc4_Printer.dll"
    if (Test-Path $patchedDll) {
        $targetDll = Join-Path $installDir "Tpc4_Printer.dll"
        Copy-Item $patchedDll $targetDll -Force
        Write-Host "Installed NOP-patched Tpc4_Printer.dll to $targetDll"
    } else {
        Write-Host "WARNING: Patched DLL not found at $patchedDll"
    }

    # -------------------------------------------------------------------------
    # Phase 5c: Configure hosts file (redirect topocal.com to localhost)
    # The license HTTP server on port 80 handles all topocal.com requests.
    # -------------------------------------------------------------------------
    Write-Host "--- Phase 5c: Configuring hosts file ---"

    $hostsFile = "C:\Windows\System32\drivers\etc\hosts"
    try {
        $hostsContent = [System.IO.File]::ReadAllText($hostsFile)
    } catch {
        $hostsContent = ""
        Write-Host "WARNING: Could not read hosts file: $_"
    }
    if ($hostsContent -notmatch "topocal\.com") {
        try {
            $addition = "`r`n127.0.0.1 topocal.com`r`n127.0.0.1 www.topocal.com"
            [System.IO.File]::AppendAllText($hostsFile, $addition)
            Write-Host "Added topocal.com redirects to hosts file"
        } catch {
            Write-Host "WARNING: Could not modify hosts file: $_"
        }
    } else {
        Write-Host "topocal.com already in hosts file"
    }
    # Flush DNS cache so the new hosts entry takes effect immediately
    $ErrorActionPreference = "Continue"
    ipconfig /flushdns 2>$null
    $ErrorActionPreference = "Stop"
    Write-Host "DNS cache flushed"

    # -------------------------------------------------------------------------
    # Phase 5d: Write license HTTP server script
    # Responds to TopoCal license validation HTTP requests with valid codes.
    #   version19         -> 9.0.961  (same as installed; no update dialog)
    #   contador_25lite   -> *         (Lite activation success response; VB6 p-code validated)
    #   contador_25online -> ok        (online connection confirmed)
    #   contador_25       -> 30        (days remaining)
    #   leermejoras       -> \r\n
    #   fechaoferta       -> 01/01/2020
    # -------------------------------------------------------------------------
    Write-Host "--- Phase 5d: Writing license HTTP server ---"

    $httpServerScript = @'
# TopoCal license HTTP server — listens on port 80
# Intercepts requests via hosts file redirect (127.0.0.1 topocal.com)
$logFile = "C:\Users\Docker\http_server.log"
try {
    Add-Content -Path $logFile -Value "$(Get-Date): HTTP Server starting on port 80"
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://+:80/")
    $listener.Start()
    Add-Content -Path $logFile -Value "$(Get-Date): Listening"
    while ($true) {
        try {
            $ctx = $listener.GetContext()
            $path = $ctx.Request.RawUrl.ToLower()
            Add-Content -Path $logFile -Value "$(Get-Date): GET $path"
            if     ($path -like '*contador_25lite*')   { $bodyStr = '*' }
            elseif ($path -like '*contador_25online*') { $bodyStr = 'ok' }
            elseif ($path -like '*contador_25*')       { $bodyStr = '30' }
            elseif ($path -like '*version19*')         { $bodyStr = '9.0.961' }
            elseif ($path -like '*leermejoras*')       { $bodyStr = "`r`n" }
            elseif ($path -like '*fechaoferta*')       { $bodyStr = '01/01/2020' }
            else                                       { $bodyStr = 'ok' }
            $body = [System.Text.Encoding]::UTF8.GetBytes($bodyStr)
            $ctx.Response.StatusCode = 200
            $ctx.Response.ContentType = 'text/plain'
            $ctx.Response.ContentLength64 = $body.Length
            $ctx.Response.OutputStream.Write($body, 0, $body.Length)
            $ctx.Response.OutputStream.Close()
            Add-Content -Path $logFile -Value "$(Get-Date): >> '$bodyStr'"
        } catch {
            Add-Content -Path $logFile -Value "$(Get-Date): Req error: $_"
            Start-Sleep -Milliseconds 100
        }
    }
} catch {
    Add-Content -Path $logFile -Value "$(Get-Date): FATAL: $_"
}
'@
    Set-Content -Path "C:\Users\Docker\http_server.ps1" -Value $httpServerScript -Encoding UTF8
    Write-Host "License HTTP server written to C:\Users\Docker\http_server.ps1"

    # -------------------------------------------------------------------------
    # Phase 5e: Register startup scheduled tasks
    # HTTPServer  — SYSTEM, at startup (binds port 80)
    # LaunchTC    — Docker, interactive (TopoCal launcher)
    # NOTE: PyAutoGUI server is managed by the gym_anything runner
    #       (windows_pyautogui_server.py) — do NOT register it here.
    # -------------------------------------------------------------------------
    Write-Host "--- Phase 5e: Registering scheduled tasks ---"

    $ErrorActionPreference = "Continue"

    # HTTP Server (SYSTEM, startup, binds port 80)
    $httpAction = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File C:\Users\Docker\http_server.ps1"
    $httpTrigger  = New-ScheduledTaskTrigger -AtStartup
    $httpSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -ExecutionTimeLimit 0
    $httpPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName "HTTPServer" `
        -Action $httpAction -Trigger $httpTrigger `
        -Settings $httpSettings -Principal $httpPrincipal -Force | Out-Null
    Write-Host "Registered HTTPServer task"

    # TopoCal launcher batch file (placeholder — updated by setup_topocal.ps1)
    $installDirForBatch = "C:\Program Files (x86)\TopoCal 2025"
    $exeForBatch = "TopoCal 2025.exe"
    $batchContent = "@echo off`r`ncd /d `"$installDirForBatch`"`r`nstart `"`" `"$exeForBatch`""
    Set-Content -Path "C:\Users\Docker\launch_topocal.bat" -Value $batchContent -Encoding ASCII

    $launchAction = New-ScheduledTaskAction -Execute "C:\Users\Docker\launch_topocal.bat"
    $launchSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries
    $launchPrincipal = New-ScheduledTaskPrincipal -UserId "Docker" -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName "LaunchTC" `
        -Action $launchAction -Settings $launchSettings `
        -Principal $launchPrincipal -Force | Out-Null
    Write-Host "Registered LaunchTC task"

    $ErrorActionPreference = "Stop"

    # -------------------------------------------------------------------------
    # Phase 6: Copy data files to Desktop
    # -------------------------------------------------------------------------
    Write-Host "--- Phase 6: Staging data files ---"

    $dataDir = "C:\Users\Docker\Desktop\SurveyData"
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null

    foreach ($f in @("survey_points.csv", "survey_points_detailed.csv", "contour_map.dxf", "denver_survey.top")) {
        $src = "C:\workspace\data\$f"
        if (Test-Path $src) {
            Copy-Item $src "$dataDir\$f" -Force
            Write-Host "Copied $f to Desktop\SurveyData"
        }
    }

    # -------------------------------------------------------------------------
    # Phase 7: Create Desktop shortcut
    # -------------------------------------------------------------------------
    Write-Host "--- Phase 7: Creating desktop shortcut ---"

    $shortcutPath = "$desktopDir\TopoCal 2025.lnk"
    $exePath = Join-Path $installDir $exeName

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $exePath
        $shortcut.WorkingDirectory = $installDir
        $shortcut.Description = "TopoCal 2025 Topographic CAD"
        $shortcut.Save()
        Write-Host "Desktop shortcut created: $shortcutPath"
    } catch {
        Write-Host "WARNING: Could not create shortcut: $_"
    }

    # -------------------------------------------------------------------------
    # Phase 8: Cleanup
    # -------------------------------------------------------------------------
    Write-Host "--- Phase 8: Cleanup ---"
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    Set-Content -Path "C:\Windows\Temp\topocal_install_complete.marker" -Value "$(Get-Date)"

    Write-Host "=== TopoCal installation complete ==="

} catch {
    Write-Host "FATAL ERROR during installation: $_"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
