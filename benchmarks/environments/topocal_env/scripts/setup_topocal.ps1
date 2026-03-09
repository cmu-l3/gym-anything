###############################################################################
# setup_topocal.ps1 — post_start hook
# Configures TopoCal: starts HTTP server + PyAutoGUI server, sets activation
# bypass registry, performs warm-up launch to handle the activation dialog.
###############################################################################

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch {}

try {
    Write-Host "=== Setting up TopoCal ==="

    # -------------------------------------------------------------------------
    # Section 1: Find install directory
    # -------------------------------------------------------------------------
    Write-Host "--- Section 1: Finding install directory ---"

    $installDir = $null
    $exeName = "TopoCal 2025.exe"
    $markerFile = "C:\Windows\Temp\topocal_install_dir.txt"
    $exeMarkerFile = "C:\Windows\Temp\topocal_exe_name.txt"

    if (Test-Path $markerFile) {
        $installDir = (Get-Content $markerFile -Raw).Trim()
        if (Test-Path $exeMarkerFile) { $exeName = (Get-Content $exeMarkerFile -Raw).Trim() }
        if (-not (Test-Path (Join-Path $installDir $exeName))) { $installDir = $null }
    }

    if (-not $installDir) {
        $searchPaths = @(
            "C:\Program Files (x86)\TopoCal 2025",
            "C:\Program Files\TopoCal 2025",
            "C:\Program Files (x86)\TopoCal",
            "C:\Program Files\TopoCal"
        )
        foreach ($sp in $searchPaths) {
            $candidates = Get-ChildItem $sp -Filter "TopoCal*.exe" -ErrorAction SilentlyContinue |
                          Where-Object { $_.Name -notmatch "unins" }
            if ($candidates) { $installDir = $sp; $exeName = $candidates[0].Name; break }
        }
    }

    if ($installDir) {
        Write-Host "TopoCal install directory: $installDir"
        Set-Content -Path $markerFile -Value $installDir
        Set-Content -Path $exeMarkerFile -Value $exeName
    } else {
        Write-Host "WARNING: TopoCal not found, using default path"
        $installDir = "C:\Program Files (x86)\TopoCal 2025"
    }
    $exePath = Join-Path $installDir $exeName

    # -------------------------------------------------------------------------
    # Section 2: Start license HTTP server (port 80)
    # Registered as scheduled task "HTTPServer" by install_topocal.ps1.
    # -------------------------------------------------------------------------
    Write-Host "--- Section 2: Starting license HTTP server ---"

    $ErrorActionPreference = "Continue"
    Start-ScheduledTask -TaskName "HTTPServer" -ErrorAction SilentlyContinue
    $ErrorActionPreference = "Stop"
    Start-Sleep -Seconds 4

    # Verify port 80 is listening
    for ($i = 0; $i -lt 10; $i++) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect("127.0.0.1", 80)
            $tcp.Close()
            Write-Host "License HTTP server confirmed on port 80"
            break
        } catch {
            if ($i -eq 9) { Write-Host "WARNING: Port 80 not yet responding" }
            Start-Sleep -Seconds 2
        }
    }

    # -------------------------------------------------------------------------
    # Section 3: Start PyAutoGUI server (port 5555)
    # -------------------------------------------------------------------------
    Write-Host "--- Section 3: Starting PyAutoGUI server ---"

    $ErrorActionPreference = "Continue"
    Start-ScheduledTask -TaskName "PyAutoGUIServer" -ErrorAction SilentlyContinue
    $ErrorActionPreference = "Stop"
    Start-Sleep -Seconds 5

    $pyagPort = 5555
    $pyagConnected = $false
    for ($i = 0; $i -lt 20; $i++) {
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $tcpClient.Connect("127.0.0.1", $pyagPort)
            $tcpClient.Close()
            $pyagConnected = $true
            Write-Host "PyAutoGUI server available on port $pyagPort"
            break
        } catch {
            Start-Sleep -Seconds 2
        }
    }
    if (-not $pyagConnected) { Write-Host "WARNING: PyAutoGUI server not responding" }

    # -------------------------------------------------------------------------
    # PyAutoGUI helper functions (JSON action format)
    # -------------------------------------------------------------------------
    function Send-PyAG {
        param([string]$JsonCmd)
        try {
            $tc = New-Object System.Net.Sockets.TcpClient
            $tc.Connect("127.0.0.1", $pyagPort)
            $sw = New-Object System.IO.StreamWriter($tc.GetStream())
            $sr = New-Object System.IO.StreamReader($tc.GetStream())
            $sw.WriteLine($JsonCmd); $sw.Flush()
            $resp = $sr.ReadLine()
            $tc.Close()
            return $resp
        } catch { return $null }
    }
    function PyAG-Click  { param([int]$X, [int]$Y)
        Send-PyAG ('{"action":"click","x":' + $X + ',"y":' + $Y + '}') | Out-Null
        Start-Sleep -Milliseconds 600 }
    function PyAG-Press  { param([string]$Key)
        Send-PyAG ('{"action":"press","key":"' + $Key + '"}') | Out-Null
        Start-Sleep -Milliseconds 400 }
    function PyAG-Hotkey { param([string[]]$Keys)
        $kj = ($Keys | ForEach-Object { "`"$_`"" }) -join ","
        Send-PyAG ('{"action":"hotkey","keys":[' + $kj + ']}') | Out-Null
        Start-Sleep -Milliseconds 400 }

    # -------------------------------------------------------------------------
    # Section 4: Suppress Windows auto-features
    # -------------------------------------------------------------------------
    Write-Host "--- Section 4: Suppressing Windows auto-features ---"

    $edgePolicies = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    New-Item -Path $edgePolicies -Force | Out-Null
    Set-ItemProperty -Path $edgePolicies -Name "RestoreOnStartup"    -Value 5 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $edgePolicies -Name "StartupBoostEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $edgePolicies -Name "BackgroundModeEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue

    $ErrorActionPreference = "Continue"
    Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    for ($k = 0; $k -lt 3; $k++) {
        Get-Process -Name "msedge" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    netsh advfirewall set allprofiles state off 2>$null
    $ErrorActionPreference = "Stop"

    # -------------------------------------------------------------------------
    # Section 5: Configure activation bypass registry
    # TopoCal (VB6) reads settings from HKCU\Software\VB and VBA Program Settings\TopoCal
    # Termina=1 signals completed activation; Idioma=EN is an additional bypass flag.
    # Note: TopoCal menus stay in SPANISH because no EN translation file exists.
    # -------------------------------------------------------------------------
    Write-Host "--- Section 5: Configuring activation bypass registry ---"

    $base = "HKCU:\Software\VB and VBA Program Settings\TopoCal"
    Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    New-Item -Path $base -Force | Out-Null

    New-Item -Path "$base\TopoCal Proceso" -Force | Out-Null
    Set-ItemProperty -Path "$base\TopoCal Proceso" -Name "Termina"  -Value "1"
    Set-ItemProperty -Path "$base\TopoCal Proceso" -Name "conecta"  -Value "0"
    Set-ItemProperty -Path "$base\TopoCal Proceso" -Name "Systema"  -Value "W10_64"
    Set-ItemProperty -Path "$base\TopoCal Proceso" -Name "Usu"      -Value "Docker"
    Set-ItemProperty -Path "$base\TopoCal Proceso" -Name "Codigo17" -Value "00000-00000-00000-00000"
    Set-ItemProperty -Path "$base\TopoCal Proceso" -Name "Placa"    -Value "VirtIO"
    # Codigo16 with ' x' suffix triggers the Lite activation HTTP call when Continuar is clicked.
    # The HTTP server returns '*' for contador_25lite, which is the correct VB6 success response.
    Set-ItemProperty -Path "$base\TopoCal Proceso" -Name "Codigo16" -Value "16a40-5aa91-906db-30388 x"

    New-Item -Path "$base\TopoCal Valores" -Force | Out-Null
    Set-ItemProperty -Path "$base\TopoCal Valores" -Name "version" -Value "3"
    Set-ItemProperty -Path "$base\TopoCal Valores" -Name "trs"     -Value "0"
    Set-ItemProperty -Path "$base\TopoCal Valores" -Name "mira"    -Value "0"

    New-Item -Path "$base\TopoCal Configuaracion" -Force | Out-Null
    # NOTE: Do NOT set Idioma=EN — TopoCal 2025 has no EN translation file.
    # Setting Idioma=EN causes "Traduce_Menu - Error nº 76: Path not found" crash.
    # TopoCal UI stays in Spanish (Archivo, MDT, Curvas de nivel, Perfil, etc.).

    New-Item -Path "$base\TopoCal Preferencias" -Force | Out-Null

    New-Item -Path "$base\TopoCal Errores" -Force | Out-Null
    Set-ItemProperty -Path "$base\TopoCal Errores" -Name "Cerrado Bien" -Value "1"
    Set-ItemProperty -Path "$base\TopoCal Errores" -Name "Cantidad"     -Value "0"

    New-Item -Path "$base\TopoCal Inicio" -Force | Out-Null
    Set-ItemProperty -Path "$base\TopoCal Inicio" -Name "Escal_grafica" -Value "True"

    New-Item -Path "$base\TopoCal Tiempo" -Force | Out-Null
    Set-ItemProperty -Path "$base\TopoCal Tiempo" -Name "Total"   -Value "100"
    Set-ItemProperty -Path "$base\TopoCal Tiempo" -Name "Ordenes" -Value "50"
    Set-ItemProperty -Path "$base\TopoCal Tiempo" -Name "Puntos"  -Value "30"

    Write-Host "Activation bypass registry configured"

    # -------------------------------------------------------------------------
    # Section 6: Set compatibility mode
    # -------------------------------------------------------------------------
    Write-Host "--- Section 6: Setting compatibility mode ---"

    $compatPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
    New-Item -Path $compatPath -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $compatPath -Name $exePath -Value "~ WINXPSP3" -ErrorAction SilentlyContinue
    Write-Host "Set compatibility mode to Windows XP SP3"

    # -------------------------------------------------------------------------
    # Section 7: Update LaunchTC batch file with verified install path
    # -------------------------------------------------------------------------
    Write-Host "--- Section 7: Updating LaunchTC batch file ---"

    $batchContent = "@echo off`r`ncd /d `"$installDir`"`r`nstart `"`" `"$exeName`""
    Set-Content -Path "C:\Users\Docker\launch_topocal.bat" -Value $batchContent -Encoding ASCII
    Write-Host "Updated launch_topocal.bat"

    # -------------------------------------------------------------------------
    # Section 8: Warm-up launch — handle activation dialog
    #
    # TopoCal activation flow (HTTP server returns version19=9.0.961, contador_25lite=*):
    #  1. TopoCal starts → shows "Activar TopoCal 2025" dialog (VB6 form, modal)
    #  2. We click "Ejecutar Lite" icon (~835, 370)
    #     → Transitions to the "Versión Lite / Continuar" page
    #  3. We click the green checkmark icon (~668, 200) to highlight it
    #  4. We click the "Continuar" text label (~668, 230) to trigger activation
    #     → TopoCal requests topocal.com endpoints (redirected to localhost:80):
    #          contador_25lite   -> *     (Lite activation success)
    #          version19         -> 9.0.961
    #          fechaoferta       -> 01/01/2020
    #  5. Lite check passes ("*" is the correct VB6 success response)
    #  6. We use win32 API to hide the activation dialog and show the main CAD window
    #
    # NOTE: The "Continuar" visual element is a VB6 PictureBox, NOT a CommandButton.
    #       The checkmark icon click (y~200) highlights; the text click (y~230) activates.
    #       The NOP-patched DLL (6×NOP at 0x6CDE1) prevents a conditional exit that
    #       otherwise fires after the PictureBox click event.
    # -------------------------------------------------------------------------
    Write-Host "--- Section 8: Warm-up launch with activation handling ---"

    if (Test-Path $exePath) {
        # Kill any stale TopoCal processes
        Get-Process | Where-Object { $_.ProcessName -match "TopoCal|Topo3" } |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        Start-ScheduledTask -TaskName "LaunchTC"
        Write-Host "Launched TopoCal via schtask..."

        # Wait for TopoCal process to appear
        $tcFound = $false
        for ($w = 0; $w -lt 30; $w++) {
            if (Get-Process | Where-Object { $_.ProcessName -match "TopoCal|Topo3" }) {
                Write-Host "TopoCal process detected"
                $tcFound = $true
                break
            }
            Start-Sleep -Seconds 2
        }

        if ($tcFound -and $pyagConnected) {
            # Allow activation dialog to fully render
            Start-Sleep -Seconds 10

            # Step 1: Click "Ejecutar Lite" icon
            Write-Host "Clicking 'Ejecutar Lite' (~835, 370)..."
            PyAG-Click -X 835 -Y 370
            Start-Sleep -Seconds 4

            # Step 2: Click the green checkmark icon to highlight it
            Write-Host "Clicking checkmark icon (~668, 200)..."
            PyAG-Click -X 668 -Y 200
            Start-Sleep -Seconds 2

            # Step 3: Click the "Continuar" text to trigger Lite activation
            Write-Host "Clicking 'Continuar' text (~668, 230)..."
            PyAG-Click -X 668 -Y 230
            Start-Sleep -Seconds 8

            # Step 4: Verify activation via HTTP log
            $httpLog = ""
            try { $httpLog = Get-Content "C:\Users\Docker\http_server.log" -Raw -ErrorAction SilentlyContinue } catch {}
            if ($httpLog -match "contador_25lite") {
                Write-Host "SUCCESS: Lite activation HTTP call confirmed"
            } else {
                Write-Host "WARNING: contador_25lite not found in HTTP log"
            }

            # Step 5: Use win32 API to hide activation dialog and show main CAD window
            Write-Host "Switching to main CAD window via win32..."
            $showWindowScript = @'
import ctypes
from ctypes import wintypes
import time

u = ctypes.windll.user32
WNDENUMPROC = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)

def get_text(h):
    n = u.GetWindowTextLengthW(h)
    if n == 0: return ''
    b = ctypes.create_unicode_buffer(n+1)
    u.GetWindowTextW(h, b, n+1)
    return b.value

windows = {}
def enum_top(h, lp):
    t = get_text(h)
    if 'Activar TopoCal' in t:
        windows['activar'] = h
    elif 'TopoCal 2025' in t and 'Dibujo' in t:
        windows['main'] = h
    return True

u.EnumWindows(WNDENUMPROC(enum_top), 0)

if 'activar' in windows:
    u.ShowWindow(windows['activar'], 0)  # SW_HIDE
    time.sleep(0.5)

if 'main' in windows:
    u.ShowWindow(windows['main'], 5)  # SW_SHOW
    time.sleep(0.3)
    u.ShowWindow(windows['main'], 9)  # SW_RESTORE
    time.sleep(0.3)
    u.SetForegroundWindow(windows['main'])
    print('MAIN_WINDOW_VISIBLE')
else:
    print('MAIN_WINDOW_NOT_FOUND')
'@
            Set-Content -Path "C:\Windows\Temp\show_cad.py" -Value $showWindowScript -Encoding UTF8
            $pyResult = python "C:\Windows\Temp\show_cad.py" 2>&1
            Write-Host "Window switch result: $pyResult"

            if ($pyResult -match "MAIN_WINDOW_VISIBLE") {
                Write-Host "SUCCESS: TopoCal main CAD window is now visible"
            } else {
                Write-Host "WARNING: Could not show main CAD window"
            }

            Start-Sleep -Seconds 3
        }

        # Close TopoCal for checkpoint (no file to save)
        Start-Sleep -Seconds 3
        if ($pyagConnected) { PyAG-Hotkey -Keys @("alt", "F4"); Start-Sleep -Seconds 5 }
        Get-Process | Where-Object { $_.ProcessName -match "TopoCal|Topo3" } |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        Write-Host "Warm-up complete"
    } else {
        Write-Host "WARNING: TopoCal executable not found, skipping warm-up"
    }

    # -------------------------------------------------------------------------
    # Section 9: Write ready marker
    # -------------------------------------------------------------------------
    Write-Host "--- Section 9: Writing ready marker ---"
    Set-Content -Path "C:\Windows\Temp\topocal_ready.marker" -Value "$(Get-Date)"

    Write-Host "=== TopoCal setup complete ==="
    Write-Host "NOTE: TopoCal UI is in Spanish (Archivo, MDT, Curvas de nivel, Perfil...)"

} catch {
    Write-Host "ERROR during setup: $_"
    Write-Host $_.ScriptStackTrace
} finally {
    try { Stop-Transcript | Out-Null } catch {}
}
