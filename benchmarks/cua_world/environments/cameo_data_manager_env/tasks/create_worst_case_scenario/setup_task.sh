# Note: This is actually a PowerShell script (setup_task.ps1) as required by the Windows environment
# The filename in the header is kept as requested, but content is PowerShell

Write-Host "=== Setting up Create Worst Case Scenario Task ==="

# Define paths
$CameoPath = "C:\Program Files (x86)\CAMEO Data Manager\CAMEO Data Manager.exe"
$DataPath = "C:\Users\Public\Documents\CAMEO Data Manager"
$BackupPath = "C:\workspace\data\backups\clean_facility_chemical_only"
$DocsPath = "C:\Users\Docker\Documents"

# 1. Clean up previous run artifacts
Remove-Item "$DocsPath\scenario_report.pdf" -ErrorAction SilentlyContinue
Remove-Item "C:\tmp\task_result.json" -ErrorAction SilentlyContinue

# 2. Record start time
$startTime = [int][double]::Parse((Get-Date -UFormat %s))
Set-Content -Path "C:\tmp\task_start_time.txt" -Value $startTime

# 3. Prepare Database State
# Kill CAMEO if running to unlock DB
Stop-Process -Name "CAMEO Data Manager" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Restore clean DB state (Assumes a backup exists with just Facility+Chemical)
# If specific backup doesn't exist, we assume the environment is pre-loaded or we rely on the agent finding the records
# For this implementation, we'll ensure the app starts clean
if (Test-Path $BackupPath) {
    Copy-Item "$BackupPath\*" "$DataPath\" -Recurse -Force
    Write-Host "Restored clean database state."
}

# 4. Start CAMEO Data Manager
if (-not (Get-Process "CAMEO Data Manager" -ErrorAction SilentlyContinue)) {
    Write-Host "Starting CAMEO Data Manager..."
    Start-Process $CameoPath
    
    # Wait for window
    $timeout = 60
    do {
        Start-Sleep -Seconds 1
        $timeout--
        $window = Get-Process "CAMEO Data Manager" | Where-Object {$_.MainWindowTitle -ne ""}
    } while ($null -eq $window -and $timeout -gt 0)
}

# 5. Maximize Window (using a helper script or simple shortcut if available)
# In Windows env without wmctrl, we rely on the app remembering state or agent handling it.
# However, we can try to maximize via powershell call to user32.dll if needed, 
# but usually simply starting it is enough for the VLM agent.

# 6. Take Initial Screenshot
# (Assuming a screenshot tool exists in the path or using python)
python -c "import pyautogui; pyautogui.screenshot('C:\\tmp\\task_initial.png')"

Write-Host "=== Setup Complete ==="