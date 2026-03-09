# Note: In the equest_env (Windows), this file should be saved as setup_task.ps1
# The framework handles the extension, but here is the PowerShell content.

Write-Host "=== Setting up Central Plant Chiller Setup Task ==="

# Define paths
$ProjectDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
$ProjectFile = "$ProjectDir\4StoreyBuilding.inp"
$MarkerFile = "C:\Users\Docker\task_start_time.txt"

# 1. Record Start Time
$StartTime = Get-Date -UFormat %s
$StartTime | Out-File -FilePath $MarkerFile -Encoding ascii -Force

# 2. Ensure eQUEST is running with the project
# Check if eQUEST is already running
$eQuestProcess = Get-Process -Name "equest" -ErrorAction SilentlyContinue

if (-not $eQuestProcess) {
    Write-Host "Starting eQUEST..."
    # Start eQUEST directly opening the project
    Start-Process -FilePath "C:\Program Files (x86)\eQUEST 3-65\eQUEST.exe" -ArgumentList "`"$ProjectFile`"" -WindowStyle Maximized
    
    # Wait for the window to settle
    Start-Sleep -Seconds 15
} else {
    Write-Host "eQUEST is already running."
    # We assume the correct project is loaded if it's open, or user will handle it.
    # ideally we might close and reopen to ensure clean state, but for speed we'll trust the env state or agent.
}

# 3. Focus and Maximize Window (using nircmd or just ensuring it's top)
# In this env, we use a helper or just rely on start-process maximized.
# We can try to use a simple shell object to activate the window if needed, but Start-Process usually handles it.

# 4. Take Initial Screenshot
Write-Host "Capturing initial screenshot..."
Get-Screenshot -OutputPath "C:\Users\Docker\task_initial.png"

Write-Host "=== Setup Complete ==="