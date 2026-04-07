# setup_garmin_basecamp.ps1 - post_start hook
# Creates and runs an interactive Session 1 script that:
# 1. Launches BaseCamp, imports fells_loop.gpx, backs up AllData.gdb
# Uses SendKeys (System.Windows.Forms) instead of PyAutoGUI TCP
# since we need reliable path input with backslashes

$ErrorActionPreference = "Continue"
$logFile = "C:\Users\Docker\env_setup_post_start.log"
Start-Transcript -Path $logFile -Append | Out-Null

Write-Host "=== Garmin BaseCamp setup started ==="

$toolDir    = "C:\GarminTools"
$backupDir  = "$toolDir\BaseCampBackup"
$markerDone = "$toolDir\setup_done.flag"

New-Item -ItemType Directory -Force -Path $toolDir   | Out-Null
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

# Find BaseCamp
$bcExePaths = @(
    "C:\Program Files (x86)\Garmin\BaseCamp\BaseCamp.exe",
    "C:\Program Files\Garmin\BaseCamp\BaseCamp.exe"
)
$bcExe = $bcExePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bcExe) {
    $found = Get-ChildItem "C:\Program Files*" -Recurse -Filter "BaseCamp.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $bcExe = $found.FullName }
}
if (-not $bcExe) {
    Write-Host "ERROR: BaseCamp.exe not found!"
    Stop-Transcript | Out-Null
    exit 1
}
Write-Host "BaseCamp: $bcExe"
$bcExe | Set-Content "$toolDir\basecamp_path.txt"

# Kill browsers and OneDrive
@("msedge","chrome","firefox","OneDrive") | ForEach-Object {
    Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# Permanently disable OneDrive startup and backup notifications
# This persists in the checkpoint so future task starts won't show the popup
$odPol = "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive"
if (-not (Test-Path $odPol)) { New-Item -Path $odPol -Force | Out-Null }
Set-ItemProperty -Path $odPol -Name "KFMBlockOptIn" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $odPol -Name "PreventNetworkTrafficPreUserSignIn" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue
# Disable OneDrive scheduled tasks
schtasks /Change /TN "\OneDrive Reporting Task-S-1-5-21*" /DISABLE 2>&1 | Out-Null
schtasks /Change /TN "\OneDrive Standalone Update Task-S-1-5-21*" /DISABLE 2>&1 | Out-Null
Write-Host "OneDrive disabled from autostart."

# Clear old markers
Remove-Item $markerDone -ErrorAction SilentlyContinue
Remove-Item "$toolDir\setup_error.txt" -ErrorAction SilentlyContinue

# ─── Write the interactive setup script (runs in Session 1) ───────
$interactiveScript = @'
# interactive_setup.ps1 - runs in Session 1 via schtasks /IT
# Uses SendKeys to interact with BaseCamp GUI

Add-Type -AssemblyName System.Windows.Forms

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinAPI2 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr c, string cls, string wnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(int flags, int dx, int dy, int data, int info);
}
"@

$toolDir    = "C:\GarminTools"
$markerDone = "$toolDir\setup_done.flag"
$markerErr  = "$toolDir\setup_error.txt"
$logFile2   = "$toolDir\interactive_setup.log"
$bcExe      = (Get-Content "$toolDir\basecamp_path.txt" -ErrorAction SilentlyContinue).Trim()
$gpxFile    = "C:\workspace\data\fells_loop.gpx"

"=== Interactive setup started at $(Get-Date) ===" | Out-File $logFile2 -Append

if (-not $bcExe -or -not (Test-Path $bcExe)) {
    "ERROR: BaseCamp not found: $bcExe" | Out-File $logFile2 -Append
    "BaseCamp not found" | Set-Content $markerErr
    exit 1
}

# Dismiss OneDrive if present
$oneDrive = Get-Process "OneDrive" -ErrorAction SilentlyContinue
if ($oneDrive) {
    Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# Launch BaseCamp
"Launching BaseCamp: $bcExe" | Out-File $logFile2 -Append
Start-Process -FilePath $bcExe
Start-Sleep -Seconds 8

# Wait for BaseCamp window
"Waiting for BaseCamp window..." | Out-File $logFile2 -Append
$bc = $null
for ($i = 0; $i -lt 30; $i++) {
    $bc = Get-Process "BaseCamp" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($bc -and $bc.MainWindowHandle -ne [IntPtr]::Zero) { break }
    Start-Sleep -Seconds 2
}

if (-not $bc -or $bc.MainWindowHandle -eq [IntPtr]::Zero) {
    "ERROR: BaseCamp window not found" | Out-File $logFile2 -Append
    "BaseCamp window not found" | Set-Content $markerErr
    exit 1
}

"BaseCamp running (PID=$($bc.Id), hwnd=$($bc.MainWindowHandle))" | Out-File $logFile2 -Append

# Bring BaseCamp to foreground
[WinAPI2]::SetForegroundWindow($bc.MainWindowHandle) | Out-Null
Start-Sleep -Seconds 3

# Dismiss Task Launcher by clicking "Plan a Trip" (NOT ESC - that closes BaseCamp!)
# The Task Launcher IS the BaseCamp main window; ESC/Close on it exits BaseCamp.
"Clicking Plan a Trip to dismiss Task Launcher..." | Out-File $logFile2 -Append
[WinAPI2]::SetCursorPos(443, 210) | Out-Null
Start-Sleep -Milliseconds 200
[WinAPI2]::mouse_event(0x02, 0, 0, 0, 0) | Out-Null
Start-Sleep -Milliseconds 100
[WinAPI2]::mouse_event(0x04, 0, 0, 0, 0) | Out-Null
Start-Sleep -Seconds 5

# Dismiss tutorial/info dialog that appears (ESC to close it)
[System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
Start-Sleep -Seconds 2

# Dismiss "Detailed Map Needed" or "3D Terrain Disabled" dialog if present (click OK at ~806,405)
[WinAPI2]::SetCursorPos(806, 405) | Out-Null
Start-Sleep -Milliseconds 200
[WinAPI2]::mouse_event(0x02, 0, 0, 0, 0) | Out-Null
Start-Sleep -Milliseconds 100
[WinAPI2]::mouse_event(0x04, 0, 0, 0, 0) | Out-Null
Start-Sleep -Seconds 2

# Close Route Planner (returns to main map view)
[System.Windows.Forms.SendKeys]::SendWait("{ESCAPE}")
Start-Sleep -Seconds 2

# Check BaseCamp is still alive
$bc = Get-Process "BaseCamp" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $bc) {
    "ERROR: BaseCamp closed after Task Launcher dismiss" | Out-File $logFile2 -Append
    "BaseCamp closed unexpectedly" | Set-Content $markerErr
    exit 1
}
[WinAPI2]::SetForegroundWindow($bc.MainWindowHandle) | Out-Null

# Open Import dialog (Ctrl+I)
"Opening Import dialog..." | Out-File $logFile2 -Append
[System.Windows.Forms.SendKeys]::SendWait("^i")
Start-Sleep -Seconds 4

# In the file open dialog: set clipboard and paste path
"Typing file path via clipboard..." | Out-File $logFile2 -Append
[System.Windows.Forms.Clipboard]::SetText($gpxFile)
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait("^a")   # Select all in filename field
Start-Sleep -Milliseconds 200
[System.Windows.Forms.SendKeys]::SendWait("^v")   # Paste path
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 6

# Dismiss import success/confirmation dialog
"Dismissing import confirmation..." | Out-File $logFile2 -Append
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Seconds 2
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Seconds 2

"Import command sent. Closing BaseCamp to save data..." | Out-File $logFile2 -Append

# Close BaseCamp (Alt+F4) to trigger save
$bc2 = Get-Process "BaseCamp" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($bc2 -and $bc2.MainWindowHandle -ne [IntPtr]::Zero) {
    [WinAPI2]::SetForegroundWindow($bc2.MainWindowHandle) | Out-Null
    Start-Sleep -Seconds 1
    [System.Windows.Forms.SendKeys]::SendWait("%{F4}")
    Start-Sleep -Seconds 4
    # Confirm save if asked
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Seconds 3
}

# Force kill BaseCamp
Stop-Process -Name "BaseCamp" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# Backup AllData.gdb
$dbSrc = "C:\Users\Docker\AppData\Roaming\Garmin\BaseCamp\Database"
$dbDst = "C:\GarminTools\BaseCampBackup\Database"
"Looking for database at: $dbSrc" | Out-File $logFile2 -Append
if (Test-Path $dbSrc) {
    $gdbFile = Get-ChildItem $dbSrc -Recurse -Filter "AllData.gdb" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gdbFile) {
        "Found AllData.gdb: $($gdbFile.FullName)" | Out-File $logFile2 -Append
    } else {
        "WARNING: AllData.gdb not found (checking DB structure):" | Out-File $logFile2 -Append
        Get-ChildItem $dbSrc -Recurse | Select-Object FullName,Length | Out-File $logFile2 -Append
    }
    if (Test-Path $dbDst) { Remove-Item $dbDst -Recurse -Force }
    Copy-Item $dbSrc $dbDst -Recurse -Force
    "Database backed up to $dbDst" | Out-File $logFile2 -Append
} else {
    "WARNING: Database directory not found: $dbSrc" | Out-File $logFile2 -Append
}

"=== Interactive setup complete at $(Get-Date) ===" | Out-File $logFile2 -Append
"done" | Set-Content $markerDone
'@

$interactiveScript | Set-Content "$toolDir\interactive_setup.ps1" -Encoding UTF8
Write-Host "Interactive setup script written."

# Create batch file to run it (avoids path quoting in schtasks)
@"
@echo off
powershell -ExecutionPolicy Bypass -File "C:\GarminTools\interactive_setup.ps1"
"@ | Set-Content "$toolDir\run_interactive_setup.bat" -Encoding ASCII
Write-Host "Batch launcher written."

# Schedule the interactive setup via schtasks /IT
$taskName = "GarminInteractiveSetup"
$runTime  = (Get-Date).AddMinutes(1).ToString("HH:mm")
Write-Host "Scheduling interactive setup at $runTime..."
schtasks /Create /SC ONCE /IT /TR "$toolDir\run_interactive_setup.bat" /TN $taskName /ST $runTime /F 2>&1 | Write-Host
schtasks /Run /TN $taskName 2>&1 | Write-Host

# Poll for completion marker (max 150 seconds after scheduling)
Write-Host "Waiting for interactive setup (max 150 seconds)..."
$elapsed = 0
$timeout = 150
while ($elapsed -lt $timeout) {
    Start-Sleep -Seconds 5
    $elapsed += 5
    if (Test-Path $markerDone) {
        Write-Host "Setup completed after ${elapsed}s"
        break
    }
    if (Test-Path "$toolDir\setup_error.txt") {
        $err = Get-Content "$toolDir\setup_error.txt" -Raw
        Write-Host "Setup error: $err"
        break
    }
    Write-Host "  Waiting... ${elapsed}s"
}

schtasks /Delete /TN $taskName /F 2>&1 | Out-Null

if (-not (Test-Path $markerDone)) {
    Write-Host "WARNING: Setup did not complete. import_gpx_file task will still work."
}

# Verify BaseCamp is installed
Write-Host "BaseCamp verified: $bcExe"

# Copy GPX files to Desktop
$desktopPath = "C:\Users\Docker\Desktop"
New-Item -ItemType Directory -Force -Path $desktopPath | Out-Null
Copy-Item "C:\workspace\data\fells_loop.gpx"         "$desktopPath\fells_loop.gpx"         -Force -ErrorAction SilentlyContinue
Copy-Item "C:\workspace\data\dole_langres_track.gpx" "$desktopPath\dole_langres_track.gpx" -Force -ErrorAction SilentlyContinue
Write-Host "GPX files on Desktop."

# Disable Edge auto-restore
$edgePol = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (-not (Test-Path $edgePol)) { New-Item -Path $edgePol -Force | Out-Null }
Set-ItemProperty -Path $edgePol -Name "StartupBoostEnabled"   -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $edgePol -Name "BackgroundModeEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue

@("msedge","chrome","OneDrive") | ForEach-Object {
    Stop-Process -Name $_ -Force -ErrorAction SilentlyContinue
}

# Clean up desktop in Session 1 (minimize terminals, close Start menu)
Write-Host "Cleaning up desktop..."
$cleanupScript = "C:\Windows\Temp\cleanup_desktop.ps1"
@'
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Milliseconds 500
(New-Object -ComObject Shell.Application).MinimizeAll()
'@ | Set-Content $cleanupScript -Encoding UTF8
schtasks /Create /TN "CleanupDesktop_GA" /TR "powershell -ExecutionPolicy Bypass -File $cleanupScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
schtasks /Run /TN "CleanupDesktop_GA" 2>$null
Start-Sleep -Seconds 5
schtasks /Delete /TN "CleanupDesktop_GA" /F 2>$null
Remove-Item $cleanupScript -Force -ErrorAction SilentlyContinue

Write-Host "=== Garmin BaseCamp setup complete ==="
Stop-Transcript | Out-Null
