# Note: This is actually a PowerShell script (setup_task.ps1) wrapped in bash logic 
# because the framework expects a script file. In the Windows env, this will be executed via PowerShell.
# We use the .ps1 extension in the hook config, so this content is for setup_task.ps1.

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up Symptom Profile Dashboard Task ==="

# Define paths
$DashboardDir = "C:\Users\Docker\Documents\Epi_Info\Dashboards"
$OutputFile = "$DashboardDir\SymptomProfile.cvs7"
$StartTimeFile = "C:\Users\Docker\AppData\Local\Temp\task_start_time.txt"

# 1. Record Start Time (Unix Timestamp)
$StartTime = [int][double]::Parse((Get-Date -UFormat %s))
$StartTime | Set-Content $StartTimeFile
Write-Host "Task start time recorded: $StartTime"

# 2. Cleanup Previous Outputs
if (Test-Path $OutputFile) {
    Remove-Item $OutputFile -Force
    Write-Host "Removed existing output file."
}

# 3. Ensure Dashboard Directory Exists
if (-not (Test-Path $DashboardDir)) {
    New-Item -ItemType Directory -Path $DashboardDir -Force | Out-Null
}

# 4. Clean Application State
# Close any running Epi Info instances
Stop-Process -Name "EpiInfo" -ErrorAction SilentlyContinue
Stop-Process -Name "AnalysisDashboard" -ErrorAction SilentlyContinue
Stop-Process -Name "Enter" -ErrorAction SilentlyContinue

# 5. Launch Visual Dashboard
# We launch the Dashboard module directly to save the agent one step and ensure correct window
$DashboardExe = "C:\Program Files (x86)\Epi Info 7\AnalysisDashboard.exe"

if (Test-Path $DashboardExe) {
    Write-Host "Launching Visual Dashboard..."
    Start-Process $DashboardExe
    
    # Wait for window to initialize
    Start-Sleep -Seconds 5
    
    # Attempt to maximize window (using simplistic method, usually agent handles this)
    # Note: Specific window manipulation in Windows containers/remote desktop 
    # is often best left to the agent or done via specific C# calls, 
    # but strictly simply starting the process is sufficient for 'Starting State'.
} else {
    Write-Error "Epi Info Dashboard executable not found at $DashboardExe"
    exit 1
}

Write-Host "=== Setup Complete ==="