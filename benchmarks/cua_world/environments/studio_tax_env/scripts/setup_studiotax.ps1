# setup_studiotax.ps1 — post_start hook
# Configures StudioTax 2024 environment after Windows boots

$ErrorActionPreference = "Stop"

$logFile = "C:\Users\Docker\env_setup_post_start.log"
Start-Transcript -Path $logFile -Force

Write-Host "=== Setting up StudioTax 2024 environment ==="

# Source shared utilities
. "C:\workspace\scripts\task_utils.ps1"

# Create working directories
$taxDir = "C:\Users\Docker\Documents\StudioTax"
$scenarioDir = "C:\Users\Docker\Desktop\TaxScenarios"
New-Item -ItemType Directory -Force -Path $taxDir | Out-Null
New-Item -ItemType Directory -Force -Path $scenarioDir | Out-Null

# Copy scenario data files to Desktop
Write-Host "Copying tax scenario data files..."
if (Test-Path "C:\workspace\data") {
    Copy-Item "C:\workspace\data\*" -Destination $scenarioDir -Force -Recurse
    Write-Host "Scenario files copied to $scenarioDir"
} else {
    Write-Host "WARNING: No data directory found at C:\workspace\data"
}

# Find StudioTax executable
$studioTaxExe = Find-StudioTaxExe
if (-not $studioTaxExe) {
    Write-Host "WARNING: StudioTax executable not found. Skipping warm-up launch."
    Write-Host "Task setup scripts will attempt to locate and launch StudioTax."
    Write-Host "=== StudioTax 2024 setup complete (with warnings) ==="
    Stop-Transcript
    exit 0
}
Write-Host "StudioTax executable: $studioTaxExe"

# Disable OneDrive (common Windows 11 annoyance)
Write-Host "Disabling OneDrive..."
$ErrorActionPreference = "Continue"
Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process OneDriveSetup -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Remove OneDrive from startup
$startupKeys = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
)
foreach ($key in $startupKeys) {
    if (Test-Path $key) {
        Remove-ItemProperty -Path $key -Name "OneDrive" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $key -Name "OneDriveSetup" -ErrorAction SilentlyContinue
    }
}

# Disable OneDrive via Group Policy
$oneDrivePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
New-Item -Path $oneDrivePolicy -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path $oneDrivePolicy -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -ErrorAction SilentlyContinue

# Disable Windows consumer features
$cloudPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
New-Item -Path $cloudPolicy -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path $cloudPolicy -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -ErrorAction SilentlyContinue

$ErrorActionPreference = "Stop"

# Warm-up launch of StudioTax to dismiss first-run dialogs
Write-Host "Performing warm-up launch of StudioTax..."
Launch-StudioTaxInteractive -StudioTaxExe $studioTaxExe -WaitSeconds 20

# Wait for window to appear
Start-Sleep -Seconds 5

# Dismiss any first-run dialogs via PyAutoGUI
Write-Host "Dismissing startup dialogs..."
$dismissScript = @'
import socket, json, time

def send_cmd(cmd):
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
    except:
        return {'success': False}

# Dismiss any dialogs with Escape key
send_cmd({'action': 'press', 'key': 'escape'})
time.sleep(1)
send_cmd({'action': 'press', 'key': 'escape'})
time.sleep(1)
send_cmd({'action': 'press', 'key': 'enter'})
time.sleep(1)
send_cmd({'action': 'press', 'key': 'escape'})
'@

$pyScript = "C:\Windows\Temp\dismiss_warmup.py"
Set-Content -Path $pyScript -Value $dismissScript
Start-Process -FilePath "python" -ArgumentList $pyScript -Wait -NoNewWindow -ErrorAction SilentlyContinue
Remove-Item $pyScript -Force -ErrorAction SilentlyContinue

# Kill StudioTax after warm-up
Write-Host "Closing StudioTax after warm-up..."
$ErrorActionPreference = "Continue"
Get-Process -Name "StudioTax*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process -Name "CheckUpdates" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$ErrorActionPreference = "Stop"

# Minimize any cmd.exe windows via PyAutoGUI (Win+D then click away)
$ErrorActionPreference = "Continue"
Get-Process cmd -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.MainWindowHandle -ne [IntPtr]::Zero) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Window {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
        [Win32Window]::ShowWindow($_.MainWindowHandle, 6) | Out-Null
    }
}
$ErrorActionPreference = "Stop"

Write-Host "=== StudioTax 2024 setup complete ==="
Stop-Transcript
