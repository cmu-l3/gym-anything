# Note: This environment is Windows-based. The task.json points to .ps1 files.
# However, for consistency with the prompt requirements, I am providing the content 
# that would go into the setup script. In a real deployment, this logic is inside 
# the setup_task.ps1 file referenced in task.json.

# --- CONTENT OF C:\workspace\tasks\evaluate_sinus_proximity\setup_task.ps1 ---
<#
.SYNOPSIS
Sets up the evaluate_sinus_proximity task in Blue Sky Plan.
#>

$ErrorActionPreference = "Stop"
Write-Output "=== Setting up Sinus Evaluation Task ==="

# 1. Timestamp for anti-gaming
$startTime = Get-Date -UFormat %s
$startTime | Out-File -Encoding ASCII "C:\tmp\task_start_time.txt"

# 2. Cleanup previous runs
Remove-Item -Path "C:\Users\Docker\Documents\sinus_evaluation_report.txt" -ErrorAction SilentlyContinue
Remove-Item -Path "C:\tmp\task_result.json" -ErrorAction SilentlyContinue

# 3. Create Ground Truth (Hidden)
# In a real scenario, this would be based on the specific DICOM loaded.
# Here we mock the ground truth for the default training case.
$groundTruthDir = "C:\workspace\ground_truth"
if (-not (Test-Path $groundTruthDir)) {
    New-Item -ItemType Directory -Path $groundTruthDir -Force
}

$groundTruth = @{
    "pos_3_height_mm" = 8.5
    "pos_14_height_mm" = 12.2
    "pos_3_decision" = "Sinus lift required"
    "pos_14_decision" = "Standard placement"
}
$groundTruth | ConvertTo-Json | Out-File -Encoding ASCII "$groundTruthDir\sinus_heights.json"

# 4. Ensure Blue Sky Plan is running
$bspProcess = Get-Process -Name "BlueSkyPlan" -ErrorAction SilentlyContinue
if (-not $bspProcess) {
    Write-Output "Starting Blue Sky Plan..."
    Start-Process "C:\Program Files\Blue Sky Bio\Blue Sky Plan\BlueSkyPlan.exe"
    Start-Sleep -Seconds 15
}

# 5. Wait for window and maximize (using helper if available, or just waiting)
# Assuming a helper script 'window_utils.ps1' exists or standard tools
# Here we simulate the wait
Write-Output "Waiting for application to be ready..."
Start-Sleep -Seconds 5

# 6. Load Data (Simulated keystrokes if not loadable via CLI)
# Assuming the default case loads on start or we trigger a load
# Ideally, we open a specific project file
$projectPath = "C:\workspace\data\Default_Patient.bsp"
if (Test-Path $projectPath) {
    Start-Process "C:\Program Files\Blue Sky Bio\Blue Sky Plan\BlueSkyPlan.exe" -ArgumentList $projectPath
    Start-Sleep -Seconds 10
}

# 7. Initial Screenshot
# Uses a screen capture tool available in the env (e.g., nircmd or built-in)
# powershell -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^{PRTSC}')"
# For this env, we assume 'scrot' or similar is not native Windows, but 'nircmd' might be.
# We'll rely on the framework's automatic recording, but creating a marker file is good.

Write-Output "=== Task setup complete ==="