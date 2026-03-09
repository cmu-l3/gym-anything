#!/bin/bash
# Wrapper to call the PowerShell setup script in the Windows environment
# The environment executes this hook. Since it is Windows-based, we pass the command to powershell.

# Create the PowerShell setup script
mkdir -p /workspace/tasks/dhw_loop_temperature_and_pump_retrofit

cat > /workspace/tasks/dhw_loop_temperature_and_pump_retrofit/setup_task.ps1 << 'PSEOF'
Write-Host "=== Setting up DHW Retrofit Task ==="

# Define paths
$ProjectDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
$InpFile = "$ProjectDir\4StoreyBuilding.inp"
$MarkerFile = "C:\workspace\tasks\dhw_loop_temperature_and_pump_retrofit\task_start_time.txt"

# 1. Record Start Time (Unix Timestamp)
$startTime = [int64]((Get-Date) - (Get-Date "1/1/1970")).TotalSeconds
Set-Content -Path $MarkerFile -Value $startTime
Write-Host "Task start time recorded: $startTime"

# 2. Ensure eQUEST is running and focused
$proc = Get-Process -Name "equest" -ErrorAction SilentlyContinue
if (-not $proc) {
    Write-Host "Starting eQUEST..."
    Start-Process "C:\Program Files (x86)\eQUEST 3-65\eQUEST.exe" -ArgumentList "$InpFile"
    Start-Sleep -Seconds 10
}

# Wait for window
$loopCount = 0
while ($loopCount -lt 30) {
    if (Get-Process -Name "equest" -ErrorAction SilentlyContinue) {
        Write-Host "eQUEST is running."
        break
    }
    Start-Sleep -Seconds 1
    $loopCount++
}

# 3. Take Initial Screenshot (using python/scrot via WSL or similar tool if available, 
# or assuming the environment handles screenshots. Here we just log.)
# Note: The environment's observation loop handles the main screenshots, 
# but we can try to capture a specific setup state if tools exist.
# In this env, we rely on the gym_anything observation.

Write-Host "=== Setup Complete ==="
PSEOF

# Execute the PowerShell script
powershell -ExecutionPolicy Bypass -File /workspace/tasks/dhw_loop_temperature_and_pump_retrofit/setup_task.ps1