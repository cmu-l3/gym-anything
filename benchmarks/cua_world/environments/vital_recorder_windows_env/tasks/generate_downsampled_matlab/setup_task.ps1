# Note: This file is named .sh but contains PowerShell content as per environment requirement
# It should be saved as setup_task.ps1 in the environment
Write-Host "=== Setting up generate_downsampled_matlab task ==="

# 1. Define Paths
$DataDir = "C:\Users\Docker\Documents\VitalRecorder"
$CaseFile = "$DataDir\case6.vital"
$CaseUrl = "https://api.vitaldb.net/cases/6"
$TimeFile = "C:\tmp\task_start_time.txt"
$InitialStateFile = "C:\tmp\initial_state.txt"

# 2. Prepare Directories
if (-not (Test-Path -Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir | Out-Null
}
if (-not (Test-Path -Path "C:\tmp")) {
    New-Item -ItemType Directory -Path "C:\tmp" | Out-Null
}

# 3. Clean Previous Artifacts
$OutputFile = "$DataDir\engineering_data.mat"
if (Test-Path $OutputFile) {
    Remove-Item $OutputFile -Force
}

# 4. Download Real Data (VitalDB Case 6) if missing
if (-not (Test-Path $CaseFile)) {
    Write-Host "Downloading VitalDB Case #6..."
    try {
        Invoke-WebRequest -Uri $CaseUrl -OutFile $CaseFile -UseBasicParsing
    } catch {
        Write-Error "Failed to download data: $_"
        exit 1
    }
}

# 5. Record Start Time (Anti-gaming)
$StartTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
Set-Content -Path $TimeFile -Value $StartTime

# 6. Start Application
Write-Host "Launching Vital Recorder..."
# Kill existing instances
Get-Process VitalRecorder -ErrorAction SilentlyContinue | Stop-Process -Force

# Start VitalRecorder with the case file
Start-Process "C:\Program Files (x86)\VitalRecorder\VitalRecorder.exe" -ArgumentList "`"$CaseFile`""

# 7. Wait for Window and Maximize
Write-Host "Waiting for application window..."
Start-Sleep -Seconds 5

$vrProcess = Get-Process VitalRecorder -ErrorAction SilentlyContinue
if ($vrProcess) {
    # Simple maximization attempt via powershell
    # (In a real scenario, we might use a small C# snippet or nircmd if available)
    # Here we rely on the agent seeing the window, but we give it time to load
    Start-Sleep -Seconds 5
} else {
    Write-Error "Vital Recorder failed to start."
}

Write-Host "=== Task setup complete ==="