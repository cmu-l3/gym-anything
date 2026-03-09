#!/bin/bash
set -e
echo "=== Setting up Audit Anesthetic Adequacy Task ==="

# 1. Prepare Timestamp for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 2. Define Powershell Helper for Windows Setup
# This function executes commands inside the Windows environment via PowerShell
run_powershell() {
    # Using 'su - Docker' or executing directly depending on container setup.
    # Assuming standard setup where we can run powershell directly or via user.
    # The environment description specifies user "Docker" with password.
    # We will use a heredoc to create a temporary ps1 file and run it.
    
    cat << 'PS1EOF' > /tmp/setup_script.ps1
$ErrorActionPreference = "Stop"

# Define Paths
$DocPath = "C:\Users\Docker\Documents\VitalData"
$FilePath = "$DocPath\case0006.vital"
$VitalUrl = "https://api.vitaldb.net/cases/6/vital"

# Create Data Directory
if (-not (Test-Path -Path $DocPath)) {
    New-Item -ItemType Directory -Path $DocPath | Out-Null
    Write-Host "Created data directory: $DocPath"
}

# Download Data File (if not exists)
if (-not (Test-Path -Path $FilePath)) {
    Write-Host "Downloading VitalDB Case #6..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $VitalUrl -OutFile $FilePath
    Write-Host "Download complete."
} else {
    Write-Host "Data file already exists."
}

# Kill existing Vital Recorder
Get-Process -Name "VitalRecorder" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

# Launch Vital Recorder with the file
# Assuming VitalRecorder is in Path or standard location. 
# Adjust path if necessary based on env (e.g., C:\Program Files\VitalRecorder\VitalRecorder.exe)
$VitalPath = "C:\Program Files\VitalRecorder\VitalRecorder.exe"
if (-not (Test-Path $VitalPath)) {
    # Try finding it
    $VitalPath = (Get-Command "VitalRecorder.exe" -ErrorAction SilentlyContinue).Source
}

if ($VitalPath) {
    Write-Host "Launching Vital Recorder with file..."
    Start-Process -FilePath $VitalPath -ArgumentList "`"$FilePath`""
} else {
    Write-Host "WARNING: Vital Recorder executable not found. Agent must launch manually."
}

# Cleanup previous outputs
Remove-Item "C:\Users\Docker\Documents\adequacy_audit.txt" -ErrorAction SilentlyContinue
Remove-Item "C:\Users\Docker\Documents\peak_stress_event.png" -ErrorAction SilentlyContinue

PS1EOF

    # Execute the PowerShell script
    # We assume 'powershell' is in the path and accessible
    powershell -ExecutionPolicy Bypass -File /tmp/setup_script.ps1
}

# Execute the setup
run_powershell

# 3. Wait for Window (Linux-side check using wmctrl if available, or just sleep)
# Since this is a Windows env via VNC/Docker, we rely on the PS script above to launch.
# We'll add a sleep to allow the app to load.
sleep 10

echo "=== Task Setup Complete ==="