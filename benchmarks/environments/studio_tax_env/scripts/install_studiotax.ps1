# install_studiotax.ps1 — pre_start hook
# Downloads and installs StudioTax 2024 on Windows 11
# The installer is Advanced Installer based and requires GUI interaction.
# We launch it via schtasks /IT in the interactive desktop session, then
# automate clicking through the wizard using PyAutoGUI.

$ErrorActionPreference = "Stop"

$logFile = "C:\Users\Docker\env_setup_pre_start.log"
Start-Transcript -Path $logFile -Force

Write-Host "=== Installing StudioTax 2024 ==="

# Check if already installed — correct path from testing:
# C:\Program Files\BHOK IT Consulting Inc\StudioTax 2024\StudioTax.exe
$installPaths = @(
    "C:\Program Files\BHOK IT Consulting Inc\StudioTax 2024\StudioTax.exe",
    "C:\Program Files (x86)\BHOK IT Consulting Inc\StudioTax 2024\StudioTax.exe",
    "C:\Program Files\BHOK IT Consulting\StudioTax 2024\StudioTax.exe",
    "C:\Program Files (x86)\BHOK IT Consulting\StudioTax 2024\StudioTax.exe"
)

$studioTaxExe = $null
foreach ($path in $installPaths) {
    if (Test-Path $path) {
        $studioTaxExe = $path
        Write-Host "StudioTax already installed at: $studioTaxExe"
        break
    }
}

if (-not $studioTaxExe) {
    # Broader search
    foreach ($searchBase in @("C:\Program Files", "C:\Program Files (x86)")) {
        $found = Get-ChildItem -Path $searchBase -Recurse -Filter "StudioTax.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $studioTaxExe = $found.FullName
            Write-Host "StudioTax found at: $studioTaxExe"
            break
        }
    }
}

if (-not $studioTaxExe) {
    Write-Host "StudioTax not found. Downloading installer..."

    $installerUrl = "https://www.downloadstudiotax.com/ver24/StudioTax2024Install.exe"
    $installerPath = "C:\Windows\Temp\StudioTax2024Install.exe"

    # Download installer
    if (-not (Test-Path $installerPath)) {
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($installerUrl, $installerPath)
            Write-Host "Download complete: $installerPath"
        } catch {
            Write-Host "WebClient download failed: $_"
            Write-Host "Trying Invoke-WebRequest..."
            Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
        }
    } else {
        Write-Host "Installer already cached at $installerPath"
    }

    if (-not (Test-Path $installerPath)) {
        Write-Host "ERROR: Failed to download StudioTax installer"
        Stop-Transcript
        exit 1
    }

    $fileSize = (Get-Item $installerPath).Length
    Write-Host "Installer size: $fileSize bytes"

    # StudioTax uses Advanced Installer — no silent install flag works.
    # We must launch it in the GUI desktop session via schtasks /IT and
    # automate clicking through the wizard using a Python helper script.

    Write-Host "Launching installer in interactive desktop session..."
    $ErrorActionPreference = "Continue"

    # Launch through VBScript so only the installer UI is shown, not a cmd.exe wrapper.
    $launchVbs = "C:\Windows\Temp\launch_installer.vbs"
    $launchVbsContent = 'Set ws = CreateObject("WScript.Shell")' + "`r`n" +
        'ws.Run """' + $installerPath + '""", 1, False'
    Set-Content -Path $launchVbs -Value $launchVbsContent -Encoding ASCII

    # Create and run the scheduled task
    $taskName = "InstallStudioTax"
    schtasks /Delete /TN $taskName /F 2>$null
    schtasks /Create /TN $taskName /TR "wscript.exe $launchVbs" /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN $taskName 2>$null

    Write-Host "Installer launched. Waiting for GUI to appear..."
    Start-Sleep -Seconds 5

    # Now automate clicking through the installer using PyAutoGUI
    # The PyAutoGUI server should already be running on port 5555
    $automationScript = @'
import socket, json, time

def send_cmd(cmd):
    for attempt in range(3):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(10)
            s.connect(('127.0.0.1', 5555))
            s.sendall((json.dumps(cmd) + '\n').encode())
            data = b''
            while True:
                chunk = s.recv(65536)
                if not chunk: break
                data += chunk
                if b'\n' in data: break
            s.close()
            return json.loads(data.decode().split('\n')[0])
        except Exception as e:
            print(f"PyAutoGUI attempt {attempt+1} failed: {e}")
            time.sleep(2)
    return {'success': False}

def click(x, y):
    return send_cmd({'action': 'click', 'x': x, 'y': y})

def press(key):
    return send_cmd({'action': 'press', 'key': key})

def hotkey(*keys):
    return send_cmd({'action': 'hotkey', 'keys': list(keys)})

# Step 0: Close OneDrive popup if it is present.
print("Step 0: Preparing desktop — closing OneDrive if present...")
# Close OneDrive X button
click(1237, 391)
time.sleep(1)

# Now wait for the installer window to appear (it may take a moment)
time.sleep(5)

# Installer wizard steps (coordinates from testing at 1280x720):
# Step 1: Language selection — click "Next >" (816, 590)
print("Step 1: Language selection — clicking Next...")
click(816, 590)
time.sleep(3)

# Step 2: Welcome page — click "Next >" (816, 590)
print("Step 2: Welcome page — clicking Next...")
click(816, 590)
time.sleep(3)

# Step 3: License agreement — accept and click Next
print("Step 3: License — clicking 'I accept' radio button...")
click(535, 517)  # "I accept" radio button
time.sleep(1)
print("Step 3: License — clicking Next...")
click(815, 590)
time.sleep(3)

# Step 4: Ready to Install — click "Install" (815, 590)
print("Step 4: Ready to Install — clicking Install...")
click(815, 590)
time.sleep(60)  # Wait for installation to complete

# Step 5: Finish — click "Finish" (815, 590)
print("Step 5: Setup Complete — clicking Finish...")
click(815, 590)
time.sleep(3)

print("Installation automation complete.")
'@

    $pyAutoScript = "C:\Windows\Temp\automate_install.py"
    Set-Content -Path $pyAutoScript -Value $automationScript

    # Run the automation script
    Write-Host "Running installer automation via PyAutoGUI..."
    $pyProc = Start-Process -FilePath "python" -ArgumentList $pyAutoScript -Wait -PassThru -NoNewWindow
    Write-Host "Automation script exit code: $($pyProc.ExitCode)"

    # Clean up
    schtasks /Delete /TN $taskName /F 2>$null
    Remove-Item $launchVbs -Force -ErrorAction SilentlyContinue
    Remove-Item $pyAutoScript -Force -ErrorAction SilentlyContinue

    $ErrorActionPreference = "Stop"

    # Wait a moment for installer process to fully exit
    Start-Sleep -Seconds 5

    # Clean up installer
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

    # Verify installation
    $studioTaxExe = $null
    foreach ($path in $installPaths) {
        if (Test-Path $path) {
            $studioTaxExe = $path
            break
        }
    }

    if (-not $studioTaxExe) {
        # Deep search for StudioTax.exe
        foreach ($searchBase in @("C:\Program Files", "C:\Program Files (x86)")) {
            $found = Get-ChildItem -Path $searchBase -Recurse -Filter "StudioTax.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $studioTaxExe = $found.FullName
                break
            }
        }
    }

    if ($studioTaxExe) {
        Write-Host "StudioTax installed successfully at: $studioTaxExe"
    } else {
        Write-Host "WARNING: Could not verify StudioTax installation."
    }
}

# Store the install path for other scripts
if ($studioTaxExe) {
    Set-Content -Path "C:\Users\Docker\studiotax_path.txt" -Value $studioTaxExe
    Write-Host "Install path saved to C:\Users\Docker\studiotax_path.txt"
}

Write-Host "=== StudioTax installation phase complete ==="
Stop-Transcript
