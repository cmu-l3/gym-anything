#!/bin/bash
echo "=== Setting up plan_resupply_distances task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Use PowerShell to set up the Windows environment properly
cat << 'EOF' > /tmp/setup_helper.ps1
# Create output directory and clean any previous outputs
$outDir = "C:\workspace\output"
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
} else {
    Remove-Item -Path "$outDir\*" -Recurse -Force -ErrorAction SilentlyContinue
}

# Kill any running BaseCamp instances
Stop-Process -Name "BaseCamp" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Restore BaseCamp database from backup (ensures Fells Loop data is loaded and clean)
$backupDir = "C:\GarminTools\BaseCampBackup\Database"
$dbDir = Join-Path $env:APPDATA "Garmin\BaseCamp\Database"

if (Test-Path $backupDir) {
    if (Test-Path $dbDir) { 
        Remove-Item -Recurse -Force $dbDir -ErrorAction SilentlyContinue 
    }
    Copy-Item -Recurse $backupDir $dbDir -ErrorAction SilentlyContinue
}

# Launch BaseCamp
$bcExe = "C:\Program Files (x86)\Garmin\BaseCamp\BaseCamp.exe"
if (-not (Test-Path $bcExe)) {
    $bcExe = "C:\Program Files\Garmin\BaseCamp\BaseCamp.exe"
}

if (Test-Path $bcExe) {
    Start-Process $bcExe
    Start-Sleep -Seconds 12

    # Dismiss potential startup dialogs
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait('{ESCAPE}')
    Start-Sleep -Seconds 1
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Start-Sleep -Seconds 1
    [System.Windows.Forms.SendKeys]::SendWait('{ESCAPE}')
} else {
    Write-Host "WARNING: BaseCamp executable not found."
}
EOF

# Execute the setup script
powershell.exe -ExecutionPolicy Bypass -File /tmp/setup_helper.ps1

# Take an initial screenshot (using X11 scrot if available in the env)
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="