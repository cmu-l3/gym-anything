# PowerShell script to install the PyAutoGUI server on Windows
# Run this script in an elevated PowerShell session

param(
    [string]$ServerPort = "5555",
    [string]$InstallPath = "C:\gym_anything"
)

Write-Host "Installing PyAutoGUI Server for Gym-Anything..." -ForegroundColor Green

# Create installation directory
if (!(Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Write-Host "Created directory: $InstallPath"
}

# Copy the server script (assumes it's in the same directory as this script)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ServerScript = Join-Path $ScriptDir "windows_pyautogui_server.py"

if (Test-Path $ServerScript) {
    Copy-Item $ServerScript -Destination $InstallPath -Force
    Write-Host "Copied server script to $InstallPath"
} else {
    Write-Host "Warning: Server script not found at $ServerScript" -ForegroundColor Yellow
    Write-Host "You'll need to copy windows_pyautogui_server.py to $InstallPath manually"
}

# Create a batch file to start the server
$BatchContent = @"
@echo off
echo Starting PyAutoGUI Server on port $ServerPort...
cd /d $InstallPath
python windows_pyautogui_server.py --port $ServerPort
pause
"@

$BatchPath = Join-Path $InstallPath "start_pyautogui_server.bat"
$BatchContent | Out-File -FilePath $BatchPath -Encoding ASCII
Write-Host "Created startup batch file: $BatchPath"

# Create a VBScript wrapper to run hidden (no window)
$VbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "cmd /c cd /d $InstallPath && python windows_pyautogui_server.py --port $ServerPort", 0, False
"@

$VbsPath = Join-Path $InstallPath "start_pyautogui_server_hidden.vbs"
$VbsContent | Out-File -FilePath $VbsPath -Encoding ASCII
Write-Host "Created hidden startup script: $VbsPath"

# Add to Windows Startup folder
$StartupFolder = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupFolder "PyAutoGUI_Server.lnk"

$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "wscript.exe"
$Shortcut.Arguments = "`"$VbsPath`""
$Shortcut.WorkingDirectory = $InstallPath
$Shortcut.Description = "Start PyAutoGUI Server for Gym-Anything"
$Shortcut.Save()
Write-Host "Created startup shortcut: $ShortcutPath"

# Configure Windows Firewall to allow the server port
Write-Host "Configuring firewall..."
try {
    New-NetFirewallRule -DisplayName "PyAutoGUI Server" -Direction Inbound -Protocol TCP -LocalPort $ServerPort -Action Allow -ErrorAction SilentlyContinue
    Write-Host "Firewall rule added for port $ServerPort"
} catch {
    Write-Host "Warning: Could not add firewall rule. You may need to do this manually." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "The PyAutoGUI server will start automatically when you log in."
Write-Host "To start it manually, run: $BatchPath"
Write-Host ""
Write-Host "To test the server, run from another machine:"
Write-Host "  python windows_pyautogui_client.py <windows-ip> $ServerPort"
Write-Host ""

# Offer to start the server now
$response = Read-Host "Start the server now? (y/n)"
if ($response -eq "y" -or $response -eq "Y") {
    Write-Host "Starting server..."
    Start-Process "wscript.exe" -ArgumentList "`"$VbsPath`""
    Write-Host "Server started in background on port $ServerPort"
}
