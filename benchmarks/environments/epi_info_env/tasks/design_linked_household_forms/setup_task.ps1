# Note: The environment runs Windows, so this is a PowerShell script saved as setup_task.ps1
# The framework executes it via the command specified in task.json.

Write-Host "=== Setting up task: design_linked_household_forms ==="

# Define paths
$ProjectDir = "C:\Users\Docker\Documents\Epi Info 7\Projects\HouseholdSurvey"
$PrjFile = "$ProjectDir\HouseholdSurvey.prj"
$TimestampFile = "C:\Users\Docker\AppData\Local\Temp\task_start_time.txt"

# 1. Clean up previous runs
If (Test-Path $ProjectDir) {
    Write-Host "Removing existing project directory..."
    Remove-Item -Path $ProjectDir -Recurse -Force
}

# 2. Record start time (Unix timestamp)
$startTime = [int64]((Get-Date).ToUniversalTime() - (Get-Date "1/1/1970")).TotalSeconds
Set-Content -Path $TimestampFile -Value $startTime
Write-Host "Task start time recorded: $startTime"

# 3. Ensure Epi Info 7 is running
$EpiProcess = Get-Process -Name "EpiInfo" -ErrorAction SilentlyContinue
If (-not $EpiProcess) {
    Write-Host "Starting Epi Info 7..."
    Start-Process -FilePath "C:\Epi Info 7\EpiInfo.exe" -WorkingDirectory "C:\Epi Info 7"
    
    # Wait for it to start
    Start-Sleep -Seconds 10
} Else {
    Write-Host "Epi Info 7 is already running."
}

# 4. Attempt to maximize/focus (Basic approach, may depend on available tools)
# In this environment, we rely on the agent to navigate, but ensuring the window is up helps.
# We can use a simple powershell snippet to bring it to front if possible, 
# but standard PS doesn't easily do window management without extra DLLs.
# We'll assume the 'Start-Process' or the existing state is sufficient.

Write-Host "=== Task setup complete ==="